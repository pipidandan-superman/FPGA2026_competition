from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
from copy import deepcopy
import hashlib,json,sys,math
from lxml import etree as E
from PIL import Image,ImageDraw,ImageFont

R=Path(__file__).resolve().parent; W=R.parents[2]
SOURCE=W/'1_docs/doc/AMD AIPC 借用报告 - 模板.docx'
OUT=W/'1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx'
SKILL=Path('C:/Users/Administrator/.codex/plugins/cache/openai-primary-runtime/documents/26.905.11957/skills/documents')
sys.path.insert(0,str(SKILL/'scripts'))
from docx_ooxml_patch import _qn
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main','a':'http://schemas.openxmlformats.org/drawingml/2006/main','wp':'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing','r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships','pic':'http://schemas.openxmlformats.org/drawingml/2006/picture'}
def q(n):p,t=n.split(':');return '{'+ns[p]+'}'+t
def sha(b):return hashlib.sha256(b).hexdigest()
assert sha(SOURCE.read_bytes())=='ebbc3f74bb0e42663e54245efb0624ae4e692cf37f2110a5de9ac75a6dcfefa6'

# Engineering figures are drawn with explicit geometry, not copied sample art.
FONT='C:/Windows/Fonts/msyh.ttc'; BOLD='C:/Windows/Fonts/msyhbd.ttc'
def diagram(name,title,flow=False):
    im=Image.new('RGB',(1700,490),'white'); d=ImageDraw.Draw(im)
    ft=lambda s,b=False:ImageFont.truetype(BOLD if b else FONT,s)
    d.text((850,28),title,font=ft(39,True),anchor='mt',fill='black')
    def box(x,y,w,h,lines,fill='#e8f1f8'):
        d.rectangle((x,y,x+w,y+h),fill=fill,outline='#253746',width=3)
        step=37; yy=y+(h-step*len(lines))/2+step/2
        for line in lines:d.text((x+w/2,yy),line,font=ft(28),anchor='mm',fill='black');yy+=step
    def arrow(points,label=None,pos=None):
        d.line(points,fill='#253746',width=4)
        x,y=points[-1];px,py=points[-2];a=math.atan2(y-py,x-px)
        d.polygon([(x,y),(x-16*math.cos(a-.45),y-16*math.sin(a-.45)),(x-16*math.cos(a+.45),y-16*math.sin(a+.45))],fill='#253746')
        if label:d.text(pos,label,font=ft(24),anchor='mm',fill='black')
    if not flow:
        box(15,110,210,170,['OV5640','DVP 图像采集'])
        box(325,110,365,170,['EES-331 / Zynq-7020','PL 视频链路 / VDMA','PS Linux / PYNQ'])
        box(815,110,365,170,['AMD Ryzen AI PC','YOLOv8n 识别','坐标转换与分拣决策'])
        box(1300,110,375,170,['机械臂及配套控制器','按选型协议执行','抓取与分类放置'])
        arrow([(225,195),(325,195)],'DVP',(275,155))
        arrow([(690,170),(815,170)],'图像上行',(752,137))
        arrow([(815,232),(690,232)],'指令/状态',(752,263))
        arrow([(1180,195),(1300,195)],'控制指令',(1240,155))
        box(355,360,310,86,['ADV7511 / HDMI 显示'])
        arrow([(507,280),(507,360)])
        arrow([(1480,280),(1480,397),(1120,397),(1120,280)],'执行反馈 / 视觉复核',(1300,434))
        d.text((30,473),'总体方案图：网络、AI 推理与执行闭环为后续联调内容',font=ft(23),fill='#404b55',anchor='ls')
    else:
        xs=[25,365,705,1045,1385]; widths=[245,245,245,245,285]
        labels=[['初始化与自检'],['图像采集','与预处理'],['本地识别','与目标定位'],['分拣规划','与指令校验'],['控制器执行','与反馈确认']]
        for x,w,lines in zip(xs,widths,labels):box(x,115,w,125,lines)
        for i in range(4):arrow([(xs[i]+widths[i],178),(xs[i+1],178)])
        box(665,337,420,90,['视觉复核 / 记录任务结果'])
        arrow([(1527,240),(1527,382),(1085,382)])
        arrow([(665,382),(487,382),(487,240)],'下一目标',(562,352))
        box(25,337,355,90,['异常停止与人工确认'],'#fff0e2')
        arrow([(145,240),(145,337)],'超时/故障',(236,284))
        d.text((665,474),'先验证感知与通信，再进行真实物理分拣测试',font=ft(23),fill='#404b55',anchor='ls')
    im.save(R/name)
diagram('architecture.png','系统总设计框图')
diagram('workflow.png','视觉分拣任务流程',True)

with ZipFile(SOURCE) as z:
    entries=z.infolist(); parts={i.filename:z.read(i.filename) for i in entries}
root=E.fromstring(parts['word/document.xml']); body=root.find('w:body',ns); table=body.find('w:tbl',ns); rows=table.findall('w:tr',ns)
def cell(r,c):return rows[r].findall('w:tc',ns)[c]
def prop(parent,name,attrs):
    el=parent.find(name,ns)
    if el is None:el=E.SubElement(parent,q(name))
    for k,v in attrs.items():el.set(q(k),str(v))
    return el
def paragraph(text='',bold=False,size=22):
    p=E.Element(q('w:p')); pp=E.SubElement(p,q('w:pPr'))
    prop(pp,'w:spacing',{'w:after':70,'w:line':270,'w:lineRule':'auto'})
    prop(pp,'w:widowControl',{'w:val':'1'})
    def run(t,b):
        r=E.SubElement(p,q('w:r')); rp=E.SubElement(r,q('w:rPr'))
        prop(rp,'w:rFonts',{'w:cs':'Aptos'})
        prop(rp,'w:sz',{'w:val':size});prop(rp,'w:szCs',{'w:val':size});prop(rp,'w:color',{'w:val':'000000'})
        if b:prop(rp,'w:b',{})
        tt=E.SubElement(r,q('w:t'));tt.text=t;tt.set('{http://www.w3.org/XML/1998/namespace}space','preserve')
    if isinstance(text,tuple):run(text[0],True);run(text[1],False)
    else:run(text,bold)
    return p
def fill(c,text,size=24,bold=False):
    old=c.find('w:p',ns); p=paragraph(text,bold,size)
    # retain source metadata spacing and alignment
    if old is not None and old.find('w:pPr',ns) is not None:
        p.remove(p.find('w:pPr',ns));p.insert(0,deepcopy(old.find('w:pPr',ns)))
    for e in list(c):
        if e.tag!=q('w:tcPr'):c.remove(e)
    c.append(p)
    return p
title=body.find('w:p',ns)
for e in list(title):title.remove(e)
pp=E.SubElement(title,q('w:pPr'));prop(pp,'w:pStyle',{'w:val':'12'});prop(pp,'w:jc',{'w:val':'center'});prop(pp,'w:spacing',{'w:after':160})
tp=paragraph('AMD AIPC 借用报告',True,24)
for rr in tp.findall('w:r',ns):title.append(rr)
fill(cell(0,1),'待确认（模板编号 4062）',22)
fill(cell(1,1),'锐眼·智行——具身智能分拣',24)
for rc in [(2,2),(2,4),(3,2),(3,4),(4,2),(4,4)]:fill(cell(*rc),'待补充',22)
fill(cell(5,1),'AMD RyzenAI 370（32G）\n拟申请',22,True)
# Convert literal newline into an actual line break in this cell.
for t in cell(5,1).findall('.//w:t',ns):
    if '\n' in (t.text or ''):
        a,b=t.text.split('\n');t.text=a;rr=t.getparent();E.SubElement(rr,q('w:br'));E.SubElement(rr,q('w:t')).text=b
fill(cell(5,2),'用途：本地视觉推理与整机联调。\n机型暂按模板拟选，借用期限按批准安排。',22)
for t in cell(5,2).findall('.//w:t',ns):
    if '\n' in (t.text or ''):
        a,b=t.text.split('\n');t.text=a;rr=t.getparent();E.SubElement(rr,q('w:br'));E.SubElement(rr,q('w:t')).text=b
fill(cell(6,0),'总设计框图',22,True)

first=[
 ('项目与申请目的：','小月文刀队面向 AMD 具身智能赛道，拟申请 1 台 AMD AI PC，用于“锐眼·智行”视觉分拣系统的本地目标识别、抓取决策及与 EES-331 的联合验证。'),
 ('应用任务：','针对桌面小型物体，完成图像采集、类别识别、目标定位、抓取与分类放置，再通过执行反馈和视觉复核确认结果，形成可重复测试的物理闭环。'),
 ('系统分工：','EES-331（Zynq-7020）连接 OV5640，承担 PL 视频采集、VDMA/DDR 帧缓存与 HDMI 显示，并逐步增加预处理。AI PC 运行视觉模型、坐标转换、分拣规划和监控；机械臂通过配套控制器执行任务，具体接口随选型确认。'),
 ('借用必要性：','现有板卡已具备视频前端与 Linux 启动基础，仍需在目标 Ryzen AI 平台上完成模型部署、加速后端适配、网络收发与持续运行测试。借用设备将用于实测精度、延迟和闭环效果，作为系统的实际推理与决策节点。'),
 ('当前工程基础：','已完成 OV5640→VDMA→DDR→HDMI 可视化板测，以及 EES-331 的 SD→Linux Shell 启动；已完成含位流 XSA 到 SD 启动包工具 v0.2 的软件验证。'),
 ('待完成工作：','视频工程与 PYNQ 的整合、板卡网络/Jupyter、新 Overlay、AI PC 推理及机械臂闭环尚需联调。以上已完成项不代表整机或模型性能通过验收。状态截至 2026 年 9 月 10 日。')]
second=[
 ('模型与输出：','拟采用 YOLOv8n，输入为板端上传图像，输出类别、置信度和边界框；经相机标定与坐标转换形成抓取目标及分类位置。使用自采分拣数据训练/验证，模型精度与实际推理速度以借用机测试为准。'),
 ('部署与开发：','AI PC 使用 Python 完成预处理、推理和决策；结合实际机型及驱动验证可用的 GPU/NPU 后端，并保留 CPU 对照。板端使用 Linux/PYNQ 控制 Overlay；PL 逻辑仍由 Vivado 设计，PS 启动配置变化由 XSA 工具重建启动包。'),
 ('接口与数据流：','OV5640 经 DVP 接入 PL，VDMA 经 AXI 访问 DDR，ADV7511 输出 HDMI。板卡与 AI PC 拟采用以太网：图像按 UDP 分帧/分片上传，携带帧号、长度、时间戳及校验信息；任务指令与状态回传配置序号、确认和超时机制。'),
 ('反馈与保护：','执行端回传完成、位置及故障状态，AI PC 结合图像确认分拣结果。通信超时、目标丢失或执行故障时，禁止继续下发动作，按控制器能力请求停止并等待人工确认；急停与互锁在执行端独立落实。'),
 ('借用期间计划：','依次完成环境与模型部署、板卡图像上行和指令回传、机械臂标定与闭环分拣、持续运行及异常恢复测试。控制器协议和机械臂型号在实物接入前确认。'),
 ('预期交付：','提供模型与运行脚本、FPGA/PS 配套版本、通信说明、演示视频及原始测试记录；报告检测精度、吞吐率、端到端 P50/P95/P99 延迟、至少 50 次任务的成功率和人工干预次数。借用及归还时间服从批准安排。')]
for row,content in [(6,first),(7,second)]:
    c=cell(row,1)
    for el in list(c):
        if el.tag!=q('w:tcPr'):c.remove(el)
    for label,txt in content:c.append(paragraph((label,txt)))
    prop(c.find('w:tcPr',ns),'w:tcW',{'w:w':8085,'w:type':'dxa'})
    mar=prop(c.find('w:tcPr',ns),'w:tcMar',{})
    prop(mar,'w:top',{'w:w':80,'w:type':'dxa'});prop(mar,'w:bottom',{'w:w':80,'w:type':'dxa'})
    trp=rows[row].find('w:trPr',ns);prop(trp,'w:cantSplit',{})
    prop(trp,'w:trHeight',{'w:val':405,'w:hRule':'atLeast'})

def picture(rid,idx,label):
    p=paragraph('');p.remove(p.find('w:r',ns));pp=p.find('w:pPr',ns);prop(pp,'w:jc',{'w:val':'center'});prop(pp,'w:spacing',{'w:after':55,'w:line':240,'w:lineRule':'auto'})
    rr=E.SubElement(p,q('w:r'));dr=E.SubElement(rr,q('w:drawing'));inline=E.SubElement(dr,q('wp:inline'),distT='0',distB='0',distL='0',distR='0')
    cx=4960000;cy=round(cx*490/1700)
    E.SubElement(inline,q('wp:extent'),cx=str(cx),cy=str(cy));E.SubElement(inline,q('wp:docPr'),id=str(idx),name=label,descr=label+'。编制与来源核对证据：E:/competition/4_metrics/logs/2026-09-10_aipc_loan_report_run01/REPORT.md')
    graphic=E.SubElement(inline,q('a:graphic'));gd=E.SubElement(graphic,q('a:graphicData'),uri=ns['pic']);pic=E.SubElement(gd,q('pic:pic'))
    nv=E.SubElement(pic,q('pic:nvPicPr'));E.SubElement(nv,q('pic:cNvPr'),id=str(idx),name=label);E.SubElement(nv,q('pic:cNvPicPr'))
    bf=E.SubElement(pic,q('pic:blipFill'));E.SubElement(bf,q('a:blip'),{q('r:embed'):rid});st=E.SubElement(bf,q('a:stretch'));E.SubElement(st,q('a:fillRect'))
    sp=E.SubElement(pic,q('pic:spPr'));xf=E.SubElement(sp,q('a:xfrm'));E.SubElement(xf,q('a:off'),x='0',y='0');E.SubElement(xf,q('a:ext'),cx=str(cx),cy=str(cy));geo=E.SubElement(sp,q('a:prstGeom'),prst='rect');E.SubElement(geo,q('a:avLst'))
    return p
cell(7,1).append(picture('rId6',100001,'系统总设计框图'))
cell(7,1).append(picture('rId7',100000,'视觉分拣任务流程'))
modified={'word/document.xml':E.tostring(root,encoding='UTF-8',xml_declaration=True,standalone=True),
          'word/media/image1.png':(R/'architecture.png').read_bytes(),'word/media/image2.png':(R/'workflow.png').read_bytes()}
with ZipFile(OUT,'w',ZIP_DEFLATED) as z:
    for info in entries:z.writestr(info,modified.get(info.filename,parts[info.filename]))
with ZipFile(OUT) as z:
    preserved=[n for n in parts if n not in modified]
    assert all(z.read(n)==parts[n] for n in preserved)
    assert set(z.namelist())==set(parts)
text='\n'.join(root.xpath('//w:t/text()',namespaces=ns))
for forbidden in ['PYNQ-Z2','YOLO11n','输送带','(示例','方案示例']:assert forbidden not in text
(R/'authored_text.txt').write_text(text,encoding='utf-8')
(R/'package_audit.json').write_text(json.dumps({'result':'TEMPLATE_PACKAGE_PRESERVATION_PASS','source_sha256':sha(SOURCE.read_bytes()),'output':str(OUT),'output_sha256':sha(OUT.read_bytes()),'changed_parts':list(modified),'preserved_parts':{n:sha(parts[n]) for n in preserved},'identity_fields':'PENDING_USER','model':'PROVISIONAL_370_32G'},ensure_ascii=False,indent=2),encoding='utf-8')
print(OUT)
