from pathlib import Path
import json, hashlib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle
from matplotlib import font_manager

ROOT = Path('E:/competition')
OUT = ROOT / '1_docs/figures'
RUN = Path(__file__).parent
OUT.mkdir(parents=True, exist_ok=True)
font_manager.fontManager.addfont('C:/Windows/Fonts/msyh.ttc')
plt.rcParams.update({'font.family':'Microsoft YaHei','svg.fonttype':'none','pdf.fonttype':42})
C={'ink':'#17324d','muted':'#52667b','blue':'#e5efff','green':'#e5f3e9','yellow':'#fff1cb','red':'#fbe5e3','purple':'#eee6f8','line':'#35516b','ctrl':'#97632b'}
outputs=[]
def page(title, subtitle, h=1000):
    fig,ax=plt.subplots(figsize=(16,h/100),dpi=150)
    fig.subplots_adjust(0,0,1,1); ax.set_xlim(0,1600); ax.set_ylim(h,0); ax.axis('off')
    ax.text(45,42,title,fontsize=23,fontweight='bold',color=C['ink'],va='center')
    ax.text(45,79,subtitle,fontsize=11,color=C['muted'],va='center')
    ax.plot([45,1555],[102,102],color='#ccd7e2',lw=1)
    return fig,ax
def box(ax,x,y,w,h,title,body='',color='blue',fs=11):
    ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle='round,pad=0,rounding_size=9',facecolor=C[color],edgecolor='#9daebc',lw=1))
    ax.text(x+w/2,y+24,title,ha='center',va='center',fontsize=fs+1,fontweight='bold',color=C['ink'])
    if body: ax.text(x+w/2,y+44+(h-49)/2,body,ha='center',va='center',fontsize=fs,color=C['ink'],linespacing=1.65)
def text(ax,x,y,s,fs=10,ha='left',color='muted'):
    ax.text(x,y,s,fontsize=fs,ha=ha,va='center',color=C[color],linespacing=1.6)
def wire(ax,pts,label=None,at=None,ctrl=False):
    col=C['ctrl'] if ctrl else C['line']; style='--' if ctrl else '-'
    for a,b in zip(pts[:-2],pts[1:-1]): ax.plot([a[0],b[0]],[a[1],b[1]],color=col,lw=1.6,ls=style)
    ax.add_patch(FancyArrowPatch(pts[-2],pts[-1],arrowstyle='-|>',mutation_scale=12,lw=1.6,color=col,linestyle=style))
    if label and at: ax.text(*at,label,fontsize=9,color=col,ha='center',va='center',bbox={'facecolor':'white','edgecolor':'none','pad':1.5})
def footer(ax,h,s):
    ax.plot([45,1555],[h-62,h-62],color='#ccd7e2',lw=1)
    text(ax,45,h-34,s,10)
def save(fig,name):
    for ext in ['svg','png','pdf']:
        p=OUT/f'{name}.{ext}'; fig.savefig(p,dpi=170,facecolor='white'); outputs.append(p)
    plt.close(fig)

# Sheet 1: PE and explicitly separate fabric accumulators.
fig,ax=page('01  |  双 INT8 打包 PE 与双路累加单元','建议架构 · W8A8 · 同一权重 × 两个空间位置 · 单 PE 核心 1 DSP48E1 · 非打包累加',1100)
box(ax,45,155,195,180,'输入事务 T','w：signed 8 bit\nx0 / x1：signed 8 bit\nlane_mask：2 bit\nin_valid：1 bit')
box(ax,300,155,270,180,'激活打包 / 权重扩位','x0b = x0 + 128（u8）\nA = {x1[7:0], 9\'b0, x0b}\nA：signed 25 bit\nB = sext18(w)',color='yellow')
box(ax,640,155,315,180,'DSP48E1 纯乘法核心','AREG / BREG → MREG → PREG\nE0 采样       E1          E2\nP = A × B；有效乘积 43 bit\n物理 P 端口 48 bit',color='green')
box(ax,1025,145,280,90,'低通道解包 / 偏置修正','p0 = s17(P[16:0]) − 128w_d',color='yellow',fs=10)
box(ax,1025,270,280,90,'高通道解包 / 借位修正','p1 = s17(P[33:17]) + P[16]',color='yellow',fs=10)
box(ax,1380,155,175,180,'PE 输出','p0 / p1：各 s17\n值域可容纳于 s16\nout_valid\nlane_mask_d',color='green',fs=10)
wire(ax,[(240,245),(300,245)],'3 × 8b',(271,228))
wire(ax,[(570,245),(640,245)],'A25 / B18',(605,226))
wire(ax,[(955,205),(990,205),(990,190),(1025,190)])
wire(ax,[(955,285),(990,285),(990,315),(1025,315)])
wire(ax,[(1305,190),(1380,190)],'s17',(1341,176))
wire(ax,[(1305,315),(1380,315)],'s17',(1341,302))
box(ax,300,405,655,90,'修正权重与侧带对齐流水','w_d / valid / mask；first_k / last_k 由阵列共享延迟至对应采样沿',color='purple',fs=11)
wire(ax,[(150,335),(150,450),(300,450)],ctrl=True)
wire(ax,[(955,435),(1005,435),(1005,247),(1165,247),(1165,235)],'w_d × 128：s17',(1164,249),ctrl=True)
wire(ax,[(955,470),(1465,470),(1465,335)],'out_valid / mask 与 E2 后的乘积对齐',(1250,455),ctrl=True)
text(ax,45,548,'MAC 单元边界：下列累加器位于 DSP 核心外部；两个乘积先解包，再分别累加。',13,color='ink')
box(ax,70,610,245,140,'输出发射 / 信用控制','允许输入空拍\n核心固定延迟、不独立反压\n保证所有在途乘积有接收空间',color='purple',fs=10)
box(ax,420,610,330,140,'Lane 0：INT32 累加器','sext32(p0) → 32-bit 加法器\nacc0：32 FF（活动状态）\nfirst_k：acc0 ← p0\n其余有效项：acc0 ← acc0 + p0',color='green',fs=10)
box(ax,840,610,330,140,'Lane 1：INT32 累加器','sext32(p1) → 32-bit 加法器\nacc1：32 FF（活动状态）\nfirst_k：acc1 ← p1\n其余有效项：acc1 ← acc1 + p1',color='green',fs=10)
box(ax,1270,610,285,140,'Tile 结果读取','等待 last_k 完成累加\n共享读出选择器 / 尾部\n保留 OC / N 标签与 mask\nK 分块间保留 acc',color='blue',fs=10)
wire(ax,[(1525,335),(1525,570),(585,570),(585,610)],'p0：s17 → s32',(665,570))
wire(ax,[(1540,335),(1540,585),(1005,585),(1005,610)],'p1：s17 → s32',(1090,585))
wire(ax,[(315,680),(420,680)],'valid / mask',(367,664),ctrl=True)
wire(ax,[(315,710),(355,710),(355,780),(1005,780),(1005,750)],ctrl=True)
wire(ax,[(750,660),(790,660),(790,803),(1220,803),(1220,660),(1270,660)])
wire(ax,[(1170,710),(1270,710)],'acc1 s32',(1220,694))
box(ax,45,840,735,150,'采样事件合同（基线无解包输出寄存）','E0：输入锁存 → E1：乘法 M → E2：P / 组合解包 → E3：累加器采样\n若增加解包输出寄存：E3 捕获乘积，E4 才累加；所有侧带同步加一级。\n若使用 CE 停顿：DSP、w_d 和侧带必须整体冻结。',color='blue',fs=11)
box(ax,810,840,745,150,'数值与资源约束','禁止对 packed P 跨 K 累加；每个 MAC 单元有 2 × 32-bit 活动累加状态。\nPE 不加 bias、不做 INT8 饱和；首层零点修正只在最终 bias_eff 加一次。\nreset 清空 valid；尾块 mask 禁止累加和写出无效 OC / N。',color='red',fs=11)
footer(ax,1100,'实线：数据   |   棕色虚线：控制 / 侧带   |   s = signed，u = unsigned   |   建议设计图，不代表新阵列已经综合或上板')
save(fig,'yolo_pe_detailed_architecture_20260918')

# Sheet 2: complete engine; data descends by stages.
fig,ax=page('02  |  GEMM 引擎总体架构','建议基线：TO × TN = 8 × 16；Kc = 576；共享尾部 R = 1 / 2；单活动 acc tile',1390)
box(ax,45,135,315,110,'PS / AXI-Lite CSR','模型加载、帧提交、IRQ / 结果消费\nAXI-Lite：32-bit 控制；不搬张量',color='purple')
box(ax,430,135,555,110,'PL 图调度器 / descriptor walker','Conv 命令快照 → cmd_valid / cmd_ready\n几何、X/W/Y 地址、量化参数、frame_id / desc_id',color='purple')
box(ax,1055,135,500,110,'GEMM frontend / tile sequencer','形状校验；OC / N / Kc 遍历；bank 所有权\n共享计数器、mask、tag、错误和在途计数',color='purple')
wire(ax,[(360,190),(430,190)],ctrl=True); wire(ax,[(985,190),(1055,190)],ctrl=True)
box(ax,45,310,315,110,'DDR / PS HP / DMA 适配','建议数据 64 bit / 地址 32 bit\nRRESP / BRESP、4 KiB、背压',color='blue')
box(ax,430,310,310,110,'W / 参数 loader','按 OC-major / K-minor 读取\nbias_eff / M / shift 随 OC 装入',color='blue')
box(ax,810,310,400,110,'X loader / 在线窗口生成','1×1 直接读取；3×3 行段缓存\nCHW；pad：首层 −128，普通层 0',color='blue')
box(ax,1270,310,285,110,'Bank 管理 / 发射准入','FREE → FILLING → READY\n→ READING → FREE\nW/X tag 匹配才发射',color='purple',fs=10)
wire(ax,[(360,365),(430,365)],'W / 参数',(395,348))
wire(ax,[(200,420),(200,450),(1010,450),(1010,420)],'X 源张量读取；完整 im2col 不写 DDR',(640,450))
wire(ax,[(1410,245),(1410,310)],ctrl=True)
box(ax,430,490,310,125,'WBUF：BRAM ping-pong','2 × 576 × 64 bit = 9 KiB\n每 k：8 个 signed INT8 权重\n物理 bank / 写 lane / 读延迟锁定',color='red',fs=10)
box(ax,810,490,400,125,'XBUF：BRAM ping-pong','2 × 576 × 128 bit = 18 KiB\n每 k：16 个 signed INT8 激活\n宽字由多个物理 BRAM bank 组成',color='red',fs=10)
box(ax,45,490,315,125,'参数 / 当前层 LUT 缓存','bias_eff、M：各 s32 / OC\nshift：6 bit；当前 SiLU：256 × 8\nBRAM / LUTRAM；按端口数配置',color='red',fs=10)
wire(ax,[(585,420),(585,490)])
wire(ax,[(1010,420),(1010,490)])
wire(ax,[(430,395),(395,395),(395,470),(200,470),(200,490)])
box(ax,430,690,780,165,'输出驻留广播阵列：8 行 × 16 个输出列','每拍：W[8] 行广播 × X[16] 列广播；共享 k / valid / first / last / mask\n64 个双乘积 PE（64 DSP 核心） → 128 路 INT32 累加\n活动 acc：4096 FF 位 + 加法器；不复制每 PE 控制计数器\nK 分块续累；最后分块完成且 PE 排空后，才允许进入尾部',color='yellow',fs=12)
wire(ax,[(585,615),(585,690)],'64 bit / 有效拍',(585,650))
wire(ax,[(1010,615),(1010,690)],'128 bit / 有效拍',(1010,650))
wire(ax,[(1410,420),(1410,745),(1210,745)],'issue / mask',(1310,728),ctrl=True)
box(ax,45,690,315,165,'数值合同 / 阵列边界','W8A8：两个乘积先解包\nacc 为 s32；不提前量化\n最终 sum = acc + bias_eff\n首层 bias 修正只加一次',color='blue',fs=11)
box(ax,1270,795,285,155,'控制状态 / 事件','LOAD → ISSUE → DRAIN_PE\n最后 K 分块 → TAIL → STORE\n写响应全部成功 → DONE\n非末 K 分块返回 LOAD',color='purple',fs=10)
box(ax,430,925,355,150,'分组读出 / 共享 requant','acc s32 + bias_eff → sum s33\n× M → s64（导出器校验范围）\nRNE ties-to-even → sat INT8\nR = 1 / 2 路起步',color='green',fs=10)
box(ax,865,925,345,150,'SiLU LUT / 线性旁路','地址 = signed INT8 + 128\n输出 INT8；保持软件量化点\nR 路并行须匹配读口 / 副本\n数据 + OC/N 标签同步前进',color='green',fs=10)
wire(ax,[(605,855),(605,925)],'选择有效 OC / N',(605,890))
wire(ax,[(785,1000),(865,1000)],'R × 8b',(825,982))
wire(ax,[(360,550),(380,550),(380,978),(430,978)],'OC 参数',(375,900))
wire(ax,[(360,585),(395,585),(395,1110),(1035,1110),(1035,1075)],'当前层 LUT；装载完成后绑定该命令',(710,1110))
box(ax,430,1160,780,125,'Output FIFO / store engine → DDR 或片上特征缓冲','CHW 行地址；byte pack / WSTRB；跟踪全部写请求与 B 响应\nPL 后继 Add / Concat / Pool / Upsample 自主调度；最终 raw head 留给 PS 后处理\nAXI 写响应全部完成后，才能发布 completion；head buffer 由 PS ACK 后释放',color='blue',fs=11)
wire(ax,[(1210,1025),(1240,1025),(1240,1200),(1210,1200)],'INT8',(1240,1110))
wire(ax,[(430,1215),(25,1215),(25,365),(45,365)],'Y 写入',(82,1140))
wire(ax,[(1210,1260),(1575,1260),(1575,200),(1555,200)],'completion / error',(1390,1243),ctrl=True)
footer(ax,1390,'容量为有效数据量，不是 BRAM 实际颗数。64 DSP 仅含 PE；尾部 DSP、路由与控制须另计。单 acc 基线计算 / 排空分阶段。')
save(fig,'yolo_gemm_detailed_architecture_20260918')

# Sheet 3: array topology without drawing misleading systolic neighbor links.
fig,ax=page('03  |  GEMM 的 PE 阵列展开与驻留状态','Y[OC,N] = W[OC,K] × Xcol[K,N] · 广播外积结构 · 每颗 PE 负责同一 OC 的两个空间位置',1150)
box(ax,245,135,1050,85,'XBUF[k]：128 bit / 拍','X[k,0:15] → 8 对激活；每一对沿同列 PE 广播',color='red',fs=11)
box(ax,45,310,150,340,'WBUF[k]','64 bit / 拍\n\nW[0,k]\nW[1,k]\n…\nW[7,k]\n\n每行广播同一 w',color='red',fs=10)
cols=[270,535,800,1065]; rows=[310,470,630]
clabel=['0','1','…','7']; rlabel=['0','1','7']
for j,x in enumerate(cols):
    text(ax,x+107,260,['X0 / X1','X2 / X3','…','X14 / X15'][j],11,color='ink')
    wire(ax,[(x+107,220),(x+107,285),(x-15,285),(x-15,690),(x,690)])
    for y in rows[:2]: wire(ax,[(x-15,y+65),(x,y+65)])
for i,y in enumerate(rows):
    wire(ax,[(195,y+20),(235,y+20),(235,y-17),(1300,y-17)])
    for j,x in enumerate(cols):
        wire(ax,[(x+75,y-17),(x+75,y)],ctrl=False)
        if j==2:
            box(ax,x,y,215,115,'列对 2 … 6','同样结构 × 5\n每单元：1 DSP + 2 acc',color='yellow',fs=10)
        else:
            box(ax,x,y,215,115,f'PE[{rlabel[i]},{clabel[j]}]','1 DSP：p0 / p1\nacc[OC,2j] / acc[OC,2j+1]\n2 × INT32 FF 状态',color='yellow',fs=10)
ax.text(775,606,'中间 OC 行 2 … 6 按相同结构重复（图中省略）',fontsize=10,ha='center',va='center',color=C['muted'],bbox={'facecolor':'white','edgecolor':'none','pad':2})
box(ax,1350,310,205,435,'全阵列共享控制','k / k_base / K_len\noc_base / n_base\nvalid / first_k / last_k\nOC mask / N mask\n\nW/X BRAM 读延迟\n与 PE 侧带对齐\n\n8 × 8 个打包 PE\n= 64 DSP 核心\n= 128 MAC / 有效拍',color='purple',fs=10)
wire(ax,[(1350,470),(1318,470),(1318,750),(1180,750),(1180,745)],ctrl=True)
box(ax,245,825,640,140,'分组读取活动 acc tile','128 个 s32 状态驻留于阵列；同一输出沿 K 累加\n最后 K 分块结束 → 等待最后乘积落入 acc\n每拍选择 R 个有效输出 → 共享 bias / requant / SiLU\n基线：全部排空之后才复用本 tile',color='green',fs=11)
wire(ax,[(380,745),(380,825)],'acc s32',(380,788))
wire(ax,[(645,745),(645,825)])
wire(ax,[(1180,745),(1180,792),(810,792),(810,825)])
box(ax,945,825,610,140,'扩展与存储预算','8×16：64 PE，4096 bit 活动 acc\n16×16：128 PE，8192 bit 活动 acc\nBRAM 放 W/X/参数/FIFO；活动 acc 先用 FF\n若加 shadow acc 重叠尾部：显式计入迁移带宽和容量',color='blue',fs=11)
text(ax,45,1015,'注意：图中的 8×16 是 128 个输出位置；不是 128 颗 DSP。每颗打包 PE 同时更新两个位置。',13,color='ink')
footer(ax,1150,'权重沿行广播，激活对沿列广播；PE 间没有部分和级联。省略的行列仅为绘图简化，实际数量见右侧统计。')
save(fig,'yolo_gemm_pe_array_20260918')

sources=[ROOT/'1_docs/yolo_pe_design_manual_20260918.md',ROOT/'1_docs/yolo_gemm_design_manual_20260918.md',Path(__file__)]
manifest={'status':'DRAWINGS_GENERATED','scope':'Proposed architecture, not RTL validation','files':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in sources+outputs]}
(RUN/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'outputs':[str(p) for p in outputs]},ensure_ascii=False,indent=2))
