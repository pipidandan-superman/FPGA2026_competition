# OV5640 + HDMI 显示 BD 关键连线核对清单

- 日期：2026-09-03  
- 状态：静态核对完成，未修改 BD/RTL  
- 结论：**OV5640 采集、DDR/VDMA、视频流回放、VTC 时序到新 HDMI 输出前端的关键连线与 2020 参考方案一致；HDMI 输出边界按 2025 工程的 ADV7511 方案替换属于预期差异。**

## 1. 对比对象与范围

### 参考工程

`E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vmda_test.srcs\sources_1\bd\design_1\design_1.bd`

参考 BD 顶层：`design_1`，器件 `xc7z010clg400-1`，Vivado 2020.2。

### 当前工程

`E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\sources_1\bd\display_test\display_test.bd`

当前 BD 顶层：`display_test`，器件 `xc7z020clg484-1`，Vivado 2025.2。

### 范围

只核对以下路径：

```text
OV5640 引脚
  -> cam_captrue_data
  -> v_vid_in_axi4s
  -> axi_vdma S2MM
  -> Zynq HP1 / DDR

Zynq HP0 / DDR
  -> axi_vdma MM2S
  -> v_axi4s_vid_out
  -> pix_frame_display
  -> hdmi_out_adv7511
  -> ADV7511 / HDMI 连接器
```

同时核对时钟、复位、AXI 控制面、AXI HP 口和关键 IP 配置。

### 明确不作为错误处理的工程差异

| 项目 | 2020 参考工程 | 2025 当前工程 | 判定 |
|---|---|---|---|
| 器件 | Zynq 7010，`xc7z010clg400-1` | Zynq 7020，`xc7z020clg484-1` | **工程基线差异，不是错误** |
| 外部系统时钟到 Clocking Wizard | 50 MHz | 100 MHz | **工程基线差异，不是错误** |
| Zynq 配置 | Zynq 7010 PS 配置 | Zynq 7020 PS 配置 | **器件/工程基线差异，不是错误** |
| Vivado/IP 版本 | Vivado 2020.2 | Vivado 2025.2 | 预期版本差异 |
| HDMI 输出实现 | `HDMI_top` 直驱 TMDS | `hdmi_out_adv7511` 驱动 ADV7511 并行总线 | **预期架构替换** |
| AXI 地址 | 参考工程旧地址 | 当前工程 Vitis 阶段单独指定 | 本次不比较地址值 |
| 中断 | CNN/后处理路径使用 `IRQ_F2P` | 当前显示链路无 `IRQ_F2P` | 预期功能裁剪差异；视频 VDMA 中断两侧均未接入 |

## 2. 关键链路总图

### 采集 / 写 DDR

```text
OV5640 D[7:0], PCLK, HREF, VSYNC
  -> cam_captrue_data
  -> vid_data / vid_vsync / vid_active_video / vid_ce / vid_clk
  -> v_vid_in_axi4s
  -> video_out AXI-Stream
  -> axi_vdma S_AXIS_S2MM
  -> axi_vdma M_AXI_S2MM
  -> axi_mem_intercon S01_AXI
  -> axi_mem_intercon M01_AXI
  -> processing_system7 S_AXI_HP1
```

### 显示 / 读 DDR

```text
processing_system7 S_AXI_HP0
  <- axi_mem_intercon M00_AXI
  <- axi_mem_intercon S00_AXI
  <- axi_vdma M_AXI_MM2S

axi_vdma M_AXIS_MM2S
  -> v_axi4s_vid_out video_in

v_tc vtiming_out
  -> v_axi4s_vid_out vtiming_in

v_axi4s_vid_out vid_data / vid_hsync / vid_vsync / vid_active_video
  -> pix_frame_display

pix_frame_display hdmi_data / hdmi_de / hdmi_hsync / hdmi_vsync
  -> hdmi_out_adv7511
  -> ADV7511 并口 / HDMI 连接器
```

## 3. OV5640 配置与采集连线

| 连接组 | 2020 参考连接 | 2025 当前连接 | 方向 | 判定 |
|---|---|---|---|---|
| SCCB 时钟 | `ov5640_cfg_top_0/sccb_clk` → `sccb_clk_0` | `ov5640_cfg_top_0/sccb_clk` → `sccb_clk_0` | FPGA → OV5640 配置时钟网络 | **一致** |
| SCCB 数据 | `sccb_data_0` ↔ `ov5640_cfg_top_0/sccb_data` | `sccb_data_0` ↔ `ov5640_cfg_top_0/sccb_data` | 双向 | **一致** |
| 配置完成 | `ov5640_cfg_top_0/sccb_cfg_done` → `sccb_cfg_done_0` | `ov5640_cfg_top_0/sccb_cfg_done` → `sccb_cfg_done_0` | FPGA 内部 → 顶层输出 | **一致** |
| 配置模块时钟 | `clk_wiz_0/clk_50m` → `ov5640_cfg_top_0/sys_clk` | `clk_wiz_0/clk_50m` → `ov5640_cfg_top_0/sys_clk` | Clocking Wizard → 配置模块 | **一致** |
| 配置模块复位 | `clk_wiz_0/locked` → `ov5640_cfg_top_0/sys_rst_n` | `clk_wiz_0/locked` → `ov5640_cfg_top_0/sys_rst_n` | Clocking Wizard → 配置模块 | **一致** |
| 相机 XCLK | `cam_captrue_data_0/cam_xclk` → `cam_xclk_0`；`clk_wiz_0/xclk` → `cam_captrue_data_0/i_xclk` | 相同 | FPGA → OV5640 XCLK | **一致** |
| 相机数据 | `cam_data_0[7:0]` → `cam_captrue_data_0/cam_data` | 相同 | OV5640 → FPGA | **一致** |
| 相机 PCLK | `cam_pclk_0` → `cam_captrue_data_0/cam_pclk` | 相同 | OV5640 → FPGA | **一致** |
| 相机 HREF | `cam_href_0` → `cam_captrue_data_0/cam_href` | 相同 | OV5640 → FPGA | **一致** |
| 相机 VSYNC | `cam_vsync_0` → `cam_captrue_data_0/cam_vsync` | 相同 | OV5640 → FPGA | **一致** |

补充核对：`cam_captrue_data` 与 `ov5640_cfg_top` 的 RTL 源文件在两个工程中 SHA256 相同，当前无源码级差异。

## 4. 采集数据到 VDMA / DDR

| 连接 | 2020 参考连接 | 2025 当前连接 | 判定 |
|---|---|---|---|
| 采集像素数据 | `cam_captrue_data_0/vid_data` → `v_vid_in_axi4s_0/vid_data` | 相同 | **一致** |
| 采集 VSYNC | `cam_captrue_data_0/vid_vsync` → `v_vid_in_axi4s_0/vid_vsync` | 相同 | **一致** |
| 采集有效视频 | `cam_captrue_data_0/vid_active_video` → `v_vid_in_axi4s_0/vid_active_video` | 相同 | **一致** |
| 采集像素时钟 | `cam_captrue_data_0/vid_clk` → `v_vid_in_axi4s_0/vid_io_in_clk` | 相同 | **一致** |
| 采集像素使能 | `cam_captrue_data_0/vid_ce` → `v_vid_in_axi4s_0/vid_io_in_ce` | 相同 | **一致** |
| Video In 到 VDMA | `v_vid_in_axi4s_0/video_out` → `axi_vdma_0/S_AXIS_S2MM` | 相同 | **一致** |
| VDMA 写 DDR | `axi_vdma_0/M_AXI_S2MM` → `axi_mem_intercon/S01_AXI` | 相同 | **一致** |
| 写通道到 PS | `axi_mem_intercon/M01_AXI` → `processing_system7_0/S_AXI_HP1` | 相同 | **一致** |

## 5. VDMA 读通道 / 视频输出

| 连接 | 2020 参考连接 | 2025 当前连接 | 判定 |
|---|---|---|---|
| VDMA 读 DDR | `axi_vdma_0/M_AXI_MM2S` → `axi_mem_intercon/S00_AXI` | 相同 | **一致** |
| 读通道到 PS | `axi_mem_intercon/M00_AXI` → `processing_system7_0/S_AXI_HP0` | 相同 | **一致** |
| VDMA 读流 | `axi_vdma_0/M_AXIS_MM2S` → `v_axi4s_vid_out_0/video_in` | 相同 | **一致** |
| VTC 时序 | `v_tc_0/vtiming_out` → `v_axi4s_vid_out_0/vtiming_in` | 相同 | **一致** |
| 输出使能回馈 | `v_axi4s_vid_out_0/vtg_ce` → `v_tc_0/gen_clken` | 相同 | **一致** |
| 输出像素数据 | `v_axi4s_vid_out_0/vid_data` → `pix_frame_display_0/vio_data` | 相同 | **一致** |
| 输出行同步 | `v_axi4s_vid_out_0/vid_hsync` → `pix_frame_display_0/vio_hsync` | 相同 | **一致** |
| 输出场同步 | `v_axi4s_vid_out_0/vid_vsync` → `pix_frame_display_0/vio_vsync` | 相同 | **一致** |
| 输出有效 | `v_axi4s_vid_out_0/vid_active_video` → `pix_frame_display_0/vio_active` | 相同 | **一致** |
| 输出常使能 | `xlconstant_0/dout` → `v_axi4s_vid_out_0/vid_io_out_ce`、`aclken` | 相同 | **一致** |

## 6. HDMI 输出边界

2020 工程的 HDMI 输出模块与 2025 工程不同，这里只核对前端公共信号。

| 前端信号 | 2020 `HDMI_top_0` 连接 | 2025 `hdmi_out_adv7511_0` 连接 | 判定 |
|---|---|---|---|
| 像素时钟 | `clk_wiz_0/pclk` → `HDMI_top_0/pix_clk` | `clk_wiz_0/pclk` → `hdmi_out_adv7511_0/PIX_CLK` | **逻辑位置一致** |
| 复位 | `clk_wiz_0/locked` → `HDMI_top_0/rst_n` | `clk_wiz_0/locked` → `hdmi_out_adv7511_0/RST_N` | **逻辑位置一致** |
| 像素数据 | `pix_frame_display_0/hdmi_data[23:0]` → `data_gen_0/data_i`；`data_gen_0/data_r_o/g_o/b_o` → `HDMI_top_0/red/green/blue_data` | `pix_frame_display_0/hdmi_data[23:0]` → `hdmi_out_adv7511_0/RGB888[23:0]` | **预期差异**：新模块内部接收 24 位 RGB888 |
| DE | `pix_frame_display_0/hdmi_de` → `data_gen_0/de` 和 `HDMI_top_0/de` | `pix_frame_display_0/hdmi_de` → `hdmi_out_adv7511_0/DE` | **逻辑位置一致** |
| HSYNC | `pix_frame_display_0/hdmi_hsync` → `HDMI_top_0/h_sync` | `pix_frame_display_0/hdmi_hsync` → `hdmi_out_adv7511_0/H_SYNC` | **一致** |
| VSYNC | `pix_frame_display_0/hdmi_vsync` → `HDMI_top_0/v_sync` | `pix_frame_display_0/hdmi_vsync` → `hdmi_out_adv7511_0/V_SYNC` | **一致** |
| 5 倍像素时钟 | `clk_wiz_0/pclk_x5` → `HDMI_top_0/pix_clk_x5` | 无；`hdmi_out_adv7511` 不使用 FPGA 直驱 TMDS 的 5 倍时钟 | **预期差异** |
| 输出物理接口 | `TMDS_clk_p/n`、`TMDS_data_p/n[2:0]`、`hdmi_en` | `HDMI_CLK_0`、`HDMI_DATA_0[15:0]`、`HDMI_DE/HSYNC/VSYNC/SCL/SDA`、`HDMI_INT_0` | **预期差异**：ADV7511 并口方案 |

### HDMI 结论

新模块不应接入 `pclk_x5`，也不应复制旧 TMDS 输出接口。2025 BD 中 `hdmi_out_adv7511` 的前端连接已经正确：

```text
PIX_CLK  = clk_wiz_0/pclk
RST_N    = clk_wiz_0/locked
RGB888   = pix_frame_display_0/hdmi_data
DE       = pix_frame_display_0/hdmi_de
H_SYNC   = pix_frame_display_0/hdmi_hsync
V_SYNC   = pix_frame_display_0/hdmi_vsync
```

ADV7511 配置与并行输出由 `hdmi_out_adv7511` 内部完成。

## 7. 时钟与复位

### 时钟

| 时钟 | 2020 参考 | 2025 当前 | 判定 |
|---|---|---|---|
| 外部 Clocking Wizard 输入 | `clk_in1_0`，50 MHz | `clk_in1_0`，100 MHz | **基线差异，不是错误** |
| Clocking Wizard `pclk` | 25 MHz | 25 MHz | **一致** |
| Clocking Wizard `pclk_x5` | 125 MHz | 125 MHz | 2020 用于旧 TMDS；2025 仍由 Clocking Wizard 输出但不进新 HDMI |
| Clocking Wizard `xclk` | 24.03846 MHz | 24.03846 MHz | **一致** |
| Clocking Wizard `clk_50m` | 50 MHz | 50 MHz | **一致** |
| PS FCLK0 | 150 MHz，作为 AXI 控制和 VDMA AXI/Stream 时钟 | 50 MHz，作为 AXI 控制和 VDMA AXI/Stream 时钟 | **基线差异，不是错误** |
| 像素域时钟 | `pclk` 到 `v_tc`、`v_axi4s_vid_out`、`pix_frame_display`、旧 HDMI | `pclk` 到 `v_tc`、`v_axi4s_vid_out`、`pix_frame_display`、`hdmi_out_adv7511` | **一致** |

### 复位

| 复位 | 2020 参考 | 2025 当前 | 判定 |
|---|---|---|---|
| 外部低有效复位 | `sys_rst_n_0` → `clk_wiz_0/resetn` | `resetn_0` → `clk_wiz_0/resetn` | **一致，仅顶层名不同** |
| Clocking Wizard locked | 到采集、VTC、显示、旧 HDMI 和相机配置复位 | 到采集、VTC、显示、新 HDMI 和相机配置复位 | **一致** |
| Video In/Out 视频域复位 | `clk_wiz_0/locked` 经 `util_vector_logic_0` 反相后到两个视频 IP | 相同 | **一致** |
| PS FCLK reset | `FCLK_RESET0_N` → Processor System Reset | 相同 | **一致** |
| AXI 复位 | Processor System Reset 输出 `peripheral_aresetn` 到 VDMA、AXI Interconnect、控制外设和 Video In/Out | 相同；另含当前新增 `axi_smc` 复位 | **控制面一致，拓扑差异见下** |

## 8. AXI 控制面

| 项目 | 2020 参考 | 2025 当前 | 判定 |
|---|---|---|---|
| PS 控制口 | `processing_system7_0/M_AXI_GP0` | 相同 | **一致** |
| 控制互联 | `M_AXI_GP0` → `ps7_0_axi_periph/S00_AXI`；`ps7_0_axi_periph/M00_AXI` → `axi_vdma_0/S_AXI_LITE` | `M_AXI_GP0` → `axi_smc/S00_AXI`；`axi_smc/M00_AXI` → `axi_vdma_0/S_AXI_LITE` | **目的连接一致；当前用 SmartConnect 替代部分 AXI Interconnect，属于预期工具/结构差异** |
| 2020 额外控制外设 | `ps7_0_axi_periph` 还接 `axi_lite_0`、`axi_bram_ctrl_0` | 当前简化为显示链路所需控制 | **预期功能裁剪** |
| AXI HP0 | VDMA MM2S 读通道使用 | 相同 | **一致** |
| AXI HP1 | VDMA S2MM 写通道使用 | 相同 | **一致** |
| AXI 地址 | 本次不比较 | 本次不比较 | Vitis 阶段单独指定 |
| VDMA 中断 | VDMA 中断引脚未接入 BD 中断链 | VDMA 中断引脚未接入 BD 中断链 | **视频路径行为一致** |
| `IRQ_F2P` | 2020 CNN/后处理路径使用 | 当前无 | **预期功能裁剪；不属于 OV5640+HDMI 显示核心路径** |

## 9. 关键 IP 配置

### 9.1 Clocking Wizard

| 配置 | 2020 | 2025 | 判定 |
|---|---|---|---|
| IP 版本 | `clk_wiz 6.0` | `clk_wiz 6.0` | 一致 |
| 输入频率 | `PRIM_IN_FREQ=50` | `PRIM_IN_FREQ=100` | **预期基线差异** |
| CLKOUT1 | 25 MHz，BUFG | 25 MHz，BUFG | 一致 |
| CLKOUT2 | 125 MHz，BUFG | 125 MHz，BUFG | 一致 |
| CLKOUT3 | 24 MHz 请求，实际 24.03846 MHz，BUFG | 24 MHz 请求，实际 24.03846 MHz，BUFG | 一致 |
| CLKOUT4 | 50 MHz，BUFG | 50 MHz，BUFG | 一致 |

### 9.2 AXI VDMA

| 配置 | 2020 | 2025 | 判定 |
|---|---|---|---|
| IP 版本 | `axi_vdma 6.3` | `axi_vdma 6.3` | 一致 |
| MM2S | `C_INCLUDE_MM2S=1` | `C_INCLUDE_MM2S=1` | 一致 |
| S2MM | `C_INCLUDE_S2MM=1` | `C_INCLUDE_S2MM=1` | 一致 |
| Scatter Gather | `C_INCLUDE_SG=0` | `C_INCLUDE_SG=0` | 一致 |
| Internal Genlock | `C_INCLUDE_INTERNAL_GENLOCK=1` | `C_INCLUDE_INTERNAL_GENLOCK=1` | 一致 |
| MM2S Genlock Mode | `C_MM2S_GENLOCK_MODE=3` | `C_MM2S_GENLOCK_MODE=3` | 一致 |
| S2MM Genlock Mode | `C_S2MM_GENLOCK_MODE=2` | `C_S2MM_GENLOCK_MODE=2` | 一致 |
| Frame Stores | `C_NUM_FSTORES=3` | `C_NUM_FSTORES=3` | 一致 |
| AXI MM2S 数据宽度 | 64 bit | 64 bit | 一致 |
| AXI S2MM 数据宽度 | 64 bit | 64 bit | 一致 |
| MM2S AXIS 数据宽度 | 24 bit | 24 bit | 一致 |
| S2MM AXIS 数据宽度 | 24 bit | 24 bit | 一致 |
| MM2S Line Buffer | `C_MM2S_LINEBUFFER_DEPTH=1024` | `C_MM2S_LINEBUFFER_DEPTH=1024` | 一致 |
| S2MM Line Buffer | `C_S2MM_LINEBUFFER_DEPTH=1024` | 当前工程实际为 `C_S2MM_LINEBUFFER_DEPTH=512` | **唯一关键 IP 配置差异；不阻断功能，建议板测稳定后如需完全对齐再改回 1024** |
| Max Burst | MM2S/S2MM 均为 8 | MM2S/S2MM 均为 8 | 一致 |
| Flush on FSYNC | 1 | 1 | 一致 |
| Vertical Flip | 0 | 0 | 一致 |

### 9.3 Video In to AXI4-Stream

| 配置 | 2020 | 2025 | 判定 |
|---|---|---|---|
| IP 版本 | `v_vid_in_axi4s 4.0` | `v_vid_in_axi4s 5.0` | **Vivado/IP 版本差异，非错误** |
| Pixels per clock | 1 | 1 | 一致 |
| AXIS Video Format | 2 | 2 | 一致 |
| Component data width | 8 bit | 8 bit | 一致 |
| Async clock | 1 | 1 | 一致 |
| FIFO address width | 13 | 13 | 一致 |
| Pixel drop | 0 | 0 | 一致 |

### 9.4 AXI4-Stream to Video Out

| 配置 | 2020 | 2025 | 判定 |
|---|---|---|---|
| IP 版本 | `v_axi4s_vid_out 4.0` | `v_axi4s_vid_out 4.0` | 一致 |
| Pixels per clock | 1 | 1 | 一致 |
| AXIS Video Format | 2 | 2 | 一致 |
| Component data width | 8 bit | 8 bit | 一致 |
| Async clock | 1 | 1 | 一致 |
| FIFO address width | 13 | 13 | 一致 |
| VTG master/slave | 0 | 0 | 一致 |
| Hysteresis level | 12 | 12 | 一致 |
| Sync lock threshold | 4 | 4 | 一致 |

### 9.5 Video Timing Controller

| 配置 | 2020 | 2025 | 判定 |
|---|---|---|---|
| IP 版本 | `v_tc 6.2` | `v_tc 6.2` | 一致 |
| Video mode | 480p | 480p | 一致 |
| H active | 640 | 640 | 一致 |
| H total | 800 | 800 | 一致 |
| HSYNC end | 752 | 752 | 一致 |
| V active | 480 | 480 | 一致 |
| V total | 525 | 525 | 一致 |
| VSYNC start/end | 489 / 491 | 489 / 491 | 一致 |
| HSYNC polarity | High | High | 一致 |
| VSYNC polarity | High | High | 一致 |
| Video format | RGB | RGB | 一致 |
| Generation | true | true | 一致 |
| Detection | false | false | 一致 |

## 10. 需要单独理解的显示边界差异

### 10.1 旧 TMDS FPGA 直驱 vs 新 ADV7511

这是有意替换，不是连线错误。

- 2020：`HDMI_top` 接收 25 MHz 像素时钟、125 MHz 五倍时钟和 RGB 分量，直接输出 TMDS 差分对。
- 2025：`hdmi_out_adv7511` 接收 25 MHz 像素时钟和 24 位 RGB888，内部转换并输出 ADV7511 所需并行接口与 I2C 配置。
- 因此 2025 不需要把 `pclk_x5` 接入 HDMI 模块，也不需要复制 TMDS 差分端口。

### 10.2 `pix_frame_display/rom_data` 来源不同

`pix_frame_display` 模块源码两侧 SHA256 相同，但 BD 输入来源不同：

- 2020：`rom_ctrl_0/rom_data_out` → `pix_frame_display_0/rom_data`。
- 2025：`xlconstant_0/dout` 同时接到 `v_axi4s_vid_out` 使能和 `pix_frame_display_0/rom_data`，等效 `rom_data=0`。

该模块源码中 `rom_valid` 对应右侧局部区域；当 `rom_data=0` 时该区域会显示黑色，而不是旧工程可能显示的 ROM 图案。  
这不影响 OV5640 视频主路径，但属于可见显示效果差异。当前工程裁剪了旧工程的 ROM/OSD 相关功能时，这是预期；如果希望完全复现 2020 显示效果，需要恢复对应 ROM 图案来源。

## 11. 最终结论

### 核心链路判定

| 路径 | 判定 |
|---|---|
| OV5640 引脚到 `cam_captrue_data` | **一致** |
| `cam_captrue_data` 到 `v_vid_in_axi4s` | **一致** |
| `v_vid_in_axi4s` 到 VDMA S2MM | **一致** |
| VDMA S2MM 到 Zynq HP1 | **一致** |
| Zynq HP0 到 VDMA MM2S | **一致** |
| VDMA MM2S 到 `v_axi4s_vid_out` | **一致** |
| `v_tc` 到 `v_axi4s_vid_out` | **一致** |
| `v_axi4s_vid_out` 到 `pix_frame_display` | **一致** |
| `pix_frame_display` 前端视频信号到新 HDMI 模块 | **一致** |
| AXI GP0 控制到 VDMA | **目的连接一致，拓扑存在 SmartConnect 差异** |
| HP0/HP1 选择 | **一致** |
| Clocking Wizard 四路输出配置 | **输出配置一致，输入频率差异为工程基线差异** |
| VTC 480p 配置 | **一致** |

### 需要留意的差异

1. `C_S2MM_LINEBUFFER_DEPTH`：2020 为 1024，2025 当前生成结果为 512。  
   - 不建议在板测前盲目修改；当前实现/比特流已通过。  
   - 如果后续出现写入侧异常或想完全对齐 2020，可将该值改回 1024 后重新跑实现。

2. `rom_data` 接法：2020 来自 ROM 控制器，2025 当前接常量 0。  
   - 视频主链路不受影响。  
   - 但屏幕右侧局部 OSD/图案效果会不同。

3. Zynq 器件、外部时钟、PS FCLK0 频率不同。  
   - 这是两套工程基线差异，不判定为错误。

4. 新 HDMI 模块没有 `pclk_x5` 输入，也没有 TMDS 差分输出。  
   - 这是 ADV7511 并口方案替代 FPGA 直驱 TMDS 的预期架构变化。

## 12. 后续验证建议

1. 使用当前已通过的 `display_test_wrapper.bit` 先做板级验证。
2. Vitis 中按当前硬件导出结果重新指定 VDMA 基地址和寄存器配置。
3. 板测顺序建议：
   - 确认 PS 初始化和 UART 正常；
   - 确认 Clocking Wizard `locked`；
   - 确认 OV5640 SCCB 配置完成 `sccb_cfg_done`；
   - 先只使能 VDMA S2MM，确认 DDR 写入；
   - 再使能 VDMA MM2S，确认 HDMI 输出；
   - 最后观察显示器是否有撕裂、偏色、行抖动或无同步。
4. 如板测确认显示稳定，再决定是否把 `C_S2MM_LINEBUFFER_DEPTH` 从 512 调回 1024 以完全对齐 2020 工程。
