# 2026-09-13 执行计划

## 最新执行：v1.4个人分支交付

1. 定点删除`8_tools/EES331_PL_Reloader_v1.0`～`v1.3`，确认v1.4仍在；不删除任何失败证据。
2. 在独立`codex/full/pipidandan-superman`工作树复制v1.4源码、完整发布包、动作Overlay增量和29个精选证据文件。
3. 用动作版EXE及唯一差异`base_library.zip`升级已有共享Viewer运行目录，并增加轻量动作启动脚本，避免重复上传约761MB依赖。
4. 更新README、HANDOFF、工具/Overlay/Viewer说明和队友上板指南，固定“直接双击仅显示、必须从v1.4内部启用动作”的规则。
5. 提交前执行19项源码测试、两个EXE自检、1006文件发布清单核验、BIT/HWH/EXE哈希与Git/LFS范围审计；仅全部通过后提交并推送个人分支。

## 最新执行结果：正确入口重开验证PASS

关闭display-only实例后通过v1.4 GUI内部按钮启动，动作客户端读取板端既有序号8并以9续接，未重载PL即恢复模型到AXI/LED链路。后续使用约束固定：需要LED输出时只从v1.4“打开动作识别”进入；直接双击Viewer EXE仅用于显示预测。

## 最新处理：上位机重开无LED的最小恢复

只读核对最新viewer运行，确认视频与模型正常但动作protocol未创建。保持当前动作PL/service，不重新验签、不停服务、不重载。唯一操作为关闭当前仅显示窗口，并从v1.4 PL Reloader点击“打开动作识别”；以`ACTION_INITIAL_CLEAR`和`ACTION_LINK_READY`为进入LED测试的硬门。

## 最新执行结果：v1.4断电冷启动复现run02 PASS

用户断电并重新上电后再次运行v1.4；程序从新原服务基线进入，完成验签、安全停A、加载C、10秒等待、VDMA双向转换、视频READY与动作READY。模型新一轮五项动作均有三帧门和seq/done_seq ACK。当前继续保持单次操作原则，不自动追加重载；若结束测试，下一阶段仅恢复原视频并核对动态HDMI/UDP。后续v1.5可增加boot ID采集，使冷启动不再只依赖人工说明。

## 最新执行结果：v1.4受控单次上板PASS

用户执行v1.4后，原服务PID594经`ORIGINAL_STOP_SAFE`退出，动作BIT加载、10秒等待、VDMA真实帧转换、视频READY、ACTL READY及Overlay READY依次通过。随后用户完成五项启用手势物理LED核对；上位机退出前发送CLEAR。当前不自动继续循环重载，也不把单次成功当作10秒最小值证明。若用户结束测试，下一门为明确授权后的原视频恢复及动态HDMI/UDP确认；若继续研究可靠性，应另开不可覆盖的多循环测试计划。

## 最新执行：v1.4延长等待与实时日志

1. 保持动作BIT/HWH、AXI地址、VDMA配置顺序及失败恢复路径不变。
2. 将传感器定时预等待设为10秒并逐秒记录进度，明确它不是传感器就绪证明。
3. 将首帧槽位转换门设为30秒，每秒记录槽位、seen及MM2S/S2MM状态；超时仍失败关闭。
4. 板端控制器将动作service journal增量转发，READY总门扩至75秒；Windows SSH逐行流式显示，主机load超时扩至180秒。
5. 更新载荷manifest哈希、v1.4源码测试和文档，构建到独立证据目录与全新发布目录。
6. 下一阶段只做一次受控上板：从人工确认动态原视频基线进入，成功则核对HDMI/UDP/动作READY；失败则禁止自动重试并核对原视频恢复。

风险与停止条件：增加等待只能覆盖迟到首帧，不能修复摄像头未重新配置或无PCLK/VSYNC；若30秒仍无转换，保留首次证据并停止，不继续放宽超时。

## 待审核执行顺序：先G1，再G2，不直接改RTL

完整路线见[动作复现解决方案](../../4_metrics/logs/2026-09-13_action_reproducibility_solution_plan_run01/REPORT.md)。若获批准，第一阶段仅改v1.4主机日志流式显示、阶段计时、run UUID和板端结构化证据，不改变位流/Camera/5秒门；完成后单独报告。第二阶段再执行V0–V4纯视频单变量矩阵，每格失败取证后恢复，不自动重试。只有定位SCCB、PCLK/VSYNC、采集AXIS、S2MM/DDR或MM2S中的第一处分歧后，才审查对应的唯一修复。动作版冷启动主线及任何SD/BOOT/systemd改变需另行授权。

## 当前停点：原视频已恢复，不重复加载

本次真实 A→C 已在动作位流下载后触发 `FIRST_FRAME_TIMEOUT`，安全恢复完成且用户确认 HDMI 正常。停止继续点击 v1.3、停止模型/LED验证，不通过延长5秒门或重试取得偶然成功。下一工程步骤分为两项且均未执行：先让GUI流式呈现板端控制器事件，消除“卡住”错觉；再固定同一BIT/Camera/超时，只增加摄像头/SCCB就绪、采集时钟/帧计数和VDMA首状态变化观测，定位与历史成功运行的第一处分歧。

## v1.3 已离线完成，等待下次上电后的分阶段实机门

已完成源码修复、16 项测试、独立离线构建和整包复核。开发板当前断电，不执行任何网络或 PL 操作。下次上电后只运行 `E:/competition/8_tools/EES331_PL_Reloader_v1.3/EES331_PL_Reloader.exe`：先点击“检查状态”，确认原 `ees331-camera` 与动态 HDMI/UDP 基线，再单次执行 A→C。只有 `ACTION_OVERLAY_READY` 才进入动作识别；随后分别验证 `ACTION_LINK_READY`、AXI 完成回执和物理 LED。任一门失败立即停止，不重复加载。

## 当前停点：先修复 v1.2 假阳性，不再重复点击加载

本次 `ACTION_ALREADY_RUNNING_NO_RELOAD` 由 `pgrep` 自匹配造成，不能作为动作版已经运行或 PL 已加载的证据。当前动作识别窗口虽然继续收帧和推理，但 `ACTION_LINK_FAILED` 后不会发送动作。未经新版本修复、离线回归和重新交付，不再点击“一键加载动作版PL”，也不把模型框选结果当作 LED 链路成功。修复后的实机顺序必须取得真实 `ACTION_OVERLAY_READY`，再取得 `ACTION_LINK_READY`、AXI 完成回执和物理 LED 确认。

## 当前执行入口：v1.2 OpenSSH版

停止使用v1.1。运行`E:/competition/8_tools/EES331_PL_Reloader_v1.2/EES331_PL_Reloader.exe`，输入板卡SSH凭据后先点击“检查状态”。程序先检查`192.168.240.10:22`：若不可达，只检查板卡上电、网线和PC有线网卡`192.168.240.2/24`，不会停止服务或加载PL；若SSH状态检查通过，再确认原HDMI/UDP动态流畅、勾选门禁并点击“一键加载动作版PL”。第一次出现错误即保留日志并停止，不连续重试。v1.2离线交付见[验证报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run03/REPORT.md)，实机按钮仍待用户执行。

## 当前交付入口：GUI替代手工命令

直接运行`E:/competition/8_tools/EES331_PL_Reloader_v1.1/EES331_PL_Reloader.exe`。输入SSH密码，确认原动态HDMI/UDP并勾选门禁，然后点击“一键加载动作版PL”。程序自动同步固定载荷、双重验签、确认原所有者、HALTED/FREED后切换、等待`ACTION_OVERLAY_READY`；动作版已运行时拒绝重复下载。需要回退时点击“恢复原视频”。首次实机仅做应用按钮验证，不修改RTL/BD/SD启动文件、不设置动作自启动。

## 当前阶段：用户手工复现门禁

1. 冷启动并验收原 `ees331-camera.service`、cfg_done、动态 HDMI 和 UDP5000。
2. 使用 `9_pynq/overlays/action_v1_20260913` 固定包；优先复用板端已上传目录，不覆盖原视频目录。
3. 停止原服务，确认 `VDMA_HALTED`、`BUFFER_FREED` 和进程退出。
4. 从原 Overlay A 状态单次启动 `run_action_v1.sh`，使用唯一证据目录；禁止已加载 C 时直接跨进程再次加载 C。
5. 看到 `VIDEO_READY_BEFORE_ACTION` 与 `ACTION_SERVICE_READY` 后才启动 PC `Start_Action_Verification.ps1`，核对模型、AXI确认和物理 LED。
6. 结束时先关闭 PC窗口发 CLEAR，再 Ctrl+C 停板端程序，确认释放后恢复原服务及动态视频。
7. 用户明确报告复现成功后，才设计并实现上电后可直接在线加载必要文件的第二阶段应用。

完整命令、PASS/STOP标准见[手工复现方案](../../4_metrics/logs/2026-09-13_action_v1_manual_repro_plan_run01/REPORT.md)。本阶段不执行板卡命令。

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

上电后先重新确认原视频和boot ID，再独立上传核验；每组前原A基线、停服务确认HALT/FREED，S1通过并恢复后才S2；实时日志与物理HDMI、PC UDP分开验收。失败不重发、不覆盖，安全恢复。
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

## 最新执行顺序：审计 → 固定对照 → 观测第一处分歧 → 最小修复

见[系统审计第8节](../../4_metrics/logs/2026-09-13_action_v1_regression_review_run01/REPORT.md)。
旧Overlay skill暂停用于部署，不作为正确性依据；当前没有新增板卡操作。
T0旧位流/旧视频入口，T1同位流/新video-only包装，T2动作位流/同video-only入口，每格唯一下载，
固定前置状态与哈希。只有对照通过才前进；T2通过后才考虑单独加载次数对照。
60–90秒为用户上电总体验，不能与PL_LOADED后的5秒直接等同；有界延迟观测须独立标记诊断。
动作服务故障隔离另立修复与注入测试，不冒充首帧根因修复。板测需链路恢复及明确独立窗口。

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

## 当前执行结果：第一版离线门完成

顺序执行：源/工程快照→独立AXI/UART仿真1002命令→官方reset及真实9600仿真
→独立AXI_LITE_test工程→主视频BD集成/验证→完整综合与布局布线→发布审计。
PC/PYNQ离线回归最终14项通过；冻结模型EXE自检通过。

主构建run01旧M19网名失效，run02 XDC不支持if且属性未生效，均保留失败且不发布；
run03把物理约束单独标为仅实现使用，验证真实网属性后通过。setup10.402ns、
hold0.020ns、黑盒0、DRC Error0、Critical Warning0。普通视频I/O/CDC告警限制保留。
Python run04测试夹具时间戳重合失败；确认Windows单调时钟分辨率0.015625s，
夹具改为真实分时帧后run05通过；未放宽生产稳定门。

按zynq-pynq-overlay-workflow停在板测前：Ethernet Disconnected/0bps，SSH无banner。
安全下一步为只读基线核对和动态HDMI确认；禁止无网络基线时盲读CSR。
实机时先停止原服务、确认VDMA停稳、分步加载/身份/单命令，再1000条与模型动作验证，
最后恢复原Overlay/视频。异常结果与恢复失败必须留存；未完整通过不Git发布。
第一版的源、发布包、完整证据入口见03_validation_summary.md和action_v1_status.md。

以下是历史计划，不覆盖当前结果。

## 最新：用户批准第一版执行

用户确认 Left/Right 暂不自动下发，采用三个不同新视频帧连续同类且各置信度 >=0.75，
稳定后只发送一次；无效结果打断连续计数，连续一秒无有效结果发送一次 CLEAR。
第一版执行已获授权，按独立仿真、BD 构建、板测顺序推进并报告；第二版尚不执行。
当前源与工程快照保存在
[source_run01](../../4_metrics/logs/2026-09-13_action_v1_source_run01/source_hashes.json)。
新动作 RTL 为此前草稿，正进行补齐和验证，尚无本版仿真、构建或板测 PASS。

## 最新：执行暂停在用户审核门

两版完整实现顺序、寄存器表、PC→PS 网络动作包、PL UART 帧、蓝牙冲突处理和分阶段
验收已写入
[方案文档](../../2_fpga/0_diaplay_test/doc/axi_action_uart_ble_two_version_plan.md)。
用户审核前不继续任何代码或硬件动作。审核通过后的第一步也不是直接改主 BD，而是先
修订现有 `DRAFT_UNREVIEWED` 初稿、建立 Python 参考编解码器并完成第一版独立自检
仿真；每一阶段报告后再按门推进。

## 最新：AXI 动作命令到 LED/UART 的实施门

实施顺序固定为：先冻结动作映射和串口帧；再实现独立的 AXI 动作寄存器组、PL UART
TX 组帧器和 LED 执行器；完成错误访问、序号、BUSY/DONE/ACK、七类动作、CRC、复位
的自检仿真；只有仿真 PASS 后才改主工程 `display_test` BD。主工程中 PS GP0 仍映射
4 KiB CSR 到 `0x43C00000`，PS 通过 `ACTION_CODE/CMD_SEQ/CONTROL.START` 提交；PL
在动作 LED 已更新且完整 7 字节串口帧发完后发布 DONE。COM4 仅接收 PL TX 输出，
不作为 PS 到 PL 的控制入口。

主 BD 将移除 `ble_uart_bridge_0` 及 BT 外部端口，加入 Verilog Module Reference 动作
控制顶层和 `PL_RS232_TX/ACTION_LED[6:0]` 端口；V4 摄像头灯不变。随后重新综合、布局
布线、BIT/HWH/XSA、HWH/哈希审计，再决定实机测试窗口。失败证据保留，不能用此前
BLE 共存 PASS 覆盖新版本失败。Git 只在新版本全部验收后选择性发布个人分支。

## 最新：主工程自动化实机共存已通过

已完成：保存主工程基线；以 Verilog Module Reference 集成 AXLT；集成透明蓝牙桥；
固定 AXI `0x43C00000/4 KiB`、VDMA `0x43000000/64 KiB` 和 50 MHz 控制时钟；
完成包装层 XSim、独立进程 BD 检查、实现及时序/DRC、BIT/HWH/XSA 发布和失败关闭
HWH 审计。M19 非专用时钟输入在实现后的 PLL 使用 `BUF_IN`，构建检查实际单元属性。

实机已执行：发布物上传到独立目录并验证哈希，原服务正常停止，集成 Overlay 运行
130 秒；PC UDP、1000 条 AXI 命令和 MLT-BT05/COM4 双向 11 轮在同一窗口通过。
集成程序正常 halted VDMA 并释放缓存，原服务随后恢复 active，UDP 新帧再次通过。
板端原目录没有覆盖。首次无网线载波的预检失败和后续成功均保留。

待用户确认集成窗口及恢复后的 HDMI 动态画面后，更新最终板测标记、同步技能/文档，
再选择性复制到干净个人 worktree、提交并推送
`codex/full/pipidandan-superman`。BRAM 不进入本次主工程集成。用户已撤销关机步骤，
任务完成后也不关闭计算机；当前不存在待取消的关机任务。

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

已读取项目工作区/日志技能、前日相关交接及现有validation.md、board_test.py、axilt.py、mmio_ordered.c。
按现有实现核对：SD启动PYNQ -> SSH与视频基线确认 -> 独立目录复制匹配产物和软件 -> ARM编译 -> 自动板测 -> 视频实际恢复 -> 取回证据。
风险：Overlay替换整个PL，视频临时中断；Python路径/板端IP需实机确认；C访问层尚未实机编译；服务恢复不等于视频恢复。
回退：失败保留原记录，先查events.jsonl/result.json及服务日志，不盲目重试。不执行任何板端命令。

## EES-331 PYNQ SD root 密码提示诊断

1. 核对目标 IMG 唯一文件、SHA-256 和既有构建读回证据。
2. 核对 `ees331-camera.service`、`run_camera.sh`、`install.sh`，区分自动启动与手工安装权限。
3. 核对既有 PYNQ 3.0.1 板端连接脚本及 PYNQ 官方凭据说明。
4. 向队友提供 `xilinx` 登录、sudo 密码与 `systemctl status` 的最小指令；若原文不同，则要求保留完整提示后再分流。
5. 不读取或修改密码哈希，不重打包 IMG，不操作板卡。

## EES-331 PYNQ SD 整盘镜像执行计划

1. 只读确认 `Disk 1` 的 USB 总线、非系统盘属性、精确容量、MBR 分区表、FAT 启动分区和 Linux 分区签名。
2. 对 `G:` 执行不带修复参数的只读 CHKDSK；出现明确文件系统错误则停止成像并报告。
3. 用固定设备路径 `\\.\PhysicalDrive1` 只读顺序读取全部 `15,634,268,160` 字节，桌面先写 `ees331_pynq_sd_20260913_full.img.partial`。
4. 同步计算源数据 SHA-256；写完后检查长度，再从桌面文件回读计算 SHA-256。两次哈希一致才改名为正式 `.img` 并生成 `.sha256`。
5. 生成复现说明，记录队友应使用不小于源卡实际扇区数的介质；烧录后先做启动、SSH、服务、HDMI/UDP和网口冲突检查。

风险与停止条件：设备编号、USB属性、容量或分区指纹变化即停止；读错误、短读、空间不足、长度或哈希不一致均保留 `.partial` 与失败证据，不宣告可交付。目标 IMG 已存在时拒绝覆盖。

## 队友 SD 包选择核对步骤

1. 只读核对桌面正式 IMG、同名 SHA-256 文件和复现说明均存在。
2. 对照当天成像报告确认精确长度、SHA-256 与结果标记。
3. 对照项目镜像清单，排除基础镜像、启动分区镜像/ZIP和 Builder EXE。
4. 向队友给出完整 IMG、校验值、目标卡容量、固定 IP/端口和冷启动验收要求。
