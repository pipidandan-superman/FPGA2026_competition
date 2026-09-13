# 2026-09-13 日计划

## 最新交付：v1.4关键资产与队友复现包发布

按用户要求只发布PL重加载器v1.4，淘汰本地v1.0～v1.3；保留旧失败原始证据用于根因追溯。交付范围包括v1.4源码/完整Windows包、固定动作Overlay、动作识别兼容入口、两轮上板成功证据、v1.3首帧失败证据、display-only重开诊断、根README/HANDOFF及零歧义上板指南。使用独立个人分支工作树和显式路径暂存，不接触冻结`2_fpga`或主工作区其他改动。

## 最新闭环：从v1.4内部重开动作识别恢复成功

用户按诊断从v1.4内部点击“打开动作识别”后确认成功。新日志立即出现ACTION_INITIAL_CLEAR/ACTION_LINK_READY，并从板端既有done_seq=8连续使用seq9，随后动作确认至seq16、关闭CLEAR至seq17；85完整帧、零丢帧、action_error=null。证明此前无LED仅因直接双击EXE进入display-only，不是PL/AXI故障，且无需重新加载PL。见[闭环诊断](../../4_metrics/logs/2026-09-13_action_viewer_reopen_diagnosis_run01/REPORT.md)。

## 最新诊断：重新打开的是仅识别模式，未启用动作链路

最新viewer已有584推理帧、590完整视频帧且零丢帧，但`protocol=null`、events仅有START，没有`ACTION_INITIAL_CLEAR/ACTION_LINK_READY`，因此不是PL/AXI/LED再次失败，而是用户直接打开EXE进入默认display-only模式。应关闭该窗口后，仅点击v1.4 GUI的“打开动作识别”，无需重载PL；新窗口出现ACTION_LINK_READY后再测LED。见[诊断报告](../../4_metrics/logs/2026-09-13_action_viewer_reopen_diagnosis_run01/REPORT.md)。

## 最新复现：断电重启后v1.4再次完整加载成功

用户确认真实断电后重新运行v1.4仍正确。第二组独立日志显示原视频服务PID596，A→C安全切换后10秒等待完成，约0.235秒进入VDMA流，VIDEO/ACTION/OVERLAY READY齐全；新一轮80个完整帧零丢帧，五项启用手势再次全部完成AXI序号闭环。见[断电复现run02](../../4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run02/REPORT.md)。由于v1.4尚未记录boot ID，断电事实严格记为用户物理确认；当前累计两次v1.4加载成功，其中第二次为用户确认的断电冷启动复现，尚不等同10/10可靠性门。

## 最新板测：v1.4单次热重载及全部启用手势LED通过

v1.4从原视频A安全切换动作C成功：10秒定时等待结束后约0.219秒即出现真实VDMA读写槽位转换，随后VIDEO/ACTION/OVERLAY READY全部到达。动作上位机272推理帧、278完整视频帧、零丢帧；Stop、Up、Down、Thumbs up、Thumbs Down五项均完成三帧稳定判定及AXI序号闭环，用户确认LED4/7/1/6/5对应成功。见[板测验收](../../4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run01/REPORT.md)。结论为`V14_SINGLE_HOT_RELOAD_VIDEO_ACTION_LED_PASS`，不外推为多次热重载可靠性PASS；本轮成功后的原视频恢复尚未请求/验证。

## 最新完成：按用户建议延长OV5640/首帧等待并交付v1.4

已将动作位流下载后的固定等待由1秒改为10秒，首帧真实VDMA槽位转换窗口由5秒改为30秒，并加入每秒进度事件；GUI/SSH同时改为实时逐行显示板端journal，避免再次表现为卡死。30秒仍无真实帧时继续fail-closed并自动请求恢复，等待事件明确标注不等于SCCB/PCLK/VSYNC就绪证明。19项测试、语法、整包哈希和打包自检通过，BIT/HWH哈希不变，交付`8_tools/EES331_PL_Reloader_v1.4`。状态`OFFLINE_PACKAGE_PASS / BOARD_NOT_RUN`；未连接开发板、未改冻结`2_fpga`。见[v1.4报告](../../4_metrics/logs/2026-09-13_pl_reloader_v14_package_verify_run01/REPORT.md)。

## 最新完成：动作识别复现与热重载完整解决方案

已基于同一C位流成功/失败证据形成双路线方案：[完整方案](../../4_metrics/logs/2026-09-13_action_reproducibility_solution_plan_run01/REPORT.md)。核心判断是AXI/LED功能板测通过与热重载首帧失败不矛盾：当前失败早于ACTL附着。交付主线建议使用独立动作版冷启动配置、统一C位流和单一Camera/ACTL服务，不让比赛复现依赖A→C热重载；热重载作为独立研发支线，通过实时日志、V0–V4纯视频矩阵、SCCB/PCLK/VSYNC/AXIS/VDMA分层观测定位第一处分歧。状态 `PLAN_ONLY / WAITING_FOR_USER_APPROVAL`；本轮未执行板测或修改RTL、BIT/HWH、SD、服务和冻结`2_fpga`。

## 最新结果：v1.3 实机进入真实加载，首帧超时后自动恢复

v1.3 未复现旧 `pgrep` 假成功：13项载荷/HWH合同、MMIO库、原服务安全停止和动作BIT下载均通过。动作 Camera/VDMA 在固定5秒门内 `seen=[false,false]`，以 `FIRST_FRAME_TIMEOUT / No real frame transition` fail-closed；动作链路、AXI和LED未执行。程序完成 `VDMA_HALTED`、`BUFFER_FREED` 并恢复原服务PID1284，用户确认HDMI正常。界面在`FOUND`后看似卡住，是主机端等待远程命令整体结束后才批量显示输出；实际板端一直在运行。当前不重试、不改超时/地址/RTL，根因仍为热重载首帧恢复时序/前置状态敏感且未闭环。见[只读审计](../../4_metrics/logs/2026-09-13_pl_reloader_v13_board_failure_audit_run01/REPORT.md)。

## 当前完成：PL 重加载工具 v1.3 离线设计、实现与交付

用户确认开发板已断电并授权开始 v1.3。已按要求默认填充 SSH 密码 `xilinx`，同时保持密码仅经临时 AskPass 环境传递；修复 `pgrep` 自匹配假阳性，把真实动作进程导致的安全跳过记为 `SKIPPED/本次未执行`，且只有真实 `ACTION_OVERLAY_READY` 才显示加载完成。16 项源码测试、离线构建、打包自检及 1006 项整包哈希复核通过，交付为 `8_tools/EES331_PL_Reloader_v1.3`。本轮未连接板卡、未修改冻结 FPGA/SD/位流；实机动作链路仍为 `NOT_RUN_BOARD_POWERED_OFF`。见[v1.3交付报告](../../4_metrics/logs/2026-09-13_pl_reloader_v13_package_verify_run01/REPORT.md)。

## 最新诊断：v1.2 假阳性跳过重载，LED 无输出根因确定

用户 16:51 的 GUI 操作没有实际加载动作版 PL。`action_running()` 把 `pgrep -af camera_action_v1.py` 查询命令自身误认为动作进程，返回 `ACTION_ALREADY_RUNNING_NO_RELOAD` 后界面错误显示“动作版PL加载完成”。PC 模型随后正常推理，但 UDP 5001 动作链路超时，未产生 PS/AXI/PL LED 输出。当前只完成诊断与证据归档，未修改程序、RTL、位流或板端状态；下一步须先修复进程检测与成功状态语义，再重新打包并执行真实 A→C 验收。见[诊断报告](../../4_metrics/logs/2026-09-13_pl_led_diagnosis_mineru_run01/REPORT.md)。

## 当前完成：修复连接超时并交付PL重加载应用v1.2

用户在v1.1输入正确凭据后仍出现两次30秒连接超时；现有日志不能证明密码错误。已用Windows OpenSSH替换PuTTY连接层，加入TCP 22端口预检和明确的板卡上电/网线/PC `192.168.240.2/24`诊断提示，密码不再进入命令行参数。12项离线测试、打包自检、AskPass实测和1006项清单哈希均通过；交付为`8_tools/EES331_PL_Reloader_v1.2`。板端验证仍为`NOT_RUN`，下一步仅由用户在桌面运行v1.2并回报第一条结果。详见[v1.2验证报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run03/REPORT.md)。

## 当前完成：一键PL重加载应用v1.1

用户取消手工逐步复现，明确要求直接制作PL重加载应用。已完成Windows GUI、板端控制器、固定动作Overlay载荷打包和离线安全验证；最终交付为`8_tools/EES331_PL_Reloader_v1.1`。应用封装状态检查、上传验签、安全停止A、单次加载C、READY门、失败恢复、原视频恢复和动作上位机启动。未执行实机按钮，物理HDMI/LED仍待用户使用时确认。证据见[交付报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run02/REPORT.md)。

## 当前阶段：冷启动后在线重载手工复现，等待用户执行

目标是在 SD 包、BOOT.BIN 和冻结 FPGA 工程不变的条件下，从冷启动原视频 Overlay A 安全切换到真实模型经 AXI-Lite 控制 PL LED/UART 的动作 Overlay C。当前只提供并审查手工复现步骤，不连接或操作板卡，不制作第二阶段一键应用。固定入口和门禁见[手工复现方案](../../4_metrics/logs/2026-09-13_action_v1_manual_repro_plan_run01/REPORT.md)。

优先级：先验原视频动态基线；确认 VDMA/缓冲释放；从 A 单次加载 C；看到视频与动作服务 READY 后再开 PC 模型；完成物理 LED 核对；正常 CLEAR/停止并恢复 A。明确非目标：C->C 重试、重写 SD、修改 RTL/BD、启用自启动、开发第二阶段应用。

## 最终收尾：用户明确暂缓热重载，第一版功能目标完成

用户已结束手工测试，并明确要求重加载故障暂不解决，待其自行重加载再复现时处理。五项真实模型→AXI寄存器→PL UART/LED输出已验证，交付提交612d7b3已推送个人分支；见[完成审计](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/completion_audit.md)。热重载仍是已知未解决项，不再自动诊断或加载。未执行此前口头计划的最后恢复操作，不声称当前原视频已恢复；收尾不操作板卡。下方“继续解决热重载/目标活动/手工测试中”等为历史状态，以本段为准。

## 最新交接：五动作真实闭环通过，热重载失败保留，用户持续GUI测试中

见[完整链路报告](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/REPORT.md)。
1500真实推理帧、五动作均三帧证据、18条/126字节COM4完全匹配；板端859.5秒4296帧、1028命令COMPLETE，安全HALT/FREED。
随后持续模式跨进程C重载首帧失败，已保存board_manual_runtime，不是动作触发；原A恢复PC65帧/用户HDMI通过后，同一systemd程序从A切C成功。根因未确认，禁止称部署稳定。
当前板端ees331-action-e2e-manual2.service持续运行，原服务停止但SD/原文件未改；PC gui_manual无自动退出。用户要求继续测试，**不得自动关闭GUI/停服务/重新加载**。
GUI90秒提前关闭问题已纠正；用户已确认五项Stop/Up/Down/拇指上/拇指下对应LED4/7/1/6/5。此反馈不是测试结束授权；先查实时进程/服务句柄，不依赖旧PID。
恢复仅在用户确认测试结束后进行，先正常退出模型清灯，再停动作服务确认HALT/FREED，再启动原服务并验证UDP/物理HDMI。
五项GUI物理确认已完成；热重载可靠性修正与受控验证、文档及个人分支交付仍待完成，不将功能映射通过等同部署问题已解决。
旧Overlay部署流程暂停，未改RTL/地址/首帧超时。不要在脏main提交，个人分支干净worktree为E:/competition_worktrees/FPGA2026_competition/pipidandan-superman，写入需要相应权限。

## 最新：完整模型→AXI→PL输出目标执行中

用户明确要求完成AXI-Lite链路的PL模型识别输出。执行证据目录：4_metrics/logs/2026-09-13_action_v1_end_to_end_run01。
已修正camera_action_v1动作初始化/线程异常连带终止视频，保留DEGRADED错误；6项故障隔离与14项动作测试通过。
同一C位流、相同Camera启动成功，真实ACTL身份/状态读通过。1000条确定命令及重复提交验证通过，含清灯1001帧7007字节COM4逐字节一致。
并行视频PC65变化帧零CRC/丢帧，用户确认LED1–7轮换、cfg_done/HDMI正常。正运行真实视频模型，已记录Stop及Thumbs up经三帧判定下发PL；其余动作、完整串口核对和最终恢复待完成。
不可将当前进度当目标完成；保持活动目标，继续真实模型/物理LED验证及可复用入口交付。原服务暂由900秒受控动作程序替代；不可直接断电或再次加载。
本轮只改用户授权的动作Python相关代码，没有改RTL/地址/SD。旧技能部署流程仍暂停；历史失败不覆盖，未Git发布。

## 最新：S1/S2加载顺序板测及最终原视频恢复全部通过

用户已重新上电，boot ID 027a8e8d-ba81-4cd7-adb9-5650802e304e；初始原视频PC66变化帧、用户HDMI正常。
S1固定120秒等待后仅一次C加载，75秒375帧、PC65变化帧，零丢帧/CRC；用户确认cfg_done/HDMI正常。
S1安全HALT/FREED后恢复原服务，PC65变化帧、用户再次确认正常。
S2预加载后等待120秒再加载，总计2次；75秒375帧，PC66变化帧、零丢帧/CRC，用户HDMI正常；HALT/FREED/exit0。
最终原服务PID2590、boot ID不变，原文件哈希一致，PC66变化帧零丢帧/CRC；用户最后确认cfg_done/HDMI动态正常。
S1/S2_VIDEO_PASS / ORIGINAL_RESTORED_PASS / ROOT_CAUSE_UNCONFIRMED。两组最后加载到出帧均约1.32秒，未放宽5秒门。
全部接收器退出，本阶段板卡操作结束。重要限制：S2同一进程双加载，不等价历史跨进程且夹身份检查的完整路径。
下一步先离线核对完整应用包装、进程边界/初始化时序与诊断入口差异，再设计单变量对照；不能认定重复加载就是根因。
无ACTL动作访问，无UART/LED/模型验收。原地址/RTL/等待时间不盲改；动作错误连带停止视频缺陷仍需单独修正验收。
见[板测报告](../../4_metrics/logs/2026-09-13_action_v1_load_sequence_board_run01/REPORT.md)及该目录完整实时输出。
禁止重试覆盖证据或跳过恢复门禁；旧部署流程仍暂停，未改生产工程/SD/技能，未Git发布。下方断电状态为历史。

## 最新：用户已断电，加载顺序对照离线准备完成

当前目标：准备加载顺序受控对照，先不改设计。S1单次C加载与S2预加载C后再次C加载；固定Camera/视频参数/120秒等待。非目标：动作业务、生产修复、SD更新与Git发布。
本轮未连接板卡、未上传/下载、未修改生产工程或旧技能；准备状态OFFLINE_PREPARATION_PASS，板测NOT_RUN。
详见[准备报告](../../4_metrics/logs/2026-09-13_action_v1_load_sequence_prepare_run01/REPORT.md)。
下方原视频已恢复等状态为断电前历史，不代表当前正在运行。

## 最新：用户批准窗口内三组纯视频对照通过，原视频已恢复

本轮授权“开始进入”，证据见[受控对照报告](../../4_metrics/logs/2026-09-13_action_v1_controlled_video_run01/REPORT.md)。
T0原A+旧Camera、T1同A+新Camera、T2动作C+同新Camera，每轮仅一次下载，各75秒。
板端帧375/375/376，PC分别60/60/61个变化帧、零CRC错误/丢帧，用户确认三组cfg_done/HDMI正常。
T2仍用上次失败的同一BIT/HWH且原5秒首帧门未改，这轮成功；未触发90秒诊断分支。
不能据此断言重复下载就是根因：未做仅加载次数变化的对照，诊断日志/只读预采样有额外启动延迟。
下一阶段固定C位流/软件/前置状态，分离加载次数、完整应用包装和就绪时序；不先盲改地址或RTL。
三组HALT/FREED/exit0，原服务PID2814恢复；PC12.140秒60变化帧、零CRC/丢帧，用户确认恢复正常。
状态T0/T1/T2_VIDEO_PASS / ORIGINAL_RESTORED_PASS / ROOT_CAUSE_UNCONFIRMED。
未发动作命令、未验UART/LED或模型、未修改生产源码/技能/SD、未Git发布；旧部署流程仍暂停。
下方待授权、T2纯视频未通过等表述保留为历史。本轮不会把单次成功覆盖上次失败。

## 最新：本次重新通电后的原视频基线通过

用户确认cfg_done灯亮、HDMI正常；只读SSH确认原服务PID600与原BIT/HWH/Python哈希，
本机有线网络Up/1Gbps；PC被动接收12.219秒61个变化帧、CRC/丢帧0。
本次boot ID=d60f7ee8-90c3-43b3-bc75-ce4efb151c30；PL_LOADED=51.900973s，
VDMA_STREAM_STARTED=53.170285s，间隔1.269312秒；它是首次启动而非最坏就绪时间保证。
证据见[冷启动只读基线](../../4_metrics/logs/2026-09-13_action_v1_coldboot_baseline_run01/REPORT.md)。
未加载Overlay、未停视频、未修改板卡。COM4已枚举，COM3身份未确认；不能假设历史COM6仍存在。
旧Overlay部署流程仍暂停，动作版根因未确认；进入会中断视频的受控对照前需明确测试窗口。
下方“当前网络断开”为此前历史状态，已由本轮只读检查更新。

## 最新：系统性回归审计，暂停旧 Overlay 部署流程

用户要求先完整分析功能增加为何影响视频，重点核查地址冲突；并明确质疑继续使用旧skill。
本轮仅离线审计，不下载、不改生产代码/RTL/skill、不Git发布。报告见
[系统审计](../../4_metrics/logs/2026-09-13_action_v1_regression_review_run01/REPORT.md)。
实际三份HWH未见同主端口地址重叠，BIT/HWH与XSA内嵌文件匹配；B→C共同视频参数/连接一致。
本次根因仍未确认；优先分离采集/启动同步与加载流程。动作异常拖停视频是确认的独立设计缺陷。
下面“当前结果”及继续只查时钟的方向为历史；不再将问题过早收窄为时钟。

## 当前结果：新ACTL身份通过，视频首帧失败，原视频完整恢复

用户已明确授权本轮切换且关闭占用工具。实际结果不能沿用下方的“未上板”停点：
[board_run02](../../4_metrics/logs/2026-09-13_action_v1_board_run02/REPORT.md)先记录61帧基线、
备份/上传/编译；同目录同名XSA触发PYNQ3.0.1解析错误，未下载，失败保留。
修正发布布局为action_v1_uart_run02（XSA位于build_artifacts/，BIT/HWH字节不变）。
[board_run03](../../4_metrics/logs/2026-09-13_action_v1_board_run03/REPORT.md)原生元数据通过，
确认原服务退出/VDMA_HALTED/BUFFER_FREED后下载成功；独立SSH存活、启动ID未变，
ACTL身份和READY=1/序号0/计数0通过。

视频应用随后重载配对Overlay，VDMA复位/分配缓冲成功，但5秒内无真实帧切换，
报No real frame transition:[False,False]，已自动HALT并释放缓冲。动作服务尚未启动，
没有提交动作命令，没有COM4/LED或模型闭环PASS。此故障不得用加大超时或自动重试掩盖。
已恢复原ees331-camera.service：PC12.109秒60个变化完整帧、CRC/丢帧0；
用户明确回复HDMI正常流畅，见[恢复确认](../../4_metrics/logs/2026-09-13_action_v1_board_run03/physical_confirmation.json)。

现阶段：OFFLINE_PASS / ACTL_IDENTITY_BOARD_PASS / VIDEO_START_BOARD_FAIL /
ORIGINAL_RESTORED_PASS / GIT_NOT_PUBLISHED。旧失败包和板端目录保留，SD启动与原视频文件未改。
PS937参数比较只有数值文本格式及禁用调试选择差异；视频软件VDMA配置未改，共同HWH视频
模块参数/端点连接无实质差异。根因未证实，下一步只读检查实现时钟/摄像头初始化，必要时
设计观测后验证具体假设；不得无依据再次加载本次失败位流或跳过视频门做模型动作验收。
未Git提交推送，第二版不执行，不关机。下方执行中/等待状态均为历史。

## 当前执行：用户明确批准第一版Overlay切换与板测

用户回复“可以”，并确认普通UDP/COM4工具已关闭；本轮硬件操作已获授权。
使用新证据[action_v1_board_run02](../../4_metrics/logs/2026-09-13_action_v1_board_run02/)。
原板端BIT/HWH/应用/服务已备份，新包已上传独立目录/home/xilinx/action_v1_20260913_run02，
逐文件哈希通过。继续依次执行基线→合同/编译→停服务/VDMA停止→下载→存活→身份→
动作/串口与视频共存→恢复；当前阶段结果未完结。第二版不执行、不关机、不提前Git推送。

## 当前补充：网络恢复，只读Overlay预检通过，切换待明确确认

用户确认HDMI及PC UDP视频流畅。本轮按zynq-pynq-overlay-workflow重新SSH只读检查成功，
原ees331-camera.service仍在运行，心跳帧691→801、变化690→800，boot_id
b17807bb-70de-4b2f-a062-b1e50feded2e。此前Disconnected已是历史状态。
板端原BIT/HWH哈希已记录，与新动作包不同；未读取AXI、上传、停服务或重配置PL。
本轮用户询问能否用Overlay skill执行，按技能咨询/授权边界先说明并等待明确切换窗口。
无需重做SD；实际执行将使用本地action_v1_uart_run01配对BIT/HWH、PYNQ应用与ARM屏障库，
XSA保留作构建交付。下一步明确允许短暂停视频后，先做转移/合同/所有者与DMA停稳门，
再分步下载、存活、身份、功能、恢复。不得绕过这些门直接执行旧通用AXLT板测。
证据：[online_precheck_run01](../../4_metrics/logs/2026-09-13_action_v1_online_precheck_run01/REPORT.md)。
第一版实机未验收、Git未提交推送、第二版不执行、不关机。以下旧停点按历史保留。

## 当前状态：第一版离线通过，板测前置条件未满足

用户批准的三新帧/每帧>=0.75稳定门及暂不自动左右已实施。动作只走
PC→UDP→PS→AXI-Lite→PL LED/UART，第二版蓝牙动作输出未执行。

已完成独立RTL、官方复位/真实波特率仿真、独立BD及主视频BD、完整综合布局布线、
配对BIT/HWH/XSA、PYNQ动作服务、PC上位机、串口验收入口和14项动作软件回归。
当前为 OFFLINE_PASS / BOARD_BLOCKED_PRECHECK / GIT_NOT_PUBLISHED。

新发布包：2_fpga/0_diaplay_test/release/action_v1_uart_run01；
新上位机：8_tools/EES331_Action_Viewer_v1.0（旧版保留）。
优先下一步为用户恢复网线并确认动态HDMI，再进行1000条命令/COM4全帧/LED及视频共存板测。
未下载新位流、未修改板端服务或SD启动配置；不进入第二版、不关机、不推送未验收版本。

详细现状见[action_v1_status.md](../../2_fpga/0_diaplay_test/doc/action_v1_status.md)。
以下按历史保留，旧“最新/暂停”条目不覆盖本节。

## 最新：用户批准第一版执行

用户确认 Left/Right 暂不自动下发，采用三个不同新视频帧连续同类且各置信度 >=0.75，
稳定后只发送一次；无效结果打断连续计数，连续一秒无有效结果发送一次 CLEAR。
第一版执行已获授权，按独立仿真、BD 构建、板测顺序推进并报告；第二版尚不执行。
当前源与工程快照保存在
[source_run01](../../4_metrics/logs/2026-09-13_action_v1_source_run01/source_hashes.json)。
新动作 RTL 为此前草稿，正进行补齐和验证，尚无本版仿真、构建或板测 PASS。

## 最新：两版动作输出方案等待用户审核

用户要求先完成方案设计，审核后才能继续执行。已形成
[两版实施方案](../../2_fpga/0_diaplay_test/doc/axi_action_uart_ble_two_version_plan.md)：
第一版为 PC 动作经网络回到 PYNQ、PS 通过 AXI-Lite 提交、PL 点灯并从 COM4 TX
发送动作帧；第二版保留第一版并把同一 UART 串行波形镜像到板载 MLT-BT05，由现有
BLE GATT FFE1 上位机抓取原始 HEX，与 COM4/AXI/期望帧四方比对。A17 与 AA13 是
独立输出引脚，不存在物理 UART 冲突；旧透明桥必须移除以避免 BT_RX 多驱动。

当前执行门为 `REVIEW_REQUIRED`。不继续仿真、BD、构建、下载或板测。用户提出审核门
之前新增的三个 RTL 和一份 ABI 文档均明确标为 `DRAFT_UNREVIEWED`，尚无任何 PASS
证据。当前模型软件仍禁用 Left/Right 自动下发，这一点已写入方案，待用户审核是否
保持。蓝牙上位机实际使用 BLE GATT，并非虚拟 COM 口。

## 最新：控制路径更正为 AXI-Lite 驱动 PL 动作

用户明确更正最终控制链路：PC/PS 模型结果不得绕过 AXI 直接写 PL 串口；PS 应通过
AXI-Lite 寄存器提交动作码和序号，PL 接受命令后同时更新动作 LED，并由 PL UART TX
向 COM4 发出动作帧。串口帧中只有 `ACTION` 字节承载动作语义，其余帧头、序号、CRC
和帧尾均为同步、关联与完整性包装。蓝牙继续保留为独立回环项目，不进入主数据流。

本阶段先在 `2_fpga/2_axi_lite_test` 内完成动作寄存器 ABI、UART TX/LED 执行器及自检
仿真；通过后再替换主视频工程 BD 中此前的透明蓝牙桥，重新综合、实现和生成匹配
BIT/HWH。动作灯使用 LED1--LED7，LED0/V4 继续专用于摄像头 `cfg_done`。此前
video+AXI+BLE 的构建与板测证据保留为历史通过记录，但不代表新的动作控制版本通过。
当前尚未修改动作 RTL、未重建位流、未下载板卡、未提交 Git，BRAM 仍为 NOT_STARTED。

## 最新：主工程自动化共存板测通过，等待 HDMI 确认

用户已确认独立测试恢复后的 HDMI 正常，独立 AXI-Lite 寄存器阶段完整 PASS。
主视频工程已加入 AXLT 寄存器模块及已验证透明蓝牙 UART 桥，完成包装层仿真、
新进程 BD 检查、综合、布局布线、位流及 HWH 合同审计。最终实现 setup/hold
裕量为 5.978/0.024 ns，黑盒与 DRC Error 均为 0；部署 BIT/HWH 哈希分别为
`633e7846...d9a5d0` 和 `8f759760...4beec0`。

首次 SSH 预检因物理网线无载波失败并保留；用户恢复网线后以现有 SD/PYNQ 启动完成
主工程集成位流实机测试。集成视频运行 130.053 秒/650 帧；PC 80.079 秒收到 400
个完整动态帧、丢帧 0；同一窗口完成 1000 条 AXI 命令和 11 轮蓝牙双向精确比对。
随后原服务恢复 active，20.172 秒收到 100 个完整动态帧、丢帧 0。自动化标记为
`MAIN_AXI_BLE_AUTOMATED_BOARD_PASS`，只等待用户确认集成窗口及恢复后的 HDMI 动态
画面，之后才提交个人分支。用户已撤销关机授权，当前无关机任务。BRAM 仍为
NOT_STARTED。

本地证据：
[构建](../../4_metrics/logs/2026-09-13_main_axi_ble_build_run08/REPORT.md)、
[BD](../../4_metrics/logs/2026-09-13_main_axi_ble_integration_run11/process_status.json)、
[仿真](../../4_metrics/logs/2026-09-13_main_axi_wrapper_sim_run05/process_status.json)、
[HWH合同](../../4_metrics/logs/2026-09-13_main_hwh_contract_run01/result.json)、
[PYNQ发布审计](../../4_metrics/logs/2026-09-13_main_pynq_audit_run02/result.json)、
[主工程板测](../../4_metrics/logs/2026-09-13_main_axi_ble_board_run01/REPORT.md)。

## 最新：复位缺陷已修复，独立寄存器板测PASS

当前停点：1000轮/3次重载及UDP恢复均通过；等待用户回答已发送的HDMI恢复确认问题，尚不宣告全阶段恢复验收。通用skill已创建并在6_skill、.codex/skills和用户全局目录同步，通过3份quick_validate及哈希一致性；[skill证据](../../4_metrics/logs/2026-09-13_skill_validation_run01/REPORT.md)。主工程仅只读核对路径，未修改/重建/下载；未Git提交推送、未关机。

下一步：HDMI确认后保存主工程可回退源/BD/约束/位流基线，集成寄存器与已验证蓝牙桥的明确共存范围，完成主工程构建及实机验证；更新并选择性发布个人分支，核验远端；全部通过保存且无未保存工作时按用户授权正常延时关机。不能因独立PASS跳过集成验收。原工作区dirty，个人worktree保留4个既有未跟踪文件，fetch后个人分支与远端0/0。

用户重新上电后取回run01残片。仅加载诊断成功；定位aux_reset_in低有效却接0，修正BD为接1。官方IP仿真复现旧故障且修复后CSR读取通过，重新构建100MHz时序/DRC通过。run02完成1000轮、3次重载，UDP恢复60帧通过，HDMI最终人工确认待补充。15项Python单测通过；旧失败与旧发布包保留。

[实机完整证据](../../4_metrics/logs/2026-09-13_axilt_reg_board_run02/REPORT.md)。后续用户新增授权：独立验收后创建通用zynq-pynq-overlay-workflow skill，再集成主FPGA工程、综合/实现/上板共存验证、更新并推送个人分支；全部完成保存且无未保存工作时才可正常延时关机。用户已确认主工程为2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr。未授权Git main合并，BRAM未实现，不提前关机。

## 历史：run01失联，暂停并等待恢复现场

已完成测试前PYNQ/视频/产物检查及ARM库编译，但正式板测期间SSH失联，未取得板端结果，REG_BOARD_UNCONFIRMED_CONNECTION_LOST，视频恢复待完成。用户确认没有拔插/复位/断电，cfg_done灯灭、HDMI黑屏；这与独立Overlay无视频模块相符，不代表寄存器通过。COM6探测无返回。下一步由用户复位/重新上电恢复原SD，然后先取回run01/events.jsonl及启动日志，不自动重试命令、不进入BRAM。

[完整现场、证据限制与恢复计划](../../4_metrics/logs/2026-09-13_axilt_reg_board_run01/REPORT.md)。本机远程控制进程已因超时退出，板端执行状态未知。

## 先前：用户上电并授权寄存器板测（进行中）

用户已明确上电并授权本轮验证，取代下方此前只说明/不操作约束。使用独立板端目录 /home/xilinx/axilt_test_20260913_run01，不覆盖原视频目录。已登录PYNQ3.0.1、核对原视频哈希和未绑定内核VDMA；用户确认HDMI动态正常，PC 12秒收到61完整帧、CRC/丢帧/坏头0。待编译ARM访问层、1000轮/3次重载及视频恢复。禁止合并主工程或自动进入BRAM。

证据：../../4_metrics/logs/2026-09-13_axilt_reg_board_run01/ 。板端日期与PC不一致，采用boot_id及monotonic区分当前启动和历史日志；首个journal未加-b含历史记录，当前依据boot_video.log。

当前：用户此前确认板卡断电，本轮仅询问如何上板验证。
目标：核对现有板测脚本，提供电源/SD/网络、文件传输、ARM编译、1000轮测试、3次重载与视频恢复步骤。
优先级：说明前提和副作用，再说明命令与通过标准。
非目标：不连接板卡、不下载、不改RTL、不实施BRAM、不合并或上传。
交付：对话操作指南及本日日志。

## EES-331 PYNQ SD root 密码提示诊断

当前判断：完整 IMG 已预装并启用相机 systemd 服务，正常刷卡冷启动不需要手工运行安装脚本。若终端提示 `[sudo] password for xilinx:`，应使用 PYNQ 的 `xilinx` 用户密码；不直接以 root 登录。

目标：给队友一组不改镜像的登录、sudo 与服务检查指引，并明确异常分流。

非目标：不修改/重打包 IMG，不操作队友板卡，不触碰冻结 `2_fpga/`，不把静态核对宣告成队友现场 PASS。

交付：[只读审计报告](../../4_metrics/logs/2026-09-13_sd_root_password_audit_run01/REPORT.md)。

## EES-331 PYNQ SD 整盘镜像交付

当前判断：插入的 `Disk 1` 为 USB 接口、MBR 分区、精确容量 `15,634,268,160` 字节；该容量等于约 15.63 GB（十进制）/14.56 GiB，符合标称 16 GB 卡的常见容量。启动 FAT 分区只读 CHKDSK 无错误，MBR、Linux 分区类型和 ext 超级块签名有效，现无损坏证据。

目标：将整张 SD 卡按扇区只读成像到桌面，保留启动区、PYNQ FAT 分区及 Linux 根分区；完成长度检查、流式 SHA-256 与落盘回读 SHA-256 一致性验证，并提供队友烧录说明。

非目标：不修改 SD 卡、不只复制 `G:` 文件、不修改冻结 `2_fpga/`、不把相同板卡/IP条件等同于队友已完成物理复现。

交付证据：[整盘成像运行目录](../../4_metrics/logs/2026-09-13_sd_card_raw_image_run01/)。

## 队友 SD 视频链路复现包选择

当前判断：队友应优先使用桌面 `ees331_pynq_sd_20260913_full.img`，它是已完成长度与双重哈希核对的完整实卡克隆；Builder EXE、基础镜像和仅启动分区包不作为本次直接复现包。

目标：明确唯一交付文件、哈希、目标卡容量、固定网络参数与现场验收边界。

非目标：不重新成像、不烧卡、不连接队友板卡、不修改冻结 `2_fpga/`。

交付证据：[只读核对报告](../../4_metrics/logs/2026-09-13_teammate_sd_package_selection_run01/REPORT.md)。
