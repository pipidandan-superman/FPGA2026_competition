# YOLO INT8 GEMM 引擎设计手册

版本：1.0，2026-09-18。目标：在 XC7Z020 上实现可配置、可验证、节省 LUT/FF 的卷积计算引擎。

本文定义建议的新设计；旧源码及旧测试仅作为参考，不表示新设计已完成。配套：[PE 设计手册](yolo_pe_design_manual_20260918.md)、[软件量化审查](yolo_quant_software_audit_20260918.md)、[PL 框图](figures/yolo_int8_pl_architecture_v2.png)。交付范围为文档，不改 RTL、不启动板测。

## 1. 系统定位

GEMM 引擎执行 63 个 Conv：窗口生成、矩阵乘法、累加、偏置、重定标和 SiLU。Add、Concat、MaxPool、Upsample 是同级 PL 图算子，由全局调度器管理，并非都塞入 PE。

PS 负责模型加载、输入准备与帧提交，读取三尺度原始头并执行 DFL、分类 sigmoid、NMS。AXI-Lite 只传控制信息；大数据经 HP/DMA；内部算子通过片上缓存或 PL 自主管理的 DDR 交换，不要求 PS 逐层介入。

### 模块边界

| 模块 | 职责 | 明确不承担 |
|---|---|---|
| CSR/全局调度器 | 提交帧、解释图、buffer 所有权、结果发布 | 卷积内逐 MAC 控制 |
| GEMM frontend | 锁存一条卷积命令、形状检查、tile 遍历 | CPU 后处理 |
| W/X loader | DMA、权重重排、窗口生成、padding | 量化舍入 |
| PE/acc array | 输出驻留整数乘加 | 分支拼接、Softmax |
| shared tail | bias、M/shift、RNE/sat、SiLU/旁路 | 每个 PE 单独复制完整尾部 |
| store engine | 有效输出重排、byte enable、AXI 写响应跟踪 | 以“最后 W 数据发出”冒充完成 |
| 图算子引擎 | Add、重定标 Concat、MaxPool、Upsample、view | 改变软件量化点 |

## 2. 软件计算合同

run04 固定输入 320×320、batch=1，权重逐 OC 对称 INT8，激活逐张量 INT8，普通层零点 0。63 Conv 共 1,011,014,400 MAC、3,001,584 个权重字节；全部卷积输出总量 3,553,900 B，此数不是整网 DDR 流量。

| 维度 | 当前集合/限制 |
|---|---|
| OC | 7、16、32、64、128、256 |
| N=OH×OW | 100、400、1600、6400、25600 |
| K=IC×KH×KW | 27、32、48、64、96、128、144、192、256、288、384、512、576、1152、2304 |
| 卷积 | 1×1 / 3×3，stride 1 / 2，groups=1 |
| 原始头 | reg[64,H,W] 与 cls[7,H,W] 分离尺度，H/W=40、20、10 |

不支持的 batch/groups/dilation/数据宽度必须报错，不能静默用普通卷积解释。扩展支持属于明确的版本变更。

## 3. 卷积到 GEMM 的映射

Y[OC,N]=W[OC,K]×Xcol[K,N]。令 k=ic×KH×KW+kh×KW+kw；n=oy×OW+ox；输入坐标 iy=oy×SH+kh−PH、ix=ox×SW+kw−PW。

逻辑字节地址：

    W_addr = W_base + oc×W_row_stride + k
    X_addr = X_base + ic×IH×IW + iy×IW + ix
    Y_addr = Y_base + oc×OH×OW + n

推荐激活使用 CHW，权重按 OC-major/K-minor 打包；W_row_stride 可为向上对齐 8 字节的 K，但 K 运算长度仍是真实值，不把 K padding 当作真实求和项。总线只约定小端字节顺序，不依赖主机默认大小端。

窗口由 PL 在线生成，不把完整 im2col 写入 DDR。1×1 走直接行读取；3×3 用行段读取和缓存复用。超边界坐标不发 DMA，直接产生正确 pad 值；首层 −128，其余层 0。

例：conv0 是 W[16,27]×Xcol[27,25600]；最后分类 1×1 层为 OC=7，需要 mask 未使用 OC 通路；10×10 特征在 TN=16 时最后一个 N tile 仅 4 个有效位置。

## 4. 阵列结构与推荐档位

采用输出驻留外积阵列：每拍读 TO 个权重、TN 个激活，对所有 TO×TN 输出更新一次。每颗打包 PE 服务一行、两列。它是广播外积结构，不承诺传统逐 PE 传播的脉动阵列时序；若改脉动结构，必须新增行列 skew 与排空合同。

| 档位 | TO×TN | 双乘积 PE/DSP 核心 | MAC/有效拍 | INT32 acc 状态 |
|---|---:|---:|---:|---:|
| 单元调试 | 4×4 | 8 | 16 | 512 bit |
| 低 LUT/FF 推荐起点 | 8×16 | 64 | 128 | 4096 bit |
| 性能扩展 | 16×16 | 128 | 256 | 8192 bit |

TO、TN 是综合参数；TN 为偶数。不要根据“片上 RAM 有余量”就默认 16×16：累加器、修正逻辑、宽 mux、广播扇出仍占逻辑。先看完整系统综合余量，再选择产品档。DSP 数表不包括重定标、地址运算和其他模块。

## 5. tile 生命周期与 K 分块

基线顺序为：接受命令 → 锁存校验 → 预装 W/X → 初始化 acc → 发射 K 拍 → 排空 PE → 排空尾部 → 写出结果 → 等待写事务完成 → 下一 tile/命令完成。

| 阶段 | 离开条件 |
|---|---|
| IDLE / ACCEPT | cmd_valid && cmd_ready，字段快照完成 |
| LOAD | 对应 W/X bank 均装载完且 tag 匹配 |
| ISSUE | 最后一项 k 的输入被真正接受 |
| DRAIN_PE | 最后一个有效乘积进入累加器 |
| TAIL | 所有有效 OC/N 元素完成重定标和 LUT |
| STORE | 所有写数据及对应 B 响应处理完，无错误 |
| DONE | 完成事件被接收，不重复发布 |

Kc 是缓存分块深度。K>Kc 时只循环 LOAD/ISSUE/DRAIN_PE，acc 持续保留；最后一个分块之后才能 TAIL。bias 只加一次。TO/TN 的掩码在命令/最后 tile 生成，不靠填充数据是否为零来推断有效性。

新 FSM 使用项目三段式风格并明确 IDLE 复位状态；每个 done 是被消费的事件，不允许跨后续 start 残留为高电平。

## 6. WBUF/XBUF 的 RAM 组织

容量与带宽分别计算。两个完整 Kc tile 的双缓冲原始容量：W=2×TO×Kc B，X=2×TN×Kc B。

| 形状 | Kc | W 双缓冲 | X 双缓冲 | 合计 |
|---|---:|---:|---:|---:|
| 8×16 | 576 | 9216 B | 18432 B | 27648 B |
| 8×16 | 2304 | 36864 B | 73728 B | 110592 B |
| 16×16 | 576 | 18432 B | 18432 B | 36864 B |
| 16×16 | 2304 | 73728 B | 73728 B | 147456 B |

建议第一版 Kc=576，支持 1152/2304 分块续累；这是缓存设计选择，不能改变层输出的量化点。每拍读宽为 W:8TO bit、X:8TN bit；8×16 合计 24 B/拍，16×16 合计 32 B/拍。这是片内带宽，不能等同为 HP 总线瞬时带宽。

按每个 k 一个宽字组织 RAM，采用多个物理 bank 形成所需读宽，loader 用字节/字 lane 写使能灌入。实际 BRAM 颗数由深度、端口模式、写宽转换和 padding 决定；不能只用有效字节除以 4608 得出最终颗数。

示例：128-bit 宽读可用四个 32-bit 数据 lane 组成，单 bank 采用兼容 36-bit 端口模式；不假设一块 BRAM 有任意宽度和任意多读口。具体 BMG 参数及读延迟须作为 IP 合同锁定。

ping-pong bank 状态建议 FREE → FILLING → READY → READING → FREE。只有 DMA 全部返回且写缓存流水排空后才 READY。每 bank 保存 oc_base/n_base/k_base/有效长度等 tag；tag 相同不代表数据已就绪。消费者尚未释放的 bank 不允许 loader 覆盖。

## 7. 累加状态和尾部缓存

活动 INT32 累加器使用 FF 基线，不把 descriptor RAM 的节省方法照搬到每拍更新的计算状态。完成 tile 可以分行序列化写入 BRAM，但必须在重新使用 acc 前迁移完成。

两个可实现档位：

- 低面积基线：单 acc tile，先计算、后排空；控制简单，尾部时间计入总时延。
- 吞吐扩展：两个 acc context 或足够分 bank 的 shadow buffer，交替计算与排空；必须显式计入额外状态和搬移带宽。

不能声称“加一块双口 BRAM”便可一拍保存 256×32 bit 的 acc 快照。若只有一个 32-bit 写端口，最少需要 256 次写；增加 bank 或时分会改变成本与时序。

## 8. 重定标与 SiLU

每输出通道加载 bias_eff(INT32)、M(INT32)、shift(建议 6 位，域 0…62)。sum=acc+bias_eff 建议先用 signed 33 bit；prod=sum×M 用 signed 64 bit，前提是导出器已验证乘积不溢出；当前包满足这一前提。

输出顺序固定：sum → prod → RNE → sat INT8 → LUT 或线性旁路。M、shift 和 bias 属于 OC，LUT 属于层，且所有参数必须随当前 tile 锁定。首层 bias_eff 的 +128Σw_q 修正只能加一次。

RNE 可按 q=floor(prod/2^s)、r=prod−q×2^s 实现，r>2^(s−1) 或相等且 q 为奇数时 q 加 1；s=0 独立旁路。SiLU 地址为 signed INT8+128，而非把补码直接当表索引。

设尾部每拍处理 R 个元素。完全隐藏一块 TO×TN 输出至少要求 ceil(有效元素/R) 不大于可重叠计算窗口；K=27 时 8×16 的满 tile 需要 R≥5，16×16 需要 R≥10。这只是算术下限，不包含尾部延迟、写口和行碎片。

默认建议先做 R=1 或 2，保证正确性和资源；按测得瓶颈增加并行。重定标乘法可能使用多个 DSP 或 fabric，不能沿用旧文档“10 个 33×32 乘法器不占 DSP、约 3K LUT”的无综合预算。LUT 可以缓存当前层的 256 B；R 路并行查表需要匹配的读端口或副本。

## 9. 外部接口设计

### 9.1 命令与完成接口

| 类别 | 建议字段 | 接收/释放规则 |
|---|---|---|
| 命令头 | frame_id、desc_id、opcode、model_version | 与 cmd_valid 一同稳定 |
| 几何 | IC/OC/IH/IW/OH/OW、KH/KW、stride、pad | 整数值，校验 N、K 一致性 |
| 存储 | X/W/Y/bias/M/shift 地址或已解析 buffer ID、容量、stride | Zynq-7020 基线 32 位物理地址 |
| 量化 | first_input、act_enable、LUT ID、quant version | 固定 RNE；不允许静默切换算法 |
| 策略 | oc_outer/n_outer、允许 spill、tile 配置版本 | 不接受超出综合能力的并行度 |
| 完成 | valid、frame_id、desc_id、status、written_bytes | ready 接收前保持稳定 |

建议内部不再复用 A2 的散装 AXI-Lite shadow 寄存器。CSR/descriptor walker 经验证后提交一条稳定命令，GEMM 只在握手时采样一次。运行期间 PS 更新表不能改变当前命令。

64 位地址字段可以保留 ABI 扩展位置，但本代硬件若只支持 32 位，必须验证高字为零，不必实现无用的 64 位地址加法器。64-bit 数据通路与 32-bit 物理地址是两回事。

### 9.2 DMA/HP 数据接口

推荐 AXI 数据宽 64 bit、地址宽 32 bit；W/参数读、X 读、Y 写逻辑分流，可由 interconnect 映射物理 HP。实际 PS HP 协议、转换器和 burst 限制由 BD 确认，不把 AXI4 最大 burst 原样套到 PS 端。

必须处理独立 AW/W、R/W 背压、RLAST、RRESP/BRESP、4 KiB 边界、部分尾字节 WSTRB、地址对齐和在途计数。Y 为 CHW，tile 的每行在 DDR 中相隔 N 字节，不能把整块 TO×TN 当连续输出写入。

完成条件是对应写事务响应全部成功，不只是最后一个 WLAST 发出。错误发生后停止发新请求，排空已有事务或进入受控恢复；不可通过复位半个 AXI 通道丢弃 outstanding 后声称空闲。

若控制与计算时钟不同，命令和完成走异步 FIFO/握手快照，禁止逐位同步多位描述符。状态计数使用快照读；首版优先单计算时钟域，降低 CDC 面积和风险。

## 10. 遍历策略与带宽

oc_outer：固定一组权重，遍历所有空间 tile；权重加载少，X 对每个 OC tile 重读。

n_outer：固定一组 X tile，遍历所有 OC tile；X 加载少，权重对每个 N tile 重读。

忽略边界与 K padding，设 Ot=ceil(OC/TO)、Nt=ceil(N/TN)：

| 策略 | W 装载字节模型 | Xcol 装载字节模型 |
|---|---|---|
| oc_outer | OC×K | Ot×K×N |
| n_outer | Nt×OC×K | K×N |

Xcol 数量是窗口缓存侧展开字节，不等于 DDR 原图读字节；行缓存、步长、跨行、对齐和重复读取另计。按每层成本选择遍历顺序，而不是固定声称全网只需要 15–20 MB DDR 访问。

对总 1.011 GMAC，16×16 单步 K 的有用 Xcol 消费量量级为 MAC/16≈63.19 MB；“每个输入只读一次”的估算不适用于所有遍历顺序。多个 HP 口最终共享 DDR，摄像头/VDMA 竞争必须在系统测量中计入。

## 11. 帧时延与资源预算方法

理想计算拍数 Ccomp=Σ ceil(OC/TO)×ceil(N/TN)×K。不能用有效 MAC/(TO×TN) 忽略尾块，也不能把 MAC 与两次运算的 GOPS 混用。

单 acc、无尾部重叠时，每 tile 预算为 load_unhidden + K + drain + ceil(有效输出/R) + store_unhidden。完全重叠时 max(compute, load, tail, store) 只构成乐观下限，启动/切换/反压仍要叠加。

| 资源 | 预算方式 |
|---|---|
| PE DSP | TO×TN/2 |
| 活动 acc FF | TO×TN×32 |
| shadow acc | 若全寄存复制，则再加同等位数；RAM 方案另计搬移 |
| W/X RAM | 第 6 节字节容量，加物理端口碎片 |
| requant | R×单路综合结果，另加参数和 valid pipeline |
| 读写 FIFO | 深度×实际 payload+tag，尽量 BRAM/LUTRAM |
| 控制 | 共享 K/OC/N 计数器，避免每 PE 复制 ID/计数器 |

100 MHz 时 8×16 的有用 MAC 理想下限约 78.99 ms/帧，16×16 约 39.49 ms/帧；这是忽略尾块和搬运的下界，不是可交付 FPS。150 MHz 是提频候选，不能由旧版局部 OOC 通过推出新引擎可达。

不承诺固定 30 fps。先出独立引擎资源/时序报告，再测带 VDMA 和 PS 后处理的整帧吞吐及延迟。

## 12. 与图算子和 PS 结果的衔接

Conv 输出直接写特征缓存；后继为 Add/Concat/Pool/Upsample 时由 PL 图算子接续。Concat 的多输入采用段描述符列表；软件图的一个 Concat 不一定对应一条固定长度硬件描述符。

view/split 可做地址视图。只有尺度相同且消费布局支持分段时，Concat 才能零拷贝；尺度不同必须显式重定标，不能把后继卷积权重随意调整当成逐位等价替代。

最终 raw head 顺序保持 reg8、reg16、reg32、cls8、cls16、cls32，每块内部 CHW，共 149100 B；各块尺度由版本化模型包提供。PL 写完全部响应后发布结果元数据和 IRQ；PS 确认消费后才能重用 head buffer。若使用双 head buffer，可与 PS 后处理重叠，但各帧 frame_id/seq 必须独立。

当前软件 schedule 为 103 个中间任务+1 个 heads 汇总；这是软件节点数量，不是新硬件 descriptor 数的硬性约束。最终需要由图编译器输出并验证程序长度。

## 13. 现有 CSR 文档对接前的检查点

本轮不修改另一工作流正在使用的 CSR 合同。连接 GEMM 前必须核对实际 RTL、冻结寄存器表与表容量，不能仅凭旧文档的建议字段直接连线。

尤其检查：16 KB descriptor 空间需要 0x4000 字节映射（或明确分页），8 KB aperture 不会自动容纳 16 KB；BRAM 数量要按物理容量和端口计算；8-bit 的能力字段不能直接表示 256 lanes，应使用更宽字段或指数编码。

当前模型有 57 张 SiLU 表，共 14592 B；4 KB 窗口只能作为分页/缓存窗口，不能默认为全模型常驻。若只有 16/32 LUT banks，应提供显式预取与换入，不得让不同层误用同一表。

逐 OC 的 bias/M/shift 参数超过一个小型逐层 profile 表的容量；建议随 W tile 通过 DMA 装载进参数缓存。控制表存地址、长度、LUT ID 和版本，不把所有 OC 参数展开成 FF。

这些属于集成前 ABI 检查项，并非本轮已证实当前新 CSR RTL 存在相应错误。

## 14. 验证计划与通过标准

| 门 | 内容 | 必须留存的证据 |
|---|---|---|
| G0 | 读取量化包、形状/容量/溢出域检查 | 源文件 SHA、模型清单 |
| G1 | PE + acc + requant + LUT | 独立 oracle、原语仿真、延迟记分板 |
| G2 | W/X RAM、窗口生成和 bank 状态 | 实际字节与地址、背压、bank 覆盖断言 |
| G3 | 单层 GEMM | K15 档、OC/N 尾块、首层/普通层、两种 walk |
| G4 | DMA 与 CSR 集成 | AW/W 异拍、随机延迟、4KiB、非对齐尾部、错误注入 |
| G5 | C2f/SPPF/Neck 子图 | 每个中间 tensor 零差异 |
| G6 | 整网 | 63 Conv+图算子+raw head，每帧逐字节比对 |
| G7 | 综合实现和板测 | 全系统资源、时序、DDR cache 一致性、持续帧与错误恢复 |

软件数学一致、RTL 仿真一致、板级一致和检测精度分别过门。单帧 fullnet 或 FakePL 通过不能代替多帧硬件验证。新增 testbench 不能直接拷贝 DUT 算法生成期望值；整数累加使用更宽独立 oracle，重点测最短 K 和最后不足一个 tile 的路径。

建议首轮合成覆盖 K=1/27/32/576/2304，OC=1/7/TO−1/TO/TO+1，N=1/TN−1/TN/TN+1/100；K=0 拒绝。数值、地址、总写字节和完成次序同时检查，不只比较最终头。

## 15. 修改模型的兼容边界

| 后续改动 | 对硬件的通常影响 |
|---|---|
| 相同 W8A8 结构更新权重/尺度/bias | 替换模型包并重新跑 golden，无需更改乘法墙 |
| LUT 内容调整、同 256×8 接口 | 表替换；必须重新评估模型输出 |
| 相同整数合同下 QAT | 更新参数，硬件接口可保持 |
| 通道数/输入尺寸在既有上限内 | 更新图与 buffer 分配，资源吞吐重新预算 |
| W8A16、INT16 head、扩大 LUT 输入域 | 乘法打包、缓存位宽、DMA 布局可能均需改动 |
| 非对称内部激活、换激活函数/网络算子 | 改数值合同及算子支持，不能保证仅换权重 |

可以先开发可配置 W8A8 架构，但不应承诺任意后期精度补救都无需硬件变化。当前 test 精度下降保留为模型问题，不能靠提前饱和、截位或省略分支缩减硬件。

## 16. 来源与交接

主要数据源：[schedule.json](../2_fpga/3_yolo_zynq/rom_data/schedule.json)、[quant.json](../2_fpga/3_yolo_zynq/rom_data/quant.json)、[逐层复算](../4_metrics/logs/2026-09-18_yolo_quant_audit_run01/layers.csv)。旧实现参考：[yolo_gemm_array.v](../2_fpga/3_yolo_zynq/rtl/yolo_gemm_array.v)。

旧版架构文档中的带宽、免费尾部、资源数字不自动继承为新设计事实。本文数字采用明确公式，复算与哈希见 [manual run01](../4_metrics/logs/2026-09-18_yolo_pe_gemm_manual_run01/)。本轮未运行新 RTL 仿真/综合/上板。
