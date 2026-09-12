# EES-331 蓝牙验证状态与复现

更新：2026-09-12。结论：**PC ↔ 板载 MLT-BT05 ↔ PL ↔ COM4 短时双向通信通过**。

## 已通过与未通过

最新补充（22:48）：BLE Console v1.1 已集成推荐未配对直连门控和自动通知。
31项离线/Tk测试通过；新版后端三轮双向各18字节、ready后保持60.5秒通过；
发布EXE按钮另行核对55AA3132/AA553231。用户随后明确反馈“OK，双向通信成功”，
记录为手动复现确认，不新增未测量的轮数、时长或误码率。

|项目|证据与边界|
|---|---|
|有线AT|COM4，9600/8N1，连续3次OK；固件MLT-BT05-V4.2。PIN只读确认，不公开凭据。|
|无线双向|未配对GATT，11轮、61.703秒，每方向166字节逐字节相同，无多余数据或异常断连。|
|硬件实现|独立电平桥仿真、综合、布局布线、bit生成通过；WNS 5.872ns、WHS 0.160ns。|
|限制|不是同时满速双工、长期压力或完整B1验收；CDC异步复位尚未签核，无字节级错误计数。|
|后续|1000帧/分包/CRC/10分钟并行、重连恢复、机械臂模块互通、正式AXI-Lite/BRAM均待独立验收。|

“未配对”不等于“没有蓝牙连接”。Windows设置的PIN配对记录与程序实际建立的GATT
会话是不同步骤；此次由Windows蓝牙适配器真实无线传输，COM4是对端核对通道。
初始配对状态下反复短连接；经批准只移除目标配对后，同一只读脚本及后续字节测试通过。
这指向配对/安全状态相关问题，但尚未确定Windows、密钥或模块固件的精确根因。

```text
PC BLE程序 → 无线 → MLT-BT05 → PL电平桥 → CP2103/COM4接收
PC BLE程序 ← 无线 ← MLT-BT05 ← PL电平桥 ← CP2103/COM4发送
```

## 当前复现方式

1. 下载独立工程生成的ble_uart_debug_top.bit，清空旧ILA的ltx；约1.1秒后LED0指示就绪。
2. 使用BLE Console v1.1，保留“已验证直连模式”和“自动订阅通知”，直接扫描连接MLT-BT05，不先进行Windows PIN配对。只使用一个活动测试客户端。
3. 等待三次真实读取及连接保持检查完成，显示“校验通过，可收发”；默认已订阅FFE1。另开串口助手COM4，9600/8N1、无流控、HEX、无后缀、无本地回显。
4. BLE发送55 AA 31 32 00 FF，COM4应收到相同6字节；反向发送AA 55 32 31 FF 00，通知应一致。
5. 遇到断连或不一致停止，保存全部失败样本，不通过重复筛选PASS。AT查询需先断开无线连接。

上述自动测试结束为程序主动断开，COM4已释放；不代表当前实时连接状态。保持已验证bit，不要擅自恢复出厂或改PIN。
上位机源码：[3_host/ble_console](../../3_host/ble_console/README.md)。本次上传源码、说明、
测试脚本和精选文本证据；EXE依赖树、bit/ltx、Vivado生成工程及包含凭据/周边设备的日志留本地。
可使用源码及构建脚本重建；最新本地EXE位于8_tools/EES331_BLE_Console_v1.1，旧v1.0保留。

## TX、RX 与文本乱码的判读

`TX 55 AA 31 32 | U�12` 是本机发送调用完成的记录，不是PL回包；
无响应写也不含对端确认。HEX才是实际字节：55对应U，31/32对应1/2，
AA单独不是有效UTF-8字符，文本栏因此显示替代字符，不意味着无线数据损坏。
应在COM4核对接收HEX；反向从COM4发送，再核对蓝牙窗口的RX NOTIFY。
当前PL电平桥不会自动回显；只有实际两端数据一致才记该方向通过。

## 证据

- [v1.1源码/打包/验证](../../4_metrics/logs/2026-09-12_ble_console_v11_run01/REPORT.md)、
  [新版后端及EXE双向原始记录](../../4_metrics/logs/2026-09-12_ble_console_v11_board_run02/REPORT.md)。
- [用户手动复现确认](../../4_metrics/logs/2026-09-12_ble_manual_confirmation_run01/REPORT.md)。
- [本次v1.1上传范围](../../4_metrics/logs/2026-09-12_ble_v11_publish_run01/REPORT.md)。

- [双向实机结果](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/REPORT.md)、[原始字节事件](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/test_events.json)。
- [授权移除配对与只读对照](../../4_metrics/logs/2026-09-12_ble_unpaired_bridge_run01/REPORT.md)。
- [发布范围与排除项](../../4_metrics/logs/2026-09-12_ble_validation_publish_run01/REPORT.md)。
- 完整AT/PIN、厂商解析、失败诊断及Vivado运行记录留本地原始run；公开归档不复制设备PIN和周边扫描数据。

下一阶段须由用户确认开始：保留电平桥作为诊断基线，正式控制采用字节级UART/FIFO，
再接自定义AXI-Lite控制寄存器与独立AXI BRAM Controller/TDP BRAM；当前不自动实施。
