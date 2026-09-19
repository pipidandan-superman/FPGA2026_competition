# M13 板级构建（yolo_sys BD → yolo_a2.xsa/.bit，2026-09-18）

## 判定（run8，2026-09-18 00:25）

```
BOARD_TIMING wns_ns=0.954
BOARD_BITSTREAM_PASS wns_ns=0.954 xsa=E:/competition/2_fpga/3_yolo_zynq/proj/board_sys/yolo_a2.xsa
```

- 全设计（PS7 + 引擎 + 自动化互连）@ FCLK0=60MHz WNS +0.954、
  "All user specified timing constraints are met"（timing summary
  rpt 已存）；与 OOC v28b60 引擎净表 +0.806 一致（含互连后仍余量）。
- 产物：yolo_sys_wrapper.bit 4,045,692 B（已拷 proj/board_sys/yolo_a2.bit）
  + yolo_a2.xsa 1,664,361 B（write_hw_platform -include_bit）。

## 设计

- BD yolo_sys = ps7（EES-331 533 项 + A2 覆盖 FCLK0=60MHz/HP0/HP1/GP0）
  + engine（module_ref yolo_engine_top V1.1，PROD-16x16）
  + proc_sys_reset（dcm_locked 恒 1——悬空=0 会把 peripheral_aresetn
  永久拉死）+ xlconstant。
- 无 PL 外部引脚（全部流量走 PS DDR）；无 IRQ v1（STATUS 轮询）。

## 地址图（run7 log 实证，= 合同三件）

```
Slave segment '/engine/s_axi/reg0'      → /ps7/Data    @0x43C1_0000 [64K]  (CSR)
Slave segment '/ps7/S_AXI_HP0/HP0_DDR_LOWOCM' → /engine/m_axi   @0x0000_0000 [1G]
Slave segment '/ps7/S_AXI_HP1/HP1_DDR_LOWOCM' → /engine/x_m_axi @0x0000_0000 [1G]
```

DDR carve-out 0x3000_0000 落在两主口 1G 窗内 ✓；HP 数据位宽 64
（ps7 配置）= 引擎 m_axi_wdata/rdata、x_m_axi_rdata 64 ✓。

## 构建坑链条（八跑剥洋葱，1–3 见会话日志 §6）

| 跑 | 拦点 | 修法 |
|---|---|---|
| 1 | `set_property -dict $ps7_cfg` 二次求值 MIO_TREE 里的 `['SD` | 逐对 foreach |
| 2 | MIO IOTYPE 校验先要 BANK 电压 | 两遍法（BANK 电压先行） |
| 3 | .bd JSON {"value":…} 二元列表被写成 Python repr | 重生成 tcl：list→`{{e0} {e1}}` |
| 4 | HP 自动化 config Slave+引脚=m_axi → 规则反查从侧失败 | 同构 GP0：config Master=引擎主 + 引脚=HP 从 |
| 5 | 从段被自动分配 reg0@0x4000_0000/1G；OFFSET 只读 [17-107] | delete_bd_objs 删映射 + assign_bd_address 重指 0x43C1_0000/64K |
| 6 | module_ref AXI 接口默认 FREQ_HZ=100MHz、无时钟关联（BD 41-237/41-967） | 建后自动化前：CONFIG.FREQ_HZ 60000000 ×3 + ASSOCIATED_BUSIF 挂 clk_i |
| 7 | `launch_runs synth_1 impl_1 -to_step write_bitstream`（12-1015 对 synth_1 非法步） | 两段式：synth 单发，impl -to_step |
| 8 | — | **PASS wns=+0.954** |

## 复现（cwd proj/board_sys）

```
F:/vivado2025/2025.2/Vivado/bin/vivado.bat -mode batch -source build_board.tcl -nojournal -log build_board_run8.log
```

产物：`yolo_a2_board/…/impl_1/yolo_sys_wrapper.bit`、`yolo_a2.xsa`
（write_hw_platform -include_bit）。

## 哈希（sha256 前 16）

```
cde1a4a077bf7830  yolo_a2.bit    (4,045,692 B)
1c75b4ab773c789e  yolo_a2.xsa    (1,664,361 B)
b13776bdcf55e19a  build_board.tcl（run8 终版，含 1–7 全部修复）
c61c94b9f5b0fab3  ps7_ees331.tcl
bcb3f0b2193cd003  yolo_sys.xdc
```
