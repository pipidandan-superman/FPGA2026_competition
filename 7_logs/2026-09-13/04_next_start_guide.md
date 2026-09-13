# 2026-09-13 下一次启动指南

## 队友唯一入口：v1.4完整复现

先执行`git lfs pull`并核对[完整上板指南](../../1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md)。开发板冷启动后等待原HDMI/UDP动态视频，关闭其他UDP5000接收器，再打开`8_tools/EES331_PL_Reloader_v1.4/EES331_PL_Reloader.exe`，检查状态、勾选基线、只加载一次。只有`ACTION_OVERLAY_READY`后才能测动作；模型必须由v1.4内部“打开动作识别”启动，并先看到`ACTION_INITIAL_CLEAR`与`ACTION_LINK_READY`。直接双击Viewer仅显示预测，不输出LED。

失败停止条件：`FIRST_FRAME_TIMEOUT`、`FAIL`、`DEGRADED`或READY超时出现后不重复加载，保存日志并恢复原视频；服务`active`不能替代动态HDMI/UDP人工确认。当前证据边界仍为2/2，其中第二次断电为用户确认，尚未达到长期可靠性门。

## 最新使用规则：动作识别必须从v1.4内部打开

需要手势驱动LED时，先确保动作版PL已经READY，然后点击v1.4中的“打开动作识别”；不要直接双击`EES331_Action_Viewer.exe`，后者默认只显示预测。正常入口应立即记录`ACTION_INITIAL_CLEAR`和`ACTION_LINK_READY`，并自动接续板端序号；重新打开动作窗口不需要再次加载PL。

## 当前唯一动作：从v1.4 GUI重新打开动作识别

先关闭当前只有识别画面但无LED的上位机窗口，然后在仍打开的v1.4 PL Reloader中点击“打开动作识别”。不要点击“一键加载动作版PL”，也不要断电。新窗口日志/状态必须出现`ACTION_INITIAL_CLEAR`和`ACTION_LINK_READY`；若仍没有，保留新run目录再诊断，不进行PL重载。

## 最新停点：断电重启后的v1.4第二次加载同样成功

当前累计两次v1.4成功，其中第二次为用户确认的真实断电后复现。不要继续无目的重复点击加载；模型窗口关闭已经完成CLEAR，但不代表板端自动恢复原视频。若本轮测试结束，请先明确要求恢复，然后只执行一次“恢复原视频”并分别核对动态HDMI和UDP。若需要把结果升级为比赛级可靠性结论，应先增加boot ID记录，再按预注册的独立冷启动次数执行，保留每次首帧时间且禁止隐藏重试。

## 最新停点：v1.4动作版运行成功，等待用户决定是否结束测试

五项启用手势及对应LED已由用户确认通过，上位机关闭时已发送AXI CLEAR；但动作版板端service通常仍保持运行，不能仅凭GUI关闭推断原视频已恢复。不要再次点击“一键加载动作版PL”。若本轮测试结束，下一步应由用户明确要求恢复，然后只执行一次“恢复原视频”，并分别核对动态HDMI与UDP；若仍继续手势测试，则保持当前动作版，不重载。多循环可靠性验证另行立项，不能用本次单次成功直接宣称热重载问题彻底解决。

## 最新停点：v1.4已交付，等待一次受控上板

首个动作：用户确认当前原HDMI/UDP动态、流畅后，运行`E:\competition\8_tools\EES331_PL_Reloader_v1.4\EES331_PL_Reloader.exe`并只点击一次“一键加载动作版PL”。默认SSH密码仍为`xilinx`。

观察门：GUI应实时出现`SENSOR_SETTLE_BEGIN/PROGRESS/COMPLETE`和`FIRST_FRAME_WAIT`；成功必须出现`VDMA_STREAM_STARTED`、`VIDEO_READY_BEFORE_ACTION`、`ACTION_SERVICE_READY`及控制器`ACTION_OVERLAY_READY`。仅等待结束或PL下载成功不是PASS。

禁止立即动作：失败后不要再次点击加载、不要继续加长30秒门、不要修改BIT/HWH/AXI地址或冻结`2_fpga`。先保存首次v1.4主机日志，检查是否出现`FIRST_FRAME_TIMEOUT`及`ORIGINAL_RESTORE_READY`，再人工确认原HDMI/UDP恢复。下方G1待批准和v1.3入口均为历史停点，以本节为准。

## 当前审核门：是否批准G1可观测性改造

先读[完整解决方案](../../4_metrics/logs/2026-09-13_action_reproducibility_solution_plan_run01/REPORT.md)。推荐下一步仅实施G1：把v1.4远程输出改成实时流式事件、阶段计时和唯一run标识，并补齐现有软件可读的下载/VDMA/缓冲证据；保持当前BIT/HWH、Camera行为、1秒等待和5秒门不变，不连接板卡。G1离线测试和打包报告完成后再审核G2。未获批准前不再次加载、不改RTL/地址/超时，也不改SD/BOOT/systemd。

## 当前第一动作：保持原视频，不再点击加载

本次动作BIT已经下载但在首帧门失败，工具已安全恢复原服务，用户确认HDMI正常。当前关闭错误框和v1.3窗口是安全的；不要再次点击“一键加载”，不要用偶然成功覆盖本次 `FIRST_FRAME_TIMEOUT`。继续开发时先读[失败审计](../../4_metrics/logs/2026-09-13_pl_reloader_v13_board_failure_audit_run01/REPORT.md)。先离线实现控制器stdout流式显示；任何下一次板测须先审核单变量观测方案，并保持同一BIT/Camera/5秒门，只增加摄像头/SCCB、帧计数和VDMA状态证据。成功标准是找到首个可重复分歧，不是单次重试出帧。

## 当前唯一下一步：上电后先运行 v1.3“检查状态”

开发板当前断电，v1.3 离线包已交付。下次上电并等待启动稳定后，双击 `E:/competition/8_tools/EES331_PL_Reloader_v1.3/EES331_PL_Reloader.exe`；密码框已自动填充 `xilinx`。第一步只点击“检查状态”，把完整状态回传；在确认原 `ees331-camera`、动态 HDMI 和 UDP 视频前，不点击加载。成功门依次为真实 `ACTION_OVERLAY_READY`、PC `ACTION_LINK_READY`、AXI 完成回执及物理 LED。不得再用 `ACTION_ALREADY_RUNNING_NO_RELOAD`、模型出框或 GUI 蓝字替代加载成功证据。

## 当前唯一下一步：修复并重打包进程检测

不要重复点击当前 v1.2 的“一键加载动作版PL”；它会把 `pgrep` 查询命令自身误认为 `camera_action_v1.py`，继续走 `ACTION_ALREADY_RUNNING_NO_RELOAD` 假成功分支。先在源码中改为严格识别真实 Python 动作进程，并让跳过分支额外验证动作协议/端口与 Overlay 身份；随后完成离线回归和新版本打包。板测时只有依次出现真实 `ACTION_OVERLAY_READY`、PC `ACTION_LINK_READY`、AXI 完成回执和物理 LED，才算加载及动作链路通过。当前不要改 RTL/地址/位流，也不要用识别画面是否出框替代动作链路验收。

## 当前唯一下一步：运行v1.2并先检查状态

不要再运行v1.1。双击`E:/competition/8_tools/EES331_PL_Reloader_v1.2/EES331_PL_Reloader.exe`，输入板卡SSH凭据，仅先点击“检查状态”。若提示`无法连接开发板192.168.240.10:22`，先确认板卡已上电、网线连接，并把PC有线网卡IPv4恢复为`192.168.240.2`、掩码`255.255.255.0`；此时程序尚未停止服务或加载PL。若显示`SSH连接成功`并列出`ees331-camera`状态，再确认原HDMI/UDP动态流畅，勾选门禁并点击“一键加载动作版PL”。把窗口中的第一条错误或`ACTION_OVERLAY_READY`结果原样回传；失败时不要连续点击。v1.2离线验收见[报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run03/REPORT.md)。

## 当前下一步：使用v1.1 GUI实机加载

不再继续手工命令。双击`E:/competition/8_tools/EES331_PL_Reloader_v1.1/EES331_PL_Reloader.exe`，输入SSH密码，确认原动态HDMI/UDP后勾选门禁并点击“一键加载动作版PL”。看到应用报告`ACTION_OVERLAY_READY`后核对HDMI与动作LED；需要回原基线时点击“恢复原视频”并再次人工确认动态画面。首次GUI按钮实机结果尚未取得，失败时保留自动生成的PC/板端证据，不连续重试。

最终离线交付与限制见[报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run02/REPORT.md)。v1.0为中间构建，不推荐使用；不删除以保留构建历史。

## 当前现场下一步：确认动态画面后安全停止原服务

当前 `ees331-camera`/原 `camera.py` 已确认是VDMA所有者。用户先肉眼确认HDMI动态流畅（以及正在使用时的UDP动态画面）；确认后执行 `sudo systemctl stop ees331-camera`，再只读检查MainPID/进程和本次boot journal。必须看到 `VDMA_HALTED`、`BUFFER_FREED` 且无残留 `camera.py`，才能进入动作Overlay C单次加载。停止失败或释放标记缺失即停，不下载PL。

## 当前现场下一步：修正板端目录变量并只读确认所有者

在现有SSH终端执行 `export ACTION_APP_DIR=/home/xilinx/action_e2e_20260913_run01` 和 `cd "$ACTION_APP_DIR"`；不要使用不存在的 `/home/xilinx/action_v1_20260913`，也无需重新上传或重新编译。随后只读核对 `pwd`、BIT/HWH/Camera哈希、`ees331-camera`状态及 `camera.py|camera_action_v1.py` 进程。未确认当前所有者和原视频基线前，不停止服务、不运行 `run_action_v1.sh`、不重载PL。

## 当前下一步：等待用户按手工流程冷启动复现

第一动作是保持 SW8 为 SD 启动、连接摄像头/HDMI/网线后上电，等待原视频服务，并确认动态 HDMI 与 UDP基线。随后严格按[手工复现方案](../../4_metrics/logs/2026-09-13_action_v1_manual_repro_plan_run01/REPORT.md)从 A 单次切入 C。禁止从已加载 C 的状态直接跨进程再次启动；失败保留证据并停在首个失败门。

用户需明确回复“复现成功”并说明看到的 READY/视频/LED结果。收到该确认前，不开始第二阶段应用，不改SD自启动、不覆盖原视频目录、不修改冻结 `2_fpga`、不执行新的硬件加载。确认后，第二阶段首要任务是把固定包校验、板端上传/复用、原服务安全停止、单次Overlay加载、READY检测、失败留证和原服务恢复封装为可重复使用的上电后应用。

## 最终收尾：用户明确暂缓热重载，第一版功能目标完成

用户已结束手工测试，并明确要求重加载故障暂不解决，待其自行重加载再复现时处理。五项真实模型→AXI寄存器→PL UART/LED输出已验证，交付提交612d7b3已推送个人分支；见[完成审计](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/completion_audit.md)。热重载仍是已知未解决项，不再自动诊断或加载。未执行此前口头计划的最后恢复操作，不声称当前原视频已恢复；收尾不操作板卡。下方“继续解决热重载/目标活动/手工测试中”等为历史状态，以本段为准。

## 当前后续门禁

功能检查点已推送612d7b3到个人分支。热重载仍待定位，见[假设与下一门禁](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/reload_hypothesis_review.md)。用户尚未明确结束手工测试，不能停止GUI/服务或重新加载PL。先取得结束测试确认，再读取当前所有者、保存现场证据并安排受控诊断；不得依赖旧PID。失败在动作挂接前，不能盲改AXI地址或加等待声称修复。

## 最新交接：五动作真实闭环通过，热重载失败保留，用户持续GUI测试中

见[完整链路报告](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/REPORT.md)。
1500真实推理帧、五动作均三帧证据、18条/126字节COM4完全匹配；板端859.5秒4296帧、1028命令COMPLETE，安全HALT/FREED。
随后持续模式跨进程C重载首帧失败，已保存board_manual_runtime，不是动作触发；原A恢复PC65帧/用户HDMI通过后，同一systemd程序从A切C成功。根因未确认，禁止称部署稳定。
当前板端ees331-action-e2e-manual2.service持续运行，原服务停止但SD/原文件未改；PC gui_manual无自动退出。用户要求继续测试，**不得自动关闭GUI/停服务/重新加载**。
GUI90秒提前关闭问题已纠正；用户已确认Stop/Up/Down/拇指上/拇指下对应LED4/7/1/6/5，最后再次确认“对的对的，拇指向下对应的led5亮了”。五项物理映射核对全部通过，证据见完整链路报告与physical_gui_manual.json。此反馈不代表用户结束测试；先查实时进程/服务句柄，不依赖旧PID。
恢复仅在用户确认测试结束后进行，先正常退出模型清灯，再停动作服务确认HALT/FREED，再启动原服务并验证UDP/物理HDMI。
五项GUI物理确认已完成；剩余热重载可靠性修正与受控验证、文档及个人分支交付仍待完成，不将功能映射通过等同部署问题已解决。
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

第一步：读准备报告，通知用户可以上电；保持原SD及接线，约90秒后确认cfg_done/动态HDMI，普通UDP接收器和COM4工具保持关闭。未经基线与DMA门禁不得下载；旧部署流程仍暂停。下一步成功标准为受控对照与原视频恢复的独立证据。
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

## 最新交接：先读系统审计，禁止沿旧流程再次盲测

首先阅读[系统审计](../../4_metrics/logs/2026-09-13_action_v1_regression_review_run01/REPORT.md)。
不要把旧skill当部署授权或正确性证明，不自动下载，不盲改地址/时钟/复位/超时，不提前Git发布。
根因未确认；已大幅降低CSR地址冲突与产物混配假设，明确动作错误连带停止视频的软件隔离缺陷。
剩余离线项：视频构建溯源、路由后时钟路径比较及唯一加载/完整事件流诊断入口审查。
实际T0/T1/T2板测前需恢复本机有线链路并确认独立测试窗口；最近60帧及HDMI恢复是上一轮证据。
下一阶段成功标准：固定对照下找到第一处可重复分歧，再做对应层最小修改；视频与动作故障隔离分别验收。

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

## 当前继续点：网线/动态视频基线恢复后做第一版板测

先读[action_v1_status.md](../../2_fpga/0_diaplay_test/doc/action_v1_status.md)与本日03_validation_summary。
第一版OFFLINE_PASS，最终主构建run03、Python回归run05、EXE构建run04/自检run03、
发布action_v1_uart_run01均已完成。无需从草稿重新实现，也不必重跑此前失败版本。

阻塞：当前PC有线网卡Disconnected/0bps、SSH无banner，用户连接确认尚未返回。
下一步先核对板卡已上电/网线连接/动态HDMI；建立新的只读网络、服务、哈希和UDP基线证据。
不能因COM4/COM6枚举正常就认定板卡或新PL功能正常。

禁止立即运行旧通用AXLT驱动读ACTL、盲读0x43C00000、停服务或自动重新下载。
新包位于2_fpga/0_diaplay_test/release/action_v1_uart_run01；
其manifest为board_validated=false。新上位机在8_tools/EES331_Action_Viewer_v1.0；
Start_Action_Verification.ps1才显式启用动作，直接双击EXE只识别显示。

网络和原动态视频确认后：独立板端目录上传/校验→编译ARM C屏障库→控制窗口停旧服务/
VDMA停稳→配对Overlay分步加载/身份/单命令→1000条PC网络到PS/AXI与COM4完整比对/
LED可视核对→五种自动动作、三帧门与超时CLEAR→HDMI/UDP共存及原服务恢复。
每阶段先报告后推进，失败不覆盖、不自动重试未知命令。第二版蓝牙动作尚未批准执行。
无关机授权，保持计算机运行。全部实机验收通过后才按个人分支策略选择性Git提交推送；
脏工作区和既有个人worktree不能清理或覆盖。

以下旧的审核暂停/旧版板测停点均为历史，不覆盖本节。

## 最新：用户批准第一版执行

用户确认 Left/Right 暂不自动下发，采用三个不同新视频帧连续同类且各置信度 >=0.75，
稳定后只发送一次；无效结果打断连续计数，连续一秒无有效结果发送一次 CLEAR。
第一版执行已获授权，按独立仿真、BD 构建、板测顺序推进并报告；第二版尚不执行。
当前源与工程快照保存在
[source_run01](../../4_metrics/logs/2026-09-13_action_v1_source_run01/source_hashes.json)。
新动作 RTL 为此前草稿，正进行补齐和验证，尚无本版仿真、构建或板测 PASS。

## 最新继续点：等待两版方案审核

先请用户审核
[两版方案](../../2_fpga/0_diaplay_test/doc/axi_action_uart_ble_two_version_plan.md)，
重点是：动作/LED 映射、模型稳定门默认值、PC→PS UDP 5001 回传格式、AXI 扩展寄存器、
UART 7 字节帧，以及第二版采用同一 UART 波形同时驱动 COM4 与 MLT-BT05。未收到明确
执行批准前，不运行草稿 RTL 仿真，不修改 XPR/BD/XDC，不构建或上板。

当前工程中的三个动作 RTL 文件仅为审核指令到达前的未验证初稿。批准后先按评审意见
修订并跑第一版独立仿真，完成后报告并按既定门继续；不要直接跳到第二版或主工程位流。

## 最新继续点：实现 AXI 动作执行器，不再走 UART RX

继续时以 `PS 写 AXI ACTION_CODE/SEQ/START，PL 点灯并从 COM4 TX 发帧` 为唯一有效
架构。不要实现 PC 直接向 COM4 发动作、PL UART RX 解析后点灯的旁路方案。串口帧
固定承载一个动作字节，其他字段仅用于封装和校验。先完成独立 RTL 自检仿真；仿真
未通过前不修改 BD、不重建主位流、不上板。主工程改造时保留 V4 摄像头 cfg_done，
动作映射到其余七个 LED，并移除主数据流中的蓝牙桥；蓝牙项目本身保持不动。

## 最新继续点：确认 HDMI 后发布个人分支

主工程本地仿真、BD、新位流、时序/DRC、HWH 合同和发布哈希均已通过。网线恢复后，
同一集成位流上的 130 秒视频、PC 400 帧、1000 条 AXI 命令及蓝牙双向 11 轮均
通过；原服务恢复后 PC 又收到 100 帧。最小下一动作是由用户确认刚才集成窗口以及
当前恢复状态下的 HDMI 都是正常动态画面。

板端测试目录为 `/home/xilinx/main_axi_ble_20260913_run01`，原
`/home/xilinx/ees331_camera` 未覆盖；首次无网线载波和首个审计字符串判断失败均已
保留。无需重复下载或重复命令，除非用户未观察到集成窗口 HDMI 而明确需要再次展示。

HDMI 确认后更新最终文档和 skill，再选择性提交个人分支
`codex/full/pipidandan-superman`，不提交或合并 `main`。BRAM 仍不实施。用户已撤销
关机步骤；没有待取消的关机任务，全部完成后也保持 Windows 运行。

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

先读 E:/competition/2_fpga/2_axi_lite_test/doc/validation.md 及本日验证摘要。
等用户明确开始并上电后，先确认现有SD正常启动PYNQ、实际网络与Python环境、原视频服务和动态视频可用，再运行独立寄存器板测。
禁止立即下载、重刷SD、覆盖原视频目录、注入非法AXI访问、失败自动重发或未验收进入BRAM/主工程合并。
最小下一步：用户上电并确认PYNQ可登录。成功标准为1000轮/3次重载及视频实际恢复，全部原始证据存新4_metrics/logs目录；失败不覆盖。

## EES-331 PYNQ SD 密码提示下一步

先让队友用 `ssh xilinx@192.168.240.10` 登录，默认密码 `xilinx`。若仅出现 `[sudo] password for xilinx:`，仍输入 `xilinx`。刷写完整 IMG 后不运行 `install.sh`，只执行只读状态检查：`systemctl status ees331-camera --no-pager`。

若密码失败或提示实际是 `root@... password:`，停止连续尝试，取回完整命令、提示原文、登录用户名，以及确认写入的 IMG 文件名/哈希。禁止为绕过提示而启用 root SSH、设置空密码或重打包镜像。

证据：[只读审计报告](../../4_metrics/logs/2026-09-13_sd_root_password_audit_run01/REPORT.md)。

## EES-331 PYNQ SD 镜像交接

当前最小动作：运行并监督[成像脚本](../../4_metrics/logs/2026-09-13_sd_card_raw_image_run01/capture_sd_image.ps1)，保持 `Disk 1` 与桌面目标路径不变，等待完整读取和回读哈希结束。

禁止立即动作：成像期间不要拔卡、休眠、重启或让其他程序写 `G:`；不要把 `.partial` 交给队友；不要用文件压缩包替代整盘镜像；不要写入或修改冻结 `2_fpga/`。

成功标准：`result.json` 标记 `SD_RAW_IMAGE_PASS`，正式 IMG 长度为 `15,634,268,160` 字节，流式与落盘回读 SHA-256 一致，桌面同时存在 IMG、SHA-256 文件和复现说明。队友烧录后的真实冷启动、SSH、服务、HDMI/UDP仍需单独验收。

本轮成像已完成：`SD_RAW_IMAGE_PASS` / `IMAGE_VERIFICATION_PASS`。队友下一步先按桌面 `README_队友复现.txt` 校验 IMG 哈希，再写入实际容量不小于源卡的 SD 卡。烧录后按冷启动顺序验收；若同网段还有另一块 `192.168.240.10` 板卡，先断开以避免 IP 冲突。失败时保留写盘工具原文、目标卡精确容量和首次启动日志，不直接重打包 IMG。

源 SD 卡已由 Windows 安全弹出，结果 `DISK_SAFE_EJECT_PASS`，可以物理拔出。后续若再次插入，不自动写入或修复；只有用户明确要求时才重新检查或成像。

## 队友直接复现视频链路

把桌面 `ees331_pynq_sd_20260913_full.img`、同名 `.sha256` 和 `README_队友复现.txt` 一起交给队友。队友先校验 SHA-256 为 `488939D8CC6B3A62F7F7CF38F8BDC71C79ECED587DF80D623B453EF26178E7CA`，再写入实际容量不小于 `15,634,268,160` 字节的 SD 卡（推荐 32 GB）。不要交付 Builder EXE、基础 IMG、启动分区 ZIP/IMG或 `.partial` 作为替代。

冷启动时保持板卡 `192.168.240.10/24`、PC `192.168.240.2/24`、UDP `5000`，并断开同网段其他同 IP 板卡。只有 HDMI 与 PC UDP 画面均随镜头前物体持续变化，才算队友现场复现通过。
