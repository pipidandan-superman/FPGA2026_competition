# 主视频工程 AXI-Lite／蓝牙集成

## 范围

本次以 `proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr`
为主工程，保留 OV5640、VDMA、ADV7511 和 PS/Linux 视频链路，并加入两项已经在
独立工程验证过的 PL 功能：

- `axi_lite_test_0`：AXLT ABI 1.0 寄存器控制；
- `ble_uart_bridge_0`：板载 MLT-BT05 与 COM4 之间的透明 UART 桥。

BRAM 字节回环尚未实现，不能把本工程称为 BRAM 阶段通过。主 BD 继续使用原名
`display_test`；独立验证工程的 BD 名仍为 `AXI_LITE_test`。

## 结构与接口

PS 的 `M_AXI_GP0` 经 SmartConnect 分别连接 VDMA 和寄存器从设备。寄存器自研模块
通过 `rtl/control/video_axi_lite_control_top.v` 作为 Verilog Module Reference 拖入
BD，内部复用 `2_fpga/2_axi_lite_test/rtl` 的协议层、寄存器组和执行器。

| 资源 | 地址／频率 | 说明 |
|---|---:|---|
| `axi_vdma_0` | `0x43000000 / 64 KiB` | 原视频寄存器窗口，不变 |
| `axi_lite_test_0` | `0x43C00000 / 4 KiB` | AXLT ABI 1.0 |
| PS FCLK0 | 50 MHz | AXI、VDMA及寄存器控制时钟 |
| M19 板级输入 | 100 MHz | 摄像头时钟向导及蓝牙桥 |

蓝牙外部端口为 `PL_RS232_RX/TX`、`BT_TX/RX`、`FPGA_BT_3V3` 和
`BT_RESET_N`。`BRIDGE_READY` 保持为 BD 内部信号，不占用原来显示摄像头
`sccb_cfg_done_0` 的 V4 LED。

`rst_ps7_0_50M` 的外部复位和辅助复位均为低有效：`aux_reset_in` 与
`dcm_locked` 固定接 1，`mb_debug_sys_rst` 固定接 0，外设复位连接
`peripheral_aresetn`。PYNQ 下载前由 `pynq/main_hardware_contract.py` 对这些连接、
地址、时钟、VDMA 参数、模块和外部端口进行失败关闭检查。

M19 是非专用时钟管脚。最终实现对实际 `PLLE2_ADV` 采用 `BUF_IN`
补偿，并保留 `CLOCK_DEDICATED_ROUTE FALSE`；构建脚本会读取实现后的单元属性，
不是只检查 Clock Wizard GUI 字段。

## 可复现入口

- `proj/integrate_axi_ble.tcl`：幂等更新主 BD、源文件和地址；
- `sim/run_axi_lite_wrapper.tcl`：在新证据目录运行 50 MHz 包装层自检；
- `proj/build_axi_ble.tcl`：综合、实现、DRC、时序、BIT/HWH/XSA 发布；
- `pynq/audit_release.py`：离线核对部署 BIT/HWH 的哈希和 HWH 合同；
- `pynq/camera.py`：加载配对 Overlay 并运行视频；
- `pynq/coexist_test.py`：不重复下载位流，在视频运行时执行至少 1000 条 AXI 命令。

Vivado 2025.2 示例：

```powershell
F:\vivado2025\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -nolog `
  -source E:\competition\2_fpga\0_diaplay_test\sim\run_axi_lite_wrapper.tcl `
  -tclargs E:\competition\4_metrics\logs\<new-sim-run>

F:\vivado2025\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -nolog `
  -source E:\competition\2_fpga\0_diaplay_test\proj\build_axi_ble.tcl `
  -tclargs E:\competition\4_metrics\logs\<new-build-run>
```

输出目录必须是新目录，失败证据不可被后一次成功覆盖。

## 已完成的本地门槛

- 主包装层自检：`MAIN_AXI_WRAPPER_SIM_PASS`，50 MHz；
- 新进程 BD 检查：`MAIN_BD_VALIDATION_PASS`，0 个 Critical Warning／Error；
- 实现：setup 5.978 ns、hold 0.024 ns、黑盒 0、DRC Error 0；
- 实现后 M19 PLL 补偿：`BUF_IN`；
- 发布审计：`MAIN_AXI_BLE_RELEASE_AUDIT_PASS`；
- 部署对：BIT `633e7846...d9a5d0`，HWH `8f759760...4beec0`。

对应原始证据分别位于：

- `4_metrics/logs/2026-09-13_main_axi_wrapper_sim_run05/`；
- `4_metrics/logs/2026-09-13_main_axi_ble_integration_run11/`；
- `4_metrics/logs/2026-09-13_main_axi_ble_build_run08/`；
- `4_metrics/logs/2026-09-13_main_hwh_contract_run01/`；
- `4_metrics/logs/2026-09-13_main_pynq_audit_run01/`。

## 上板验收

上板必须在独立目录加载新位流，不覆盖已验证的 `/home/xilinx/ees331_camera`，
并同时保留以下三路证据：

1. 视频服务持续运行，PC UDP 帧 CRC／丢帧／坏包为 0，并由现场确认 HDMI 动态画面；
2. `coexist_test.py` 完成 1000 条寄存器命令，序号、取反结果及执行计数一致；
3. MLT-BT05 的 FFE1 与 COM4 在两个方向各完成 11 轮精确字节比对。

测试完成后恢复原服务并验证真实新帧；只有三路均通过才将结果标为主工程共存 PASS。

### 2026-09-13 实机结果

自动化部分已通过：集成相机运行 130.053 秒并生成 650 帧；PC 在其中 80.079 秒
接收 400 个完整动态帧、丢帧 0；同一时间完成 1000 条 AXI 命令和 11 轮蓝牙双向
精确比对。测试结束后原服务重新 active，PC 又收到 100 个完整动态帧、丢帧 0。
详细证据见
`4_metrics/logs/2026-09-13_main_axi_ble_board_run01/REPORT.md`。

当前标记为 `MAIN_AXI_BLE_AUTOMATED_BOARD_PASS`，等待用户补充集成窗口和恢复后的
HDMI 物理观察后再升级为完整共存 PASS。BRAM 不在本次结果范围内。
