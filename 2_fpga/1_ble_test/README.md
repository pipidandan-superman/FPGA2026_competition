# EES-331 PL 蓝牙 UART 诊断工程

本目录用于验证 PL 与板载 MLT-BT05 的 UART 通路，不包含 AXI-Lite、BRAM 邮箱或
机械臂控制协议。

## 目录

- `rtl/`：UART TX/RX、AT 测试控制器、顶层与 EES-331 XDC。
- `sim/`：PASS/timeout 自检 testbench 和 XSim 复现脚本。
- `proj/ble_test_vivado_2025_2/`：Vivado 2025.2 工程。
- `proj/create_ble_test_project.tcl`：从原路径重建工程并生成 bitstream 的脚本。

工程仅引用 `rtl/` 中的源文件；未将 RTL/XDC 复制进工程。仿真 testbench 不属于
工程 Design Sources。

三个 FSM（UART TX、UART RX、AT 测试控制器）统一采用严格三段式：

1. 第一段为时序状态寄存器；
2. 第二段为组合次态逻辑；
3. 第三段为时序输出及数据通路逻辑。

每个 FSM 的复位状态均固定为 `STATE_IDLE`。控制器从 `STATE_IDLE` 进入上电等待，
不再把上电等待状态兼作复位初态。

## 功能

上电后顶层执行以下序列：

1. 使能蓝牙供电并保持复位 100 ms；
2. 释放复位并等待 1000 ms；
3. 以 9600 8N1 发送 `AT\r\n`；
4. 收到连续顺序中的 `O`、`K` 后锁存 PASS；
5. 500 ms 内未收到 `OK` 时锁存 FAIL。

顶层默认使用 EES-331 的 100 MHz PL 时钟。若模块固件要求无行结束符，可将顶层
参数 `SEND_CRLF` 改为 `0`，此时只发送 `AT`。

## 仿真

```powershell
powershell -ExecutionPolicy Bypass -File E:\competition\2_fpga\1_ble_test\sim\run_xsim.ps1
```

通过标记为 `BLE_RTL_SIM_PASS`。testbench 同时检查正常 `OK` 响应和无响应超时。

## 上板文件

- `proj/ble_test_vivado_2025_2/ble_test_vivado_2025_2.runs/impl_1/ble_test_top.bit`
- `proj/ble_test_vivado_2025_2/ble_test_vivado_2025_2.runs/impl_1/ble_test_top.ltx`

下载时必须使用同一次构建生成的 `.bit` 与 `.ltx`。

LED 映射：LED0 PASS、LED1 timeout FAIL、LED2 收到合法字节、LED3 UART frame
error、LED4--LED7 为状态机状态低位到高位。

ILA 深度为 65536，包含 UART 串行线、收发字节、start/done/busy、frame error、
状态机、电源和复位。删除调试逻辑时将 `ENABLE_ILA=0`，再从工程移除 `ila_0` IP。

详细构建证据见：
`4_metrics/logs/2026-09-12_ble_fsm_refactor_vivado_run01/REPORT.md`。

`2026-09-12_ble_vivado_build_run01` 对应旧 FSM 写法，已被本次重新仿真和重新构建
明确取代，不得再用于上板。

## 新增：独立 PL USB-UART 透明桥版本

本节只适用于 `ble_uart_debug_top`，不改变上面的 AT/ILA 版本。

- RTL：`rtl/ble_uart_debug_top.v`；约束：`rtl/ees331_ble_uart_debug.xdc`。
- 工程：`proj/ble_uart_debug_vivado_2025_2/ble_uart_debug_vivado_2025_2.xpr`。
- bit：`proj/ble_uart_debug_vivado_2025_2/ble_uart_debug_vivado_2025_2.runs/impl_1/ble_uart_debug_top.bit`。
- 本版本不含 ILA，不加载旧 `.ltx`；仅引用上述一份 RTL 和一份 XDC。
- 三段式上电 FSM 从 `STATE_IDLE` 复位；保持模块复位 100 ms，释放后等待 1000 ms。
- LED0 对应 BRIDGE_READY，表示桥已使能，不表示蓝牙已连接或 AT 已通过。

链路：PC COM4 ↔ J8 上层 USB/CP2103 ↔ PL A16/A17 ↔ PL Y13/AA13 ↔ MLT-BT05。
这是经过双级同步与寄存输出的串行电平透传，不进行字节解析、缓存或波特率转换，
也不会自动发送 AT。两端波特率必须一致，初次使用按当前模块配置选择 9600、8N1、
无流控；更改 PC 波特率并不会自动修改蓝牙模块波特率。

上板步骤：

1. 用户下载本节的新 bit，清空 Hardware Manager 中旧 ILA probes 文件。
2. 等待约 1.1 秒；断开 PC/手机与 MLT-BT05 的 BLE 连接，避免处于无线透传模式。
3. 串口助手打开 COM4，9600、8N1、无流控，关闭本地回显，ASCII 模式发送 `AT`，
   附加 CRLF。必须以收到模块真实 `OK` 为 UART 链路验收，不把发送区回显当响应。
4. 收到真实响应后查询固件版本，按该固件支持的只读 AT 指令查询 PIN/认证配置。
   当前尚未读出实际 PIN，禁止凭型号猜值或发送修改 PIN、恢复出厂等命令。
5. 需要无线透传测试时再连接 BLE；COM4 发送字节由模块无线发出，BLE 写入则在 COM4
   接收区显示。两个方向各需实测，不能沿用旧 ILA 单字节结果宣布本桥双向上板通过。

仿真文件 `sim/tb_ble_uart_debug_top.v` 覆盖 ASCII、00/FF/AA/55、全双工及复位恢复。
其中模拟回复 `654321` 仅是测试数据，**不是板卡 PIN**。
仿真与构建证据：`4_metrics/logs/2026-09-12_pl_uart_bridge_build_run02/`。
原 AT/ILA RTL、XDC、bit 均保留，可以重新下载旧 bit+ltx 回退。
