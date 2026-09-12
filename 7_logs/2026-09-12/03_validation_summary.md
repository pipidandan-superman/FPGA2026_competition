# 2026-09-12 蓝牙验证摘要（精选发布）

## 新增：v1.1接入流程与用户手动确认

v1.1默认未配对GATT、三次无缓存读取/保持门控、自动订阅通知和异常停止。
31项离线/Tk测试、新版后端60.5秒三轮双向各18字节、实际EXE按钮双向核对通过；
用户另行反馈“OK，双向通信成功”，仅记手动复现确认，不增加未提供的量化指标。
源码/构建/使用说明及TX与文本乱码解释已更新，方案状态升级v1.2，原验收门槛不变。

[新版实机原始记录](../../4_metrics/logs/2026-09-12_ble_console_v11_board_run02/REPORT.md) ·
[用户确认](../../4_metrics/logs/2026-09-12_ble_manual_confirmation_run01/REPORT.md) ·
[本次上传范围](../../4_metrics/logs/2026-09-12_ble_v11_publish_run01/REPORT.md)。
本地新包8_tools/EES331_BLE_Console_v1.1，旧版保留。本次发布源码/测试/说明及精选文本证据，
不上传EXE依赖包、截图、PIN、周边扫描日志、构建缓存，不改冻结FPGA。
个人worktree显式暂存、普通push，不合入main；最终回执以本机push_receipt.json为准。
下一阶段持续通信/重连或正式AXI/BRAM开发须等用户明确开始，不自动执行。
下方为前次里程碑历史记录；完整本机日记保留，当前文件为本任务精选发布摘要。

- [短时双向实机报告](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/REPORT.md)：BLE_UART_DUPLEX_11_ROUNDS_60S_PASS；11轮、61.703秒、每方向166字节精确一致。结束主动断开，COM4释放。
- [原始收发事件](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/test_events.json)：记录每轮两个不同方向的发送与实际接收，不是PC本地回显。
- [未配对对照](../../4_metrics/logs/2026-09-12_ble_unpaired_bridge_run01/REPORT.md)：用户授权后目标配对实际移除，同一脚本三次无缓存远端读取通过。
- [PL桥构建](../../4_metrics/logs/2026-09-12_pl_uart_bridge_build_run02/REPORT.md)：仿真与实现通过；CDC异步复位未知端点和PL-only ZPS7警告保留说明，不冒充生产签核。
- [发布审查](../../4_metrics/logs/2026-09-12_ble_validation_publish_run01/REPORT.md)：显式清单、原始证据取舍、测试和分支推送边界。

未完成：正式方案B0十次/错误计数、B1各1000帧/CRC/分包/10分钟并行/P95、B2十次重连与复位、BT24机械臂互通、AXI/BRAM实施。未配对并非无连接；测试期间由Windows适配器建立真实GATT会话。

完整失败/AT/PIN/厂商解析/Vivado底层日志留在本机，发布时排除凭据和周边设备数据，不声称这些原件均已上传。
