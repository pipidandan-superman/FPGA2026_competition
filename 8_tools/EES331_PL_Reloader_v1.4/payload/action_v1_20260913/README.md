# 第一版：真实模型经 AXI-Lite 控制 PL UART/LED

功能链路已通过板测；配套v1.4重加载器已完成两轮A→C成功，其中第二轮由用户确认是在开发板断电、重新上电之后完成。当前证据仍只有2/2，**不是长期稳定或量产部署结论**。
模型在PC推理，PL负责AXI寄存器、动作锁存、LED和UART输出。蓝牙不接入。

## 文件与来源

本目录保存匹配BIT/HWH、部署源码及release_manifest.json；build_artifacts/XSA仅供构建溯源，不放在BIT同目录，避免PYNQ优先解析不兼容元数据。
硬件来自2026-09-13_action_v1_main_build_run03；BIT 4045696字节、SHA256 bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d，HWH SHA256 64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0。
上传二进制的理由：允许用户复现本次实机验证的精确Overlay，不以不同构建替代。全文件大小、哈希与XSA来源见manifest；原始证据在4_metrics/logs/2026-09-13_action_v1_end_to_end_run01。

## 已验证与限制

- 确定命令1000条+清灯，共1001帧7007字节COM4逐字节相同，重复提交不多执行。
- 真实模型两轮1500帧，五种启用动作均有连续三帧、PS/PL序号与实际UART证据，共18条126字节完全相同。
- 用户已在上位机确认Stop/Up/Down/Thumbs up/Thumbs Down对应LED4/7/1/6/5；LED0常亮为cfg_done。
- 窗口显示预测阈值0.45，而下发要求单类且每帧>=0.75、连续三个不同新帧。同类保持不重复发，1秒无有效结果清灯；阈值未降低。
- 新版动作异常不再主动结束视频，但硬件AXI挂死不是Python可保证隔离的故障。
- v1.3曾在成功运行后跨进程重载同一C时首帧超时；v1.4改为只允许从正在运行的原视频A进入动作版C，并加入10秒传感器预等待、30秒首帧诊断窗口和逐秒状态。该策略已经两次成功，但并未消除OV5640前置状态风险。
- 延长窗口可接纳迟到首帧，但不是SCCB/PCLK/VSYNC健康证明；30秒仍无真实帧转换时必须失败关闭并恢复原视频，禁止连续重试。
- 本包不提供机械臂安全控制、识别泛化精度或蓝牙集成保证。

## 板端启动（明确独立窗口后操作）

保留原SD与原视频服务文件；不要覆盖/home/xilinx/ees331_camera。
先上电，等待原cfg_done/动态HDMI与PC UDP基线正常。关闭普通UDP接收器。将此目录放入全新板端目录，核验manifest哈希，在ARM板端编译：

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared mmio_ordered.c -o libmmio_ordered.so
```

停止实际视频所有者并检查journal：必须看到VDMA_HALTED后BUFFER_FREED、进程退出，不能只看systemctl active。若不能确认安全停止，不下载。
从确认正常的原视频A状态进入本包；已加载C时不要直接再次启动本程序。推荐使用`8_tools/EES331_PL_Reloader_v1.4`执行完整门控和失败恢复。

```sh
sudo systemctl stop ees331-camera
# 人工检查HALT/FREED与进程退出后，使用未存在的新证据目录：
sudo bash ./run_action_v1.sh --evidence /home/xilinx/action_runs/unique_run_name --seconds 0
```

`--seconds 0`持续运行；必须看到VIDEO_READY_BEFORE_ACTION及ACTION_SERVICE_READY再启用PC动作控制。失败不重试，保留events/result；安全停止后恢复原服务并检查真实视频。不要使用旧Overlay skill自动序列。
Ctrl+C为正常停止；先关闭PC上位机使正常AXI清灯，再停止板端程序，确认HALT/FREED后才运行`sudo systemctl start ees331-camera`。系统ctl启动成功不是HDMI/UDP恢复验收。

## PC可视化使用

在仓库固定模型环境下：

```powershell
powershell -ExecutionPolicy Bypass -File E:/competition/3_host/model_env/run_python.ps1 E:/competition/3_host/model_env/gesture_viewer.py --action-control
```

**人工测试不要加--smoke-seconds**，它会自动关闭窗口。不得同时启动普通UDP接收器；COM4观察为9600/8N1、只接收。
直接双击识别EXE默认只显示/识别，不启用动作协议；LED验证必须从v1.4内部“打开动作识别”按钮启动，或使用上述`--action-control`命令。动作日志需先出现`ACTION_INITIAL_CLEAR`和`ACTION_LINK_READY`。
若默认SD原视频仍在运行，先完成上述板端切换，不要单独运行AXI客户端。
自动取证入口为model_action_validation.py，它与GUI互斥使用UDP5000/COM4。其结果只覆盖实际出现的动作，需检查stable_actions并保留物理确认。

## 当前状态与复现入口

2026-09-13已完成两轮v1.4加载与五种启用动作LED人工确认；随后也复现并定位了“直接重开模型只有识别、没有LED”的原因：直接启动处于显示模式，`protocol=null`。从v1.4内部重新打开后动作序号继续、确认正常。完整操作见[上板复现指南](../../../1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md)。原SD开机仍只启动原视频，不自动进入动作版。
