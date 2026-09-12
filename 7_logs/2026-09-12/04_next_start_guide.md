# 下一次从这里开始：蓝牙短时验证通过

先读[验证状态](../../1_docs/doc/ees331_ble_validation_status_2026-09-12.md)和[方案v1.1](../../1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。

保留ble_uart_debug_top.bit诊断基线。BLE上位机直接扫描连接MLT-BT05、订阅FFE1，不先Windows PIN配对；COM4=9600/8N1，无流控，HEX无后缀。当前测试已主动断开且COM4释放。无需ILA即可双向字节比对。

未经用户开始指令不要重烧板、改TYPE/PIN、恢复出厂、自动发送动作或直接写main。当前电平桥没有UART字节解析/FIFO/帧错误计数，不是正式PL控制器。

下一阶段可选：补齐正式B0/B1/B2可靠性门槛，或经批准实现字节级UART/FIFO及C0/C1 AXI-Lite+独立BRAM控制。机械臂尚未到货/互通未证实，不把PC Central成功外推为MLT Central或BT24直连成功。

本次交付与排除项见[发布记录](../../4_metrics/logs/2026-09-12_ble_validation_publish_run01/REPORT.md)。需要本机EXE时使用8_tools/EES331_BLE_Console_v1.0的完整目录；本次分支交付源码而非EXE依赖包。
