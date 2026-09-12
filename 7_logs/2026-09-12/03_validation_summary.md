# 2026-09-12 蓝牙验证摘要（精选发布）

- [短时双向实机报告](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/REPORT.md)：BLE_UART_DUPLEX_11_ROUNDS_60S_PASS；11轮、61.703秒、每方向166字节精确一致。结束主动断开，COM4释放。
- [原始收发事件](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/test_events.json)：记录每轮两个不同方向的发送与实际接收，不是PC本地回显。
- [未配对对照](../../4_metrics/logs/2026-09-12_ble_unpaired_bridge_run01/REPORT.md)：用户授权后目标配对实际移除，同一脚本三次无缓存远端读取通过。
- [PL桥构建](../../4_metrics/logs/2026-09-12_pl_uart_bridge_build_run02/REPORT.md)：仿真与实现通过；CDC异步复位未知端点和PL-only ZPS7警告保留说明，不冒充生产签核。
- [发布审查](../../4_metrics/logs/2026-09-12_ble_validation_publish_run01/REPORT.md)：显式清单、原始证据取舍、测试和分支推送边界。

未完成：正式方案B0十次/错误计数、B1各1000帧/CRC/分包/10分钟并行/P95、B2十次重连与复位、BT24机械臂互通、AXI/BRAM实施。未配对并非无连接；测试期间由Windows适配器建立真实GATT会话。

完整失败/AT/PIN/厂商解析/Vivado底层日志留在本机，发布时排除凭据和周边设备数据，不声称这些原件均已上传。
