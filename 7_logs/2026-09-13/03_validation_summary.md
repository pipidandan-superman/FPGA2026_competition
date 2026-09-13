# 2026-09-13 验证摘要

## 最新发布：个人分支远端回执PASS

- 内容提交`63343aa314c27bd64f44210cc35ae144bdc16c13`已推送到`codex/full/pipidandan-superman`。
- Git LFS上传20/20对象、72 MB完成；重新fetch与`ls-remote`均返回同一远端HEAD，dry-run无待上传LFS对象。
- 暂存/提交范围不含冻结`2_fpga`和PL重加载器v1.0～v1.3；独立工作树原有4个无关未跟踪审计文件仍未纳入。
- 详细范围、清理记录、测试与远端回执见[发布报告](../../4_metrics/logs/2026-09-13_pl_reloader_v14_github_publish_run01/REPORT.md)。

## 最新验证：v1.4发布候选离线核验

- `test_pl_reloader.py`：19项通过。
- `EES331_PL_Reloader.exe --self-test`：`PL_RELOADER_SELF_TEST_PASS`，版本1.4，13项载荷，BIT/HWH哈希匹配。
- v1.4 `package_manifest.json`：1006项逐文件SHA-256核验，0失败。
- 共享动作兼容Viewer `--self-test`：退出码0；EXE SHA-256 `92790d9d232fa66604cab34c8560cce5439eba3f6a78a673aee44cc972b9e1aa`，`base_library.zip` SHA-256 `ab41a8807584e1ed863491ce597364d24b0102683b316f5eeab679a2a85a4c68`。
- v1.4 EXE SHA-256 `aa46d21540109ce9387822802b18d96d493643663f735d8eea0bd641cd063d90`；BIT/HWH仍为`bffaa835...`/`64ff7724...`。
- 上板事实仍引用两轮既有原始证据；本次发布阶段未重新执行SSH、PL下载或板端服务操作。

## 最新验证：动作上位机正确入口恢复PASS

- 运行证据：[viewer run](../../4_metrics/logs/2026-09-13_175441_976385_gesture_viewer_run01/)；ACTION_INITIAL_CLEAR seq9、prior done_seq8、ACTION_LINK_READY，后续动作ACK连续至seq16，关闭CLEAR seq17。
- 结果：85完整视频帧、lost_frames=0、error=null、action_error=null。
- 人工确认：[physical_confirmation.json](../../4_metrics/logs/2026-09-13_175441_976385_gesture_viewer_run01/physical_confirmation.json)，标记`ACTION_VIEWER_INTERNAL_LAUNCH_RECOVERY_PASS`。
- 结论：无LED根因是display-only启动入口；从v1.4内部启动动作识别即可恢复，无需重新加载PL。

## 最新验证：上位机重开无LED根因确认

- 证据：[reopen diagnosis](../../4_metrics/logs/2026-09-13_action_viewer_reopen_diagnosis_run01/REPORT.md)。
- 最新viewer run `2026-09-13_175035_407501_gesture_viewer_run01`记录584推理帧、590完整帧、lost_frames=0、error=null，说明视频/推理正常。
- `protocol=null`且events只有START，无任何ACTION链路事件，确认该实例为display-only启动。
- 启动器源码明确：直接双击EXE仅显示；`Start_Action_Verification.ps1`或v1.4 GUI“打开动作识别”才传入`--action-control`。
- 状态：`DISPLAY_ONLY_REOPEN_CAUSE_CONFIRMED`；未执行板端命令，当前PL/AXI健康未被本次display-only实例否定。

## 最新验证：用户确认断电后的v1.4第二次复现PASS

- 第二次重加载日志：[GUI run01](../../4_metrics/logs/2026-09-13_174815_607100_pl_reloader_gui_run01/)；PID596原服务基线、验签、STOP_SAFE、PL operating、10秒等待、VDMA转换`[1,1]`、全部READY与GUI PASS齐全。
- 第二次动作日志：[viewer run01](../../4_metrics/logs/2026-09-13_174929_021251_gesture_viewer_run01/)；75推理帧、80完整帧、lost_frames=0、error/action_error均null；五项启用动作均完成三帧判定和ACK闭环。
- 断电/正确性人工记录：[physical_confirmation.json](../../4_metrics/logs/2026-09-13_174929_021251_gesture_viewer_run01/physical_confirmation.json)。v1.4未采boot ID，故断电属于`USER_CONFIRMED`而非自动证据。
- 汇总：[run02报告](../../4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run02/REPORT.md)，标记`V14_POWER_CYCLE_REPRODUCTION_PASS_RUN02`。
- 累计边界：v1.4已有两次成功A→C加载，第二次经用户确认发生在真实断电重启后；尚未达到10/10冷启动或20/20热重载可靠性验收。

## 最新验证：v1.4视频、动作链路与五项LED单次板测PASS

- 重加载原始日志：[GUI run01](../../4_metrics/logs/2026-09-13_173347_248500_pl_reloader_gui_run01/)；原服务安全停止、PL operating、10秒等待、VDMA转换`[1,1]`、VIDEO/ACTION/OVERLAY READY及GUI PASS齐全，无FIRST_FRAME_TIMEOUT。
- 手势原始日志：[viewer run01](../../4_metrics/logs/2026-09-13_173608_873155_gesture_viewer_run01/)；272推理帧、278完整帧、lost_frames=0、action_error=null。Stop/Up/Down/Thumbs up/Thumbs Down分别以动作4/7/1/6/5完成三帧判定和seq/done_seq闭环，关闭前CLEAR完成。
- 人工物理证据：[physical_confirmation.json](../../4_metrics/logs/2026-09-13_173608_873155_gesture_viewer_run01/physical_confirmation.json)；用户确认全部手势对应LED成功。
- 汇总：[v1.4板测验收](../../4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run01/REPORT.md)，标记`V14_SINGLE_HOT_RELOAD_VIDEO_ACTION_LED_PASS`。
- 边界：这是单次A→C功能PASS，不是20/20热重载可靠性PASS；10秒为本次成功配置，不是已证明的最小充分时间。成功后的原视频恢复未请求、未验证。

## 最新验证：PL Reloader v1.4离线包PASS，上板未执行

- 代码回归：[run02](../../4_metrics/logs/2026-09-13_pl_reloader_v14_code_run02/)；19项测试全过，`ResourceWarning`提升为错误后仍PASS，三文件语法标记`PL_RELOADER_V14_SYNTAX_PASS`。
- 构建证据：[build_run01](../../4_metrics/logs/2026-09-13_pl_reloader_v14_build_run01/)；全新发布目录`8_tools/EES331_PL_Reloader_v1.4`。
- 整包复核：[package_verify_run01](../../4_metrics/logs/2026-09-13_pl_reloader_v14_package_verify_run01/REPORT.md)；标记`PL_RELOADER_V14_PACKAGE_PASS`，1006项manifest零哈希失败，自检版本1.4/退出0。
- 打包载荷确认10秒传感器定时等待、30秒首帧窗口；GUI实时输出、控制器journal增量转发均有源码测试。
- BIT SHA256仍为`bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`，HWH SHA256仍为`64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0`。
- 边界：仅`OFFLINE_PACKAGE_PASS`，不是`BOARD_VIDEO_PASS`或`HOT_RELOAD_PASS`。未连接板卡、未停服务、未下载PL、未访问AXI、未改冻结`2_fpga`。

## 动作识别复现完整方案审计

方案证据：[REPORT.md](../../4_metrics/logs/2026-09-13_action_reproducibility_solution_plan_run01/REPORT.md)。已确认用于方案的事实：同一动作BIT `bffaa835...e16d` 曾连续859.5秒/4296帧完成1028条AXI动作及五项真实模型LED验证，也以相同`seen=[false,false]`和VDMA CR/SR多次首帧失败；当前代码在`overlay.download()`后仅固定等待1秒并记录`SENSOR_SETTLE_COMPLETE`，没有真实SCCB/cfg_done/PCLK/VSYNC证据。由此将“AXI功能正确”和“热重载启动可靠性”分开，根因仍标记`UNCONFIRMED`。

本轮只完成方案：路线A为独立动作版冷启动主线，路线B为A→C热重载诊断；定义G0–G6门、V0–V4纯视频矩阵、E01–E10错误分类、恢复门和冷启动10次/热重载20循环最终验收。没有运行命令触碰板卡，没有修改冻结工程、RTL、BIT/HWH、SD或服务，状态为`PLAN_ONLY / BOARD_NOT_RUN`。

## v1.3 首次真实加载失败与自动恢复

本次GUI日志为 `4_metrics/logs/2026-09-13_170635_544500_pl_reloader_gui_run01`。载荷/HWH合同、MMIO编译、原服务安全停止和动作BIT下载通过；BIT SHA-256 `bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`。动作运行在 `SENSOR_SETTLE_COMPLETE seconds=1.0`、`VDMA_RESET_OK`、`BUFFER_ALLOCATED` 后触发 `FIRST_FRAME_TIMEOUT`：`seen=[false,false]`、MM2S/S2MM SR=`0x11000/0x10000`、CR=`0x1008b/0x180cb`，随后 `FAIL / VDMA_HALTED / BUFFER_FREED`。未到达 `ACTION_SERVICE_READY` 或 `ACTION_OVERLAY_READY`，动作端口、AXI、UART和LED均未运行。

控制器自动恢复原服务，PID1284、active/running，用户独立确认HDMI正常，状态为 `PL_DOWNLOAD_PASS / ACTION_VIDEO_FIRST_FRAME_FAIL / ACTION_LINK_AXI_LED_NOT_RUN / ORIGINAL_RESTORE_PASS / PHYSICAL_HDMI_USER_CONFIRMED_PASS / ROOT_CAUSE_UNCONFIRMED`。只读板端证据及历史同签名对照见[审计报告](../../4_metrics/logs/2026-09-13_pl_reloader_v13_board_failure_audit_run01/REPORT.md)、[原始SSH输出](../../4_metrics/logs/2026-09-13_pl_reloader_v13_board_failure_audit_run01/board_failure_readonly.txt)和[人工确认](../../4_metrics/logs/2026-09-13_pl_reloader_v13_board_failure_audit_run01/physical_confirmation.json)。

用户首张界面截图的 MinerU 证据为[解析目录](../../4_metrics/logs/2026-09-13_pl_reloader_v13_stall_mineru_run01/)：`MINERU_PARSE_PASS`，输入SHA-256 `400517BA296436D28F9DCA0C83081CA98A7251F115C06A5A9B7EECBE30A12DC0`，Markdown/content JSON完整，`Fallback=false`；`ChineseQuality=review(short_text)`，语义结论以用户提供的完整文本、原始GUI日志和板端文件为主。

## PL 重加载工具 v1.3 离线验收

用户确认板卡已断电，本轮仅离线修改主机端工具。v1.3 默认填充密码 `xilinx`，操作后恢复该默认值；密码继续不进入日志、配置或 SSH/SCP 命令行。动作进程检测使用不自匹配的 bracket pattern 并解析真实 PID/命令行，旧截图中的 `bash -c pgrep ...` 自匹配回归已覆盖。真实动作进程存在时状态为 `SKIPPED`，不再生成 PASS/加载完成；只有控制器返回 `ACTION_OVERLAY_READY` 时才宣告加载完成并自动启动识别。

源码证据：[16项测试](../../4_metrics/logs/2026-09-13_pl_reloader_v13_code_run01/tests.txt)，结果全部通过。构建证据：[v1.3构建](../../4_metrics/logs/2026-09-13_pl_reloader_v13_build_run01/)。整包证据：[交付报告](../../4_metrics/logs/2026-09-13_pl_reloader_v13_package_verify_run01/REPORT.md)与[result.json](../../4_metrics/logs/2026-09-13_pl_reloader_v13_package_verify_run01/result.json)。标记 `PL_RELOADER_V13_PACKAGE_PASS`；1006 项清单哈希失败 0，打包自检退出码 0/版本 1.3；主 EXE SHA-256 `0F627ED5BD45BBD41CB31C5E71CA4BD40952DC83A70422AD6C3682F4A1C842A7`。状态边界：`OFFLINE_PACKAGE_PASS / BOARD_NOT_RUN / ACTION_LINK_NOT_RUN / AXI_LED_NOT_RUN`。

## v1.2 实机假阳性与 LED 无输出诊断

16:51:37 状态检查显示原 `ees331-camera` 服务 active/running，实际进程为 PID 597 的 `camera.py`。16:51:58 的动作进程查询只返回 `bash -c pgrep -af camera_action_v1.py || true`，但 GUI 用简单字符串包含判断而误报动作进程存在，结果文件为 `PASS / ACTION_ALREADY_RUNNING_NO_RELOAD`；本次没有调用板端 `load`，也没有取得 `ACTION_OVERLAY_READY`。16:52:04 启动的 PC 动作识别程序约 1 秒后记录 `ACTION_LINK_FAILED / TimeoutError('timed out')`；它仍完成 757 个以上推理帧并识别到多个动作，但发布器未 READY，`effective_action=UNKNOWN`、`protocol=null`，因此不会产生 AXI/LED 输出。状态：`PC_VIDEO_INFERENCE_RUNNING / PL_RELOAD_THIS_OPERATION_NOT_EXECUTED / ACTION_LINK_FAILED / AXI_LED_OUTPUT_NOT_OCCURRED`。完整证据、源码定位及 MinerU 结果见[诊断报告](../../4_metrics/logs/2026-09-13_pl_led_diagnosis_mineru_run01/REPORT.md)。附件解析为 `MINERU_PARSE_PASS`，SHA-256 `2C2C7BD3071328EB1287A66BB0155EAA10EB2528049ED63A22335C710B3D4DE4`，Markdown 与内容 JSON 完整，`Fallback=false`；`ChineseQuality=review(short_text)`，结论以原始应用日志和源码为主。

## PL重加载应用v1.2离线验收与v1.1现场失败

用户现场v1.1日志先记录一次空密码输入，随后在已输入凭据时两次停在PuTTY连接层并各30秒超时；该证据不能判定密码错误。v1.2已替换为Windows OpenSSH并加入TCP 22预检、AskPass临时环境传密和合并SCP上传。状态：`12_OFFLINE_TESTS_PASS / PL_RELOADER_V12_PACKAGE_PASS / BOARD_NOT_EXECUTED`。主EXE SHA-256为`1681f96e6c77ed4830ecfc06f95e5021d5dc71c74d8501fd2ffc812e27d08e48`；1006个包清单条目复算零失败。详见[v1.2报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run03/REPORT.md)、[12项测试](../../4_metrics/logs/2026-09-13_pl_reloader_code_run05/tests.txt)、[包结果](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run03/result.json)和[v1.1现场日志](../../4_metrics/logs/2026-09-13_163033_840000_pl_reloader_gui_run01/application.log)。

隔离执行环境的端口探针返回`PL_RELOADER_NETWORK_UNREACHABLE`/Windows 10013；由于沙箱可能阻止网络，这不是开发板当前物理状态证据。未执行SSH登录、停服务、BIT下载、AXI/UART、动态视频或物理LED/HDMI检查，故实机状态仍为`NOT_RUN`。`code_run04`保留旧虚拟环境入口失效的前置失败；`code_run05`改用可用解释器验证代码，`build_run05`从本地归档wheel离线重建PyInstaller环境。

## PL重加载应用v1.1离线验收

状态：`PL_RELOADER_SOURCE_PASS / 8_OFFLINE_TESTS_PASS / PL_RELOADER_FINAL_PACKAGE_PASS / BOARD_NOT_EXECUTED`。最终EXE SHA-256为`40dad6dc22caa70d1e47ff226304ff53a829c978075503597caf8667fd76eae4`；窗口型EXE隐藏self-test返回`PL_RELOADER_SELF_TEST_PASS`，1004项包清单复算零失败，固定BIT/HWH哈希匹配。8项测试覆盖载荷验证、篡改拒绝、恢复幂等和DMA释放硬门。证据见[最终交付报告](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run02/REPORT.md)、[代码测试](../../4_metrics/logs/2026-09-13_pl_reloader_code_run03/tests.txt)及[result.json](../../4_metrics/logs/2026-09-13_pl_reloader_package_verify_run02/result.json)。

本轮未连接板卡、未停止当前`ees331-camera`、未加载C、未启动模型；不能把离线应用PASS写成板端功能PASS。早期build_run01/run02为打包自检失败并完整保留；最终推荐v1.1，不推荐使用中间v1.0。

## 用户现场：原Overlay A所有者确认

用户回传 `systemctl show` 与 `pgrep`：`ees331-camera` 当前运行，实际进程为原 `/home/xilinx/ees331_camera/.../camera.py --peer 192.168.240.2 --port 5000 --fps 5`。这确认当前仍是冷启动原视频服务占有VDMA，尚未进入动作Overlay C；服务/进程门通过。关键文件哈希输出未包含在本次回传中，仍沿用前一步待核对项。进入停止服务前还需用户确认当前动态HDMI/UDP物理基线正常；停止将短暂中断视频。

## 用户现场：冷启动后目录预检

用户截图显示板端 `/home/xilinx/action_e2e_20260913_run01` 存在，包含6639字节的新版 `camera_action_v1.py`、配对BIT/HWH、2469字节manifest及已编译的7012字节 `libmmio_ordered.so`。当前 `cd` 失败仅因随后把 `ACTION_APP_DIR` 覆盖成不存在的 `/home/xilinx/action_v1_20260913`；没有证据表明文件丢失，也尚未据此宣告当前服务所有权、Overlay状态或复现PASS。下一步先恢复正确变量并只读检查哈希、systemd和实际进程，不立即加载PL。

## 当前阶段：手工复现方案离线审查

状态：`PLAN_ONLY_READY / BOARD_NOT_POWERED / NO_BOARD_OPERATION / STAGE2_APP_NOT_STARTED`。

本轮只读核对 `9_pynq/overlays/action_v1_20260913/release_manifest.json`：13个条目均存在且 SHA-256 匹配。关键 BIT 为 `bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`，HWH为 `64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0`。既有实机证据支持 A 正常基线后单次切 C；同时保留 C 成功后跨进程再次加载 C 的 `FIRST_FRAME_TIMEOUT`，所以方案禁止 C->C 盲重试。

本轮没有连接板卡、停止服务、下载位流、启动模型、修改 SD/RTL/BD或创建第二阶段应用。用户复现 PASS 需至少看到 `ACTION_SERVICE_READY`、动态视频正常、一个真实模型动作得到AXI确认且物理LED映射正确；推荐五动作全部复核。完整审查和命令见[run01报告](../../4_metrics/logs/2026-09-13_action_v1_manual_repro_plan_run01/REPORT.md)。

## 最终收尾：用户明确暂缓热重载，第一版功能目标完成

用户已结束手工测试，并明确要求重加载故障暂不解决，待其自行重加载再复现时处理。五项真实模型→AXI寄存器→PL UART/LED输出已验证，交付提交612d7b3已推送个人分支；见[完成审计](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/completion_audit.md)。热重载仍是已知未解决项，不再自动诊断或加载。未执行此前口头计划的最后恢复操作，不声称当前原视频已恢复；收尾不操作板卡。下方“继续解决热重载/目标活动/手工测试中”等为历史状态，以本段为准。

## 热重载离线证据复核

已重读实际交付Camera与三组事件，形成[根因假设表](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/reload_hypothesis_review.md)。三个C运行CMA均0x10100000；失败在ACTION_ATTACH前；下载到名义1秒等待结束实际为成功1.183/1.190秒、失败1.046秒。仅支持时序/前置状态需要控制，不能证明根因。未连接板卡、未改设计、未加延时。下一硬件窗口需用户明确结束当前手工测试。

## 最新：功能检查点已推送个人分支

提交612d7b3d0fd3e427f47498885fc9debab2b429e6已推送codex/full/pipidandan-superman，ls-remote核对一致；未合并main。70项明确交付文件，13项清单哈希、两轮真实模型/串口/三帧核对及25项离线测试通过。见[发布记录](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/publication_result.md)和delivery_audit_utf8.log。热重载故障仍未解决，目标未标完成；本轮未停止板卡服务/GUI。

## 交付离线预检补充

67项明确文件已复制到个人分支独立worktree并逐文件核对哈希；尚未暂存/提交/推送。该工作树隔离测试6项、动作测试14项、GUI测试5项通过。修正测试引用交付包，以及Windows保留设备名com4.bin的发布副本名称；原始证据不改。见[预检记录](../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/delivery_preflight.md)。本次未操作板卡或关闭上位机。

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

离线8项测试通过，5份归档文件哈希匹配、Python编译和ACTION_HARDWARE_CONTRACT_PASS；路径审计15项通过。证据含offline_tests.log、offline_result.json、delivery/manifest.json与path_audit.txt。只证明诊断准备就绪，未证明根因或实际双加载行为。
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

## 最新证据：系统审计完成，根因尚未锁定

[报告与复现入口](../../4_metrics/logs/2026-09-13_action_v1_regression_review_run01/REPORT.md)
及[全量静态审计JSON](../../4_metrics/logs/2026-09-13_action_v1_regression_review_run01/system_audit.json)。
- 三份HWH交叉检查：同主地址空间重叠0；实际VDMA=0x43000000/64KiB、ACTL=0x43C00000/4KiB。
- B→C共同IP参数/连接差异0，路由后共同IO属性差异0，新增输出无封装引脚重复；不等于物理时序等价。
- 8个Camera方法AST相同，包括5秒首帧门；动作服务在camera.start之后启动。
- 原视频归档PL_LOADED→VIDEO_STARTED为1.257552秒，旧AXI+BLE为1.259921秒；动作版6.019878秒后首帧门失败。
- MM2S状态0x11000含帧中断，S2MM=0x10000；修正此前“没任何真实帧/显示完全不工作”的过强推断：证据直接证明槽位未轮转。
- 确认动作异常传播会HALT视频，以及单独身份读后视频程序再次下载；均不等于已证明本次首帧故障原因。
- 本轮SSH读取journal失败，本机Ethernet Disconnected；上一轮恢复PASS保留，但不宣称当前在线状态已验证。
审计首次沙箱解释器启动失败记录保留，后续仅离线审计成功。未更改板卡、生产源码或skill。

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

## 当前：ACTION_V1_OFFLINE_AUDIT_PASS，板测仍未进行

第一版（模型稳定动作→PS AXI寄存器→PL LED/COM4 TX）已实现并完成离线验收；
不代表板上LED、实际串口字节、HDMI/视频共存或真实模型识别已经验收。

| 阶段 | 当前证据 |
|---|---|
| 动作RTL仿真 | [rtl_run01](../../4_metrics/logs/2026-09-13_action_v1_rtl_run01/process_status.json)：PASS，1002命令/254494检查 |
| 真实波特率/官方reset | [reset_baud_run01](../../4_metrics/logs/2026-09-13_action_v1_reset_baud_run01/process_status.json)：PASS |
| 独立工程构建 | [independent_build_run01](../../4_metrics/logs/2026-09-13_action_v1_independent_build_run01/process_status.json)：PASS，11.112/0.051ns |
| 主BD验证 | [main_bd_run03](../../4_metrics/logs/2026-09-13_action_v1_main_bd_run03/process_status.json)：PASS |
| 主完整构建 | [main_build_run03/REPORT](../../4_metrics/logs/2026-09-13_action_v1_main_build_run03/REPORT.md)：PASS，setup10.402/hold0.020ns，黑盒0/DRC错误0/Critical0 |
| 补充时序检查 | [timing_audit_run01](../../4_metrics/logs/2026-09-13_action_v1_timing_audit_run01/bus_skew.rpt)：8项总线偏斜全部MET，最小余量18.902ns；保留clocks.rpt |
| PYNQ/PC回归 | [python_run05/tests](../../4_metrics/logs/2026-09-13_action_v1_python_run05/tests.txt)：14项PASS，含稳定门、真实UDP、去重、超时和失败可见性 |
| 发布HWH负例 | [hwh_tests_run02](../../4_metrics/logs/2026-09-13_action_v1_hwh_tests_run02/result.json)：7项拒绝通过 |
| EXE离线测试 | [viewer_smoke_run03](../../4_metrics/logs/2026-09-13_action_v1_viewer_smoke_run03/self_test.json)：模型/Tk/动作协议PASS；构建run04 |
| 配对发布包 | [release_manifest](../../2_fpga/0_diaplay_test/release/action_v1_uart_run01/release_manifest.json)：ACTION_V1_RELEASE_PASS，board_validated=false |
| 最终审计 | [final_audit_run01](../../4_metrics/logs/2026-09-13_action_v1_final_audit_run01/result.json)：35个Python语法、测试源码/发布哈希、3999项上位机文件；skill路径15项PASS |
| 板测前检查 | [board_run01/REPORT](../../4_metrics/logs/2026-09-13_action_v1_board_run01/REPORT.md)：BLOCKED_PRECHECK，Ethernet断开/0bps，SSH无banner |

失败保留：[main_build_run01](../../4_metrics/logs/2026-09-13_action_v1_main_build_run01/process_status.json)、
[main_build_run02](../../4_metrics/logs/2026-09-13_action_v1_main_build_run02/process_status.json)、
[python_run04](../../4_metrics/logs/2026-09-13_action_v1_python_run04/tests.txt)。
详细根因见当前方案状态文档；沙箱启动失败及早期BD失败同样保留，没有覆盖原记录。

主资源LUT5093/FF7850/BRAM20.5/DSP9；无无时钟寄存器/未约束内部端点，
但原视频接口延迟与CDC/非CCIO限制仍在，不夸大为完整物理时序证明。
上位机交付：8_tools/EES331_Action_Viewer_v1.0，EXE SHA256
92790d9d232fa66604cab34c8560cce5439eba3f6a78a673aee44cc972b9e1aa。

没有向板端上传、停服务、加载新位流或发AXI命令；当前等待用户连接确认。
尚未Git提交/推送，不操作第二版蓝牙，不关机。
后续实机通过条件为1000条命令+逐字节COM4+序号/计数+LED人工确认+
真实模型稳定动作+动态HDMI/UDP共存与原服务恢复。
[完整实现与操作说明](../../2_fpga/0_diaplay_test/doc/action_v1_status.md)。

按仿真技能清理本轮三个自动生成WDB，源/自检脚本/全量控制台保留可重现；
[清理清单](../../4_metrics/logs/2026-09-13_action_v1_final_audit_run01/removed_generated_waves.json)。

以下是同日历史证据，不代表当前动作v1已获得板测PASS。

## 最新：用户批准第一版执行

用户确认 Left/Right 暂不自动下发，采用三个不同新视频帧连续同类且各置信度 >=0.75，
稳定后只发送一次；无效结果打断连续计数，连续一秒无有效结果发送一次 CLEAR。
第一版执行已获授权，按独立仿真、BD 构建、板测顺序推进并报告；第二版尚不执行。
当前源与工程快照保存在
[source_run01](../../4_metrics/logs/2026-09-13_action_v1_source_run01/source_hashes.json)。
新动作 RTL 为此前草稿，正进行补齐和验证，尚无本版仿真、构建或板测 PASS。

## 最新：方案完成，执行证据仍为 NOT_STARTED

[AXI 动作 UART/BLE 两版方案](../../2_fpga/0_diaplay_test/doc/axi_action_uart_ble_two_version_plan.md)
已保存，状态 `REVIEW_REQUIRED`。本次只确认了现有工程的静态事实：COM4 A16/A17 与
MLT-BT05 Y13/AA13 是独立 UART 管脚；现有蓝牙主机接口为 BLE GATT FFE1 而非虚拟
COM；旧透明桥会占用 BT_RX，第二版必须替换而不能并联。没有据此宣告新功能通过。

用户提出审核门前生成的 `action_uart_tx.v`、`action_command_executor.v`、
`axi_action_reg_bank.v` 和 `action_control_abi.md` 尚未仿真、未进 BD/工程、未构建，
统一为 `DRAFT_UNREVIEWED`。新动作版本仍为 SIM/BUILD/BOARD NOT_STARTED。

## 最新：新动作控制版本尚未验收

用户已纠正控制方向为 `PS --AXI-Lite--> PL --LED + UART TX--> COM4`。此前完成的
`MAIN_AXI_BLE_AUTOMATED_BOARD_PASS` 只证明视频、通用 AXI 寄存器和透明蓝牙桥可以
共存，是保留的历史证据；它没有实现“模型结果经 AXI 映射后由 PL 组帧发送并点灯”，
不能作为新需求的 PASS。当前新版本状态为 DESIGN_FIXED / RTL_NOT_STARTED /
SIM_NOT_STARTED / BUILD_NOT_STARTED / BOARD_NOT_STARTED。独立 AXI 寄存器阶段仍为
PASS，BRAM 仍为 NOT_STARTED。

## 最新：主工程自动化共存板测 PASS，物理 HDMI 待确认

独立寄存器阶段因用户确认恢复后的 HDMI 正常而闭环为 PASS。主视频工程当前离线证据：

- `MAIN_AXI_WRAPPER_SIM_PASS`：50 MHz 包装层读写、WSTRB、命令、序号和 ACK；
- `MAIN_BD_VALIDATION_PASS`：新 Vivado 进程检查地址、时钟、蓝牙端口和复位，
  Critical Warning/Error 为 0；
- `MAIN_AXI_BLE_BUILD_PASS`：setup 5.978 ns、hold 0.024 ns、黑盒 0、DRC Error 0；
- `MAIN_HWH_CONTRACT_TEST_PASS`：新 HWH 通过、旧视频 HWH 被拒绝；
- `MAIN_AXI_BLE_RELEASE_AUDIT_PASS`：BIT/HWH 哈希、camera.py 固定哈希和 HWH 合同一致。

首次 SSH 预检因 PC 有线适配器 `Disconnected / 0 bps` 失败；用户恢复网线后同一
run01 完成：板端集成相机 130.053 秒/650 帧；PC 集成窗口 400 帧、丢帧 0；AXI
1000/1000；蓝牙 11/11 轮、双向各 166 字节；原服务恢复后 PC 再收 100 帧、丢帧
0。VDMA 最终状态无错并正常 halted，自动审计标记
`MAIN_AXI_BLE_AUTOMATED_BOARD_PASS`。仍需用户确认集成窗口及恢复后的 HDMI 动态
画面，故尚不标记完整共存 PASS、尚不 Git 推送。BRAM 未实现。用户已撤销关机授权，
当前无关机任务，后续保持计算机运行。

证据索引：
[构建](../../4_metrics/logs/2026-09-13_main_axi_ble_build_run08/REPORT.md)、
[BD](../../4_metrics/logs/2026-09-13_main_axi_ble_integration_run11/process_status.json)、
[仿真](../../4_metrics/logs/2026-09-13_main_axi_wrapper_sim_run05/process_status.json)、
[HWH](../../4_metrics/logs/2026-09-13_main_hwh_contract_run01/result.json)、
[PYNQ](../../4_metrics/logs/2026-09-13_main_pynq_audit_run02/result.json)、
[主工程板测](../../4_metrics/logs/2026-09-13_main_axi_ble_board_run01/REPORT.md)。

## 最新：复位缺陷已修复，独立寄存器板测PASS

当前停点：1000轮/3次重载及UDP恢复均通过；用户已确认恢复后的HDMI正常，独立寄存器阶段完整验收PASS。人工确认保存在[physical_confirmation.json](../../4_metrics/logs/2026-09-13_axilt_reg_board_run02/physical_confirmation.json)。通用skill已创建并在6_skill、.codex/skills和用户全局目录同步，通过3份quick_validate及哈希一致性；[skill证据](../../4_metrics/logs/2026-09-13_skill_validation_run01/REPORT.md)。主工程集成现进入实施阶段；尚未Git提交推送、未关机。

下一步：HDMI确认后保存主工程可回退源/BD/约束/位流基线，集成寄存器与已验证蓝牙桥的明确共存范围，完成主工程构建及实机验证；更新并选择性发布个人分支，核验远端；全部通过保存且无未保存工作时按用户授权正常延时关机。不能因独立PASS跳过集成验收。原工作区dirty，个人worktree保留4个既有未跟踪文件，fetch后个人分支与远端0/0。

用户重新上电后取回run01残片。仅加载诊断成功；定位aux_reset_in低有效却接0，修正BD为接1。官方IP仿真复现旧故障且修复后CSR读取通过，重新构建100MHz时序/DRC通过。run02完成1000轮、3次重载，UDP恢复60帧通过，用户确认HDMI正常。15项Python单测通过；旧失败与旧发布包保留。

[实机完整证据](../../4_metrics/logs/2026-09-13_axilt_reg_board_run02/REPORT.md)。后续用户新增授权：独立验收后创建通用zynq-pynq-overlay-workflow skill，再集成主FPGA工程、综合/实现/上板共存验证、更新并推送个人分支；全部完成保存且无未保存工作时才可正常延时关机。用户已确认主工程为2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr。未授权Git main合并，BRAM未实现，不提前关机。

## 历史：run01失联，暂停并等待恢复现场

已完成测试前PYNQ/视频/产物检查及ARM库编译，但正式板测期间SSH失联，未取得板端结果，REG_BOARD_UNCONFIRMED_CONNECTION_LOST，视频恢复待完成。用户确认没有拔插/复位/断电，cfg_done灯灭、HDMI黑屏；这与独立Overlay无视频模块相符，不代表寄存器通过。COM6探测无返回。下一步由用户复位/重新上电恢复原SD，然后先取回run01/events.jsonl及启动日志，不自动重试命令、不进入BRAM。

[完整现场、证据限制与恢复计划](../../4_metrics/logs/2026-09-13_axilt_reg_board_run01/REPORT.md)。本机远程控制进程已因超时退出，板端执行状态未知。

## 先前：用户上电并授权寄存器板测（进行中）

用户已明确上电并授权本轮验证，取代下方此前只说明/不操作约束。使用独立板端目录 /home/xilinx/axilt_test_20260913_run01，不覆盖原视频目录。已登录PYNQ3.0.1、核对原视频哈希和未绑定内核VDMA；用户确认HDMI动态正常，PC 12秒收到61完整帧、CRC/丢帧/坏头0。待编译ARM访问层、1000轮/3次重载及视频恢复。禁止合并主工程或自动进入BRAM。

证据：../../4_metrics/logs/2026-09-13_axilt_reg_board_run01/ 。板端日期与PC不一致，采用boot_id及monotonic区分当前启动和历史日志；首个journal未加-b含历史记录，当前依据boot_video.log。

本轮仅流程核对，非板测PASS。现有release四文件存在，脚本及前置条件已读；未重跑仿真/构建或哈希审计。
[核对记录与技能路径审计输出](../../4_metrics/logs/2026-09-13_axilt_board_guide_run01/REPORT.md)。
未来命令（未执行）：sudo /usr/local/share/pynq-venv/bin/python board_test.py --bit ./AXI_LITE_test.bit --manifest ./artifact_manifest.json --run-dir ./evidence/register_run01；Python路径先实机确认。
通过条件：AXILT_REG_BOARD_TEST_PASS、completed>=1000、reloads=3、无失败，并另验HDMI/UDP恢复。重复提交板测为软件拒绝，协议错误注入归仿真。
当前REG_BOARD_PENDING、BRAM_NOT_STARTED。板卡断电是用户已知状态，没有新增连接检查。

## EES-331 PYNQ SD root 密码提示只读核对

- 目标 IMG SHA-256 为 `8D22BCDE0268678050BCC1429BEE5ECADB0020E5CE3F5BA4DF7045066DEAFCCA`，与发布哈希一致。
- 构建证据显示应用已写入 `/home/xilinx/ees331_camera`，且 `ees331-camera.service` 启用链接存在。
- 服务未设置 `User=`，系统级 systemd 服务按 root 权限自动运行，无交互密码步骤。
- `install.sh` 的 root 检查只属于手工安装路径；刷完整 IMG 后无需再次执行。
- 既有实机连接脚本以 `xilinx/xilinx` 登录并将同一密码交给 sudo；PYNQ 官方 FAQ 与此一致。
- 建议：SSH 使用 `xilinx@192.168.240.10`；若提示 `[sudo] password for xilinx:`，输入 `xilinx`；若是 `root@... password:`，退出后改用 `xilinx` 登录。
- 本轮未获取队友终端原文、未连接其板卡，故现场状态仍为 `BOARD_NOT_OBSERVED`。
- 证据：[SD root 密码提示审计](../../4_metrics/logs/2026-09-13_sd_root_password_audit_run01/REPORT.md)。结果标记：`SD_ROOT_PASSWORD_GUIDANCE_PASS`。

## EES-331 PYNQ SD 整盘镜像验证

- 当前源设备：`Disk 1` / `Generic STORAGE DEVICE` / USB / MBR / `15,634,268,160` 字节 / 非系统盘、非启动盘。
- 分区 1：偏移 4096、长度 136,314,880、类型 FAT32 LBA、卷标 `PYNQ`、盘符 `G:`；分区 2：偏移 137,363,456、长度 15,496,904,704、类型 Linux `0x83`。
- 只读 FAT CHKDSK：`Windows has scanned the file system and found no problems.`；MBR 签名 `0xAA55`；ext 魔数 `0xEF53`；ext 状态 `1`（clean）。容量显示 14.56 GiB 不构成损坏证据。
- 当前目标：桌面 `ees331_pynq_sd_20260913_full.img`，预期精确长度 `15,634,268,160` 字节。
- PASS 条件：完整读取源盘；输出长度等于源盘；流式与回读 SHA-256 完全一致；正式 IMG 和 `.sha256` 均存在；生成复现说明和结果标记 `SD_RAW_IMAGE_PASS`。
- FAIL 条件：设备指纹改变、短读/读错、空间不足、长度不符或哈希不一致；失败时不得把 `.partial` 当成可烧录镜像。
- 原始证据：[整盘成像报告](../../4_metrics/logs/2026-09-13_sd_card_raw_image_run01/REPORT.md)。
- 实际结果：完整复制 `15,634,268,160` 字节；流式与落盘回读 SHA-256 均为 `488939D8CC6B3A62F7F7CF38F8BDC71C79ECED587DF80D623B453EF26178E7CA`；正式 IMG、`.sha256` 与队友复现说明均已放在桌面。
- 独立镜像复核：大小、SHA-256、MBR `0xAA55`、分区类型 `0x0C/0x83`、ext 魔数 `0xEF53`、ext 状态 `1` 全部通过。结果标记：`SD_RAW_IMAGE_PASS` / `IMAGE_VERIFICATION_PASS`。
- 证据边界：未对队友目标卡执行烧录或冷启动；其 SSH、服务、HDMI、UDP 与物理功能仍为 `TEAMMATE_BOARD_NOT_VALIDATED`。

## SD 卡安全弹出

- 成像与回读校验进程已结束，桌面不存在 `.img.partial`；重新核对目标为 `Disk 1` / USB / `15,634,268,160` 字节 / `G: PYNQ`，且非系统盘、非启动盘。
- Windows Eject 请求完成后，`G:` 在门限内消失，`volume_still_mounted=false`。
- 结果标记：`DISK_SAFE_EJECT_PASS`。用户已被明确告知可以物理拔出。
- 证据：[安全弹出报告](../../4_metrics/logs/2026-09-13_sd_card_safe_eject_run01/REPORT.md)。

## 队友 SD 视频链路复现包只读核对

- 交付选择：桌面 `ees331_pynq_sd_20260913_full.img`，精确大小 `15,634,268,160` 字节，SHA-256 `488939D8CC6B3A62F7F7CF38F8BDC71C79ECED587DF80D623B453EF26178E7CA`。
- 同名 `.sha256` 与 `README_队友复现.txt` 当前存在；内容与当天成像证据一致。
- 排除项：`EES331SDBootBuilder_v0.2.2.exe` 是生成工具；基础 PYNQ IMG 不含相机开机业务；启动分区 IMG/ZIP 不是整卡部署包。
- 现场条件：板卡 `192.168.240.10/24`，PC `192.168.240.2/24`，UDP `5000`；目标卡实际容量不得小于 `15,634,268,160` 字节，推荐 32 GB。
- 状态：`TEAMMATE_SD_PACKAGE_SELECTION_PASS / TEAMMATE_BOARD_NOT_VALIDATED`。证据：[核对报告](../../4_metrics/logs/2026-09-13_teammate_sd_package_selection_run01/REPORT.md)。
