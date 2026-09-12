# 下一次从这里开始：蓝牙短时验证通过

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

先读[验证状态](../../1_docs/doc/ees331_ble_validation_status_2026-09-12.md)和[方案v1.1](../../1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。

保留ble_uart_debug_top.bit诊断基线。BLE上位机直接扫描连接MLT-BT05、订阅FFE1，不先Windows PIN配对；COM4=9600/8N1，无流控，HEX无后缀。当前测试已主动断开且COM4释放。无需ILA即可双向字节比对。

未经用户开始指令不要重烧板、改TYPE/PIN、恢复出厂、自动发送动作或直接写main。当前电平桥没有UART字节解析/FIFO/帧错误计数，不是正式PL控制器。

下一阶段可选：补齐正式B0/B1/B2可靠性门槛，或经批准实现字节级UART/FIFO及C0/C1 AXI-Lite+独立BRAM控制。机械臂尚未到货/互通未证实，不把PC Central成功外推为MLT Central或BT24直连成功。

本次交付与排除项见[发布记录](../../4_metrics/logs/2026-09-12_ble_validation_publish_run01/REPORT.md)。需要本机EXE时使用8_tools/EES331_BLE_Console_v1.0的完整目录；本次分支交付源码而非EXE依赖包。
