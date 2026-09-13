# 第一版真实模型→AXI-Lite→PL输出

## 当前状态

MODEL_AXI_UART_FIVE_ACTIONS_PASS / AXI_1000_COMMANDS_PASS / HOT_RELOAD_FAILURE_REPRODUCED / MANUAL_GUI_REPEAT_IN_PROGRESS。
目标仍活动，不把热重载问题和未完成的人机交接隐藏在成功计数中。
板卡boot ID：027a8e8d-ba81-4cd7-adb9-5650802e304e。

## 实现修改

1. `2_fpga/0_diaplay_test/pynq/camera_action_v1.py`：动作初始化/线程错误不再抛出到视频主循环；结果显式DEGRADED，仍返回非零，不伪装动作通过。结果读取失败同样记录；保留部分初始化Camera对象以安全释放；统一Camera事件到持久日志。
2. `2_fpga/2_axi_lite_test/pynq/action_service.py`：bind失败关闭新socket，防止泄漏。
3. `3_host/model_env/model_action_validation.py`：真实UDP摄像头→固定YOLO→原StableAction/ActionPublisher→PS AXI→PL COM4自动核验。COM4只读取；空白warmup不进入决策；图片为有限正类样本，不声称全面精度。
4. 6项假Camera故障注入与14项动作协议/驱动测试通过；证据isolation_tests.log、action_tests.log。软件异常隔离不等于硬件AXI总线挂死可被Python超时打断。
5. 原有gesture_viewer已预创建模型配置目录，不需要修改；一次补丁因上下文不匹配拒绝，原文件未改。新增验证脚本首轮模型配置目录未预创建导致库回退生成根目录Ultralytics/settings.json，已归档到本run/ultralytics_fallback并修正预创建目录；没有删除用户数据。

BIT bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d；HWH 64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0。
Camera仍8c8b75442d97c99e1db72ff0c8a43ffafbe16cce26715534b09515b0f9d5d0a5；未修改RTL、地址、时钟、首帧门或SD。
`delivery/release_manifest.json`列软件/硬件完整哈希，上传新目录`/home/xilinx/action_e2e_20260913_run01`。
ARM屏障库编译SHA256 753b36efadfb1da6f626bd267b8d97da3d9e1d927a856852fca894e5b5429e23。

## 成功的完整运行证据

原视频PID2590→HALT/FREED→同一C单次加载，1656.951723视频启动，然后1656.986587动作服务READY，地址来自HWH。
整个受控运行859.502748秒，4296帧/4295变化帧、1028条动作完成，状态READY、无动作错误；人工请求继续测试后主动SIGTERM，HALT→FREED→COMPLETE，exit0。见board_runtime/及runtime.log。

### 确定动作回归

known_commands/result.json：1000条命令+最后CLEAR，共1001帧7007字节，COM4逐字节完全一致；每条重复UDP提交均返回DUPLICATE且无额外串口帧。
并行PC65变化帧、零CRC/丢帧；用户先说LED1–6后纠正为LED1–7，cfg_done/HDMI正常，见physical_axi_pressure.json。

### 真实模型而非标签注入

固定权重68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79；YOLO CPU输入640，检测conf=.45，动作门每帧>=.75，连续三个不同新帧；左右不自动下发。

|动作|AXI序号示例|三帧ID|PL串口原始帧|LED|
|---|---:|---|---|---|
|Stop|1003|1765/1766/1767|A5 5A EB 04 DA 0D 0A|4|
|Thumbs up|1005|2001/2002/2003|A5 5A ED 06 AA 0D 0A|6|
|Thumbs Down|1007|2112/2113/2114|A5 5A EF 05 89 0D 0A|5|
|Up|1013|2689/2690/2691|A5 5A F5 07 52 0D 0A|7|
|Down|1015|2887/2888/2889|A5 5A F7 01 6A 0D 0A|1|

real_model：900推理帧，动作4/5/6，10条确认、70串口字节完全一致。
real_model_up_down：600推理帧，动作1/7，8条确认、56字节完全一致；启动前同步丢弃533包单列，同步后CRC/丢帧0。
model_audit_2.json逐项验证每个stable决定前的三个真实预测帧、单类、置信度和新鲜度，并与全部串口字节一致。
collect_board.py还交叉核对这些PC完成序号与板端ACTION_DONE。GUI重复独立统计，不并入COM4核验。
用户初次答“目前都对”；GUI90秒内明确确认Stop/Up/Down对应LED4/7/1。GUI自动关闭打断用户测试属于助手操作问题，已改为无时限窗口。
无时限GUI用户确认Stop/Up/Down/Thumbs up分别LED4/7/1/6；Thumbs Down未亮，LED0常亮。LED0是cfg_done，不是动作灯。
thumb_down_diagnosis.json及1320帧快照：127帧检测到Thumbs Down，但单类且>=0.75最多连续2帧，ACTION5确认记录为空。因此这次没有亮灯的直接原因是决策门未通过，不能归因PL LED5不响应；自动首轮曾满足3帧并完成ACTION5/COM4，两个样本不矛盾。保留人工未通过，不擅自降低阈值。
GUI有449完整帧/443推理帧、6个consumer_skipped（首个模型加载期间），无动作错误。无时限GUI另有1个incomplete_frame计数，不能宣称其全程零包错误；自动两轮接收证据独立为零CRC/丢帧。
后续无时限GUI elapsed286.844秒Thumbs Down三帧通过，fid1800、confidence0.7786506，seq19/action5/done19；elapsed290.656秒失效清灯seq20。用户随后确认“led5亮了”，并再次确认“对的对的，拇指向下对应的led5亮了”。五项动作均完成物理LED核对，见physical_gui_manual.json；保留前一次未达门槛记录，阈值未修改。该次GUI物理确认不另计为新的COM4原始采集。

## 热重载新失败及恢复：必须保留

成功运行结束后，同一C再次加载（跨进程systemd持续模式）发生FIRST_FRAME_TIMEOUT，seen=false/false，MM2SSR11000、S2MMSR10000；在ACTION_ATTACH之前失败。
PL_LOADED2592.399762，BUFFER2593.479504，超时2598.486077。板端安全HALT/FREED/exit1，见board_manual_runtime/和manual_failure_full.log。未自动重试。
恢复原A服务PID5383，PC65变化帧零CRC/丢帧，用户确认cfg_done/HDMI正常，见restored_udp.json、physical_recovery.json。
保持同一C/Camera/包装/systemd，只改变前置状态为正常原A后，再以新unit启动manual_runtime2：PL_LOADED2869.393350，VDMA_STREAM_STARTED2870.867358，ACTION_SERVICE_READY2870.888254，成功。
这个对照支持前置PL/外设状态或启动时序相关假设，但单样本、fsync实际耗时等仍不同，不能声称具体根因已证明或永久修复。不是AXI命令触发该首帧失败，失败发生在动作挂接前；也不能以此排除全部硬件问题。

## 当前在线状态与禁止操作

临时服务`ees331-action-e2e-manual2.service`，PID5783（以实时查询为准），Restart=no、TimeoutStopSec=infinity、SendSIGKILL=no、--seconds 0，无自动结束，不设置开机自启。
PC `gui_manual` 使用gesture_viewer.py --action-control，无--smoke-seconds；由用户完成测试后再关闭。
原ees331-camera已停止但文件/开机配置保持原状。**用户仍在测试：不得自动关闭GUI、停止动作服务、重新加载或恢复原A。**
旧manual服务失败保留，不用reset-failed抹去失败。不能直接重启当前C应用作为“已验证热重载”；后续需解决此已复现边界。

## 待办与交付边界

- 等用户完成GUI中拇指上/下与HDMI确认；保存证据，不设置自动关闭。
- 系统定位新热重载故障，区分功能链路通过与启动可靠性未完成。
- 更新工程状态/操作文档、个人分支交付，不能在脏main工作区直接提交/推送。此前提交请求仍待完整验收后按Git策略执行。
- 第一版蓝牙不接主数据流；模型仍PC，不是PL内部模型推理。没有机械臂安全闭环或通用识别准确率认证。
