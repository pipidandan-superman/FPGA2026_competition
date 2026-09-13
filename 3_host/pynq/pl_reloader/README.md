# EES-331 PL 在线重加载工具 v1.4

本工具将动作版 BIT/HWH、PYNQ应用、哈希验证、原视频安全停止、单次PL加载、READY等待和失败恢复封装为一个Windows图形化程序。SD镜像、BOOT.BIN和原`ees331-camera`开机服务不变；动作版不会设为开机自启。

当前固定版本已完成两轮 A→C 上板成功，其中第二轮发生在用户确认断电、重新上电后；五种启用手势均已由用户确认对应LED输出。该结果仍是2/2样本，不外推为长期冷启动可靠性。队友从上电开始的完整步骤、停止条件和证据入口见[上板复现指南](../../../1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md)。

## 使用

1. 开发板保持SD启动，上电后等待原HDMI/UDP动态视频正常。
2. 双击`EES331_PL_Reloader.exe`；SSH密码默认自动填充为`xilinx`，如板卡密码已修改可直接覆盖。
3. 勾选“已确认当前原HDMI/UDP画面动态、流畅”，点击“一键加载动作版PL”。
4. 工具显示`ACTION_OVERLAY_READY`后，观察HDMI，并使用自动打开的动作识别程序核对LED。
5. 要回到原视频时点击“恢复原视频”，随后人工确认动态HDMI/UDP。

动作识别必须由v1.4内部“打开动作识别”按钮启动，或显式使用`--action-control`。直接双击识别EXE默认是显示模式，日志会显示`protocol=null`，可以识别但不会向AXI/LED下发；这不是PL加载失败。

默认开发板地址`192.168.240.10`，用户名`xilinx`。应用使用Windows自带的OpenSSH `ssh.exe`和`scp.exe`，不再依赖PuTTY。首次连接会自动接受新主机密钥；已缓存的密钥发生冲突时工具会失败，不会静默接受变化。

## 自动安全门

- 本地先核对13项发布清单，再上传到独立目录`/home/xilinx/pl_reloader/action_v1_20260913`。
- SSH登录前先检查开发板TCP 22端口；板卡未上电、网线断开或PC有线网卡不是`192.168.240.2/24`时会直接给出网络提示。
- 板端再次逐项核对SHA-256和HWH硬件合同，并在ARM端编译`libmmio_ordered.so`。
- 只允许从正在运行的原`ees331-camera`基线进入动作版；停止时要求`VDMA_HALTED`后出现`BUFFER_FREED`。
- 进程检查使用不自匹配的模式并解析真实PID/命令行；不会再把`pgrep`查询命令自身误认为`camera_action_v1.py`。
- 检测到真实`camera_action_v1.py`时安全跳过C→C重复下载，结果明确记为`SKIPPED/本次未执行`，不得显示“加载完成”。
- 只有板端控制器返回`ACTION_OVERLAY_READY`时才显示动作版加载完成并自动打开动作识别。
- 动作位流下载后执行10秒传感器预等待，并在最多30秒的首帧窗口内每秒报告VDMA槽位和状态；该等待是诊断性容错，不冒充SCCB/PCLK/VSYNC就绪证明。
- 板端控制器把动作服务journal增量转发到GUI，SSH输出逐行实时显示，不再等整个远程命令结束后批量出现。
- 动作运行使用不自启的systemd transient service；关闭Windows工具不会终止板端运行。
- `FIRST_FRAME_TIMEOUT`、`FAIL`、`DEGRADED`或READY超时会停止动作服务并请求恢复原视频。
- 每次使用唯一板端证据目录`/home/xilinx/pl_reload_runs/<timestamp>`；PC日志保存在`E:/competition/4_metrics/logs/<timestamp>_pl_reloader_gui_run01`。

## 边界

工具检测到READY仍不等于物理验收；HDMI画面和LED必须人工观察。网络或AXI硬挂死时软件不能保证恢复，遇到程序明确报错时不要反复点击加载。

SSH密码不会写入日志、配置文件或命令行参数。v1.4按用户要求在密码框中默认填充`xilinx`，每次操作后恢复该默认值；程序只通过子进程的临时环境向随包提供的OpenSSH AskPass辅助程序传递密码，因此仅应在受信任的本地开发机和直连实验网络使用。

载荷固定为`action_v1_20260913`：BIT SHA-256 `bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`，HWH SHA-256 `64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0`。

Windows发布只保留`8_tools/EES331_PL_Reloader_v1.4`；v1.0～v1.3不属于当前交付。失败运行的原始证据仍保留，不能因删除旧程序而删除。
