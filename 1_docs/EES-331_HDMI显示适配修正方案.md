# EES-331 HDMI 显示适配修正方案

| 项目 | 内容 |
|---|---|
| 文档日期 | 2026-09-03 |
| 目标板卡 | 依元素 EES-331（xc7z020clg484-1） |
| 适用工程 | `E:/competition/2_fpga/0_diaplay_test/proj/display_test_zynq7020_school`（camera → VDMA → DDR → HDMI 显示链路） |
| 文档状态 | 方案评审稿 |
| 证据来源 | 《EES-331 User Guide》第 2/5/20/21/23 节及第 31-32 页原理图、板卡 Bank 电压表 |

---

## 1. 问题背景：当前遇到的 HDMI 显示适配问题

### 1.1 现象

当前工程中的 HDMI 输出模块 `HDMI_top` 采用 **FPGA 直驱 TMDS** 架构（8b/10b 编码 + 10:1 串化 + 差分输出，直接驱动 HDMI 座的 4 对差分引脚）。该架构在原开发板（HDMI 座直连 FPGA 引脚的板卡）上可正常点亮显示器。

将工程迁移到 EES-331 板卡后，该模块**物理上无法工作**。

### 1.2 根因（来自原理图的实锤）

EES-331 的 HDMI 座（U32）**不与 FPGA 直接相连**：

```
HDMI 座 DATA2±/DATA1±/DATA0±/CLOCK±
        │（经 ACM2012H-900 共模电感）
        ▼
ADV7511 的 TX2±/TX1±/TX0±/TXC±（TMDS 输出侧）
```

- FPGA 与 HDMI 座之间**没有任何直接连线**，FPGA 侧只连接到 ADV7511 的**并行视频输入总线**和 I2C 配置接口
- 因此 `HDMI_top` 的 `TMDS_clk_p/n`、`TMDS_data_p/n[2:0]`、`hdmi_en` 端口在新板上**无引脚可约束**，不是修改 XDC 能解决的问题
- 即便物理移除 ADV7511 芯片，HDMI 座走线仍只连到该芯片焊盘，不会产生 FPGA → 连接器的新通路

### 1.3 结论

**必须将显示末级从"TMDS 直驱"改造为"ADV7511 并行总线驱动"**：FPGA 负责把视频整理为 ADV7511 要求的并行格式并完成芯片初始化，TMDS 编码与串化由 ADV7511 芯片内部完成。

---

## 2. 原有 HDMI 模块功能与数据流

### 2.1 模块端口（迁移前）

```verilog
module HDMI_top(
    input  wire        pix_clk,      // 像素时钟
    input  wire        pix_clk_x5,   // 5 倍频串化时钟
    input  wire        rst_n,
    input  wire        h_sync,
    input  wire        v_sync,
    input  wire [7:0]  red_data,
    input  wire [7:0]  green_data,
    input  wire [7:0]  blue_data,
    input  wire        de,           // 数据有效
    output wire        TMDS_clk_p,   // TMDS 时钟差分对
    output wire        TMDS_clk_n,
    output wire [2:0]  TMDS_data_p,  // 3 对 TMDS 数据差分
    output wire [2:0]  TMDS_data_n,
    output wire        hdmi_en
);
```

### 2.2 内部数据流（三级流水）

```
RGB888 + DE/HS/VS (pix_clk 域)
   │
   ▼
① TMDS_encode：对 R/G/B 三通道分别做 8b/10b TMDS 编码（视频期编码像素，消隐期编码 HSYNC/VSYNC 控制字符）；时钟通道固定发送控制字符序列
   │  （10bit × 4 通道，pix_clk 域）
   ▼
② par_to_ser：10:1 并转串，使用 pix_clk_x5 + OSERDESE2 双沿技术得到 10 倍速率位流
   │  （pix_clk_x5 域，单端）
   ▼
③ ser_to_diff：OBUFDS 将单端位流转为 TMDS 差分对
   │
   ▼
TMDS_clk_p/n（像素时钟，未编码的 1x 时钟）
TMDS_data_p/n[2:0]（D2=红、D1=绿、D0=蓝+同步）
```

### 2.3 该数据流的本质

显示器端的 HDMI 接收器要求收到的是 **8b/10b 编码后的 10 倍率串行 TMDS 流**。原方案中"编码 + 串化"这两步全部由 FPGA 逻辑承担，因此需要 5 倍频时钟和 OSERDESE2 资源。

---

## 3. 目标方案：EES-331 上应遵循的操作流程与数据流

### 3.1 目标架构总览

```
FPGA（保留前端）                          ADV7511（芯片内部完成）           显示器
┌────────────────────────────┐   16位并行  ┌──────────────────────┐
│ 摄像头→VDMA→DDR→v_tc 时序   │──YCbCr422──▶│ 8b/10b 编码           │──TMDS──▶ HDMI 座
│ →RGB888                    │   CLK/DE    │ →PLL 串化             │         →显示器
│ →rgb2ycbcr422 转换打包      │   HS/VS     │ →DDC 直通/HPD         │
│ →输出寄存对齐               │──I2C 配置──▶│ (寄存器初始化后才开始) │
└────────────────────────────┘  SCL/SDA   └──────────────────────┘
```

**核心认知：TMDS 编码与串化并没有消失，只是从 FPGA 逻辑搬进了 ADV7511 芯片内部。** 手册引脚表暴露的"PL 端 HDMI 引脚"全部是 ADV7511 的 FPGA 侧接口；芯片与 HDMI 座之间的显示器侧接口不经过 FPGA、无需约束。

### 3.2 ADV7511 必须接收的信号清单（含 EES-331 引脚）

| 信号 | 方向 | FPGA 引脚 | 说明 |
|---|---|---|---|
| 视频数据 `HDMI_D[15:0]` | FPGA→ADV7511 | R7,V10,V9,V8,W8,W11,W10,V12,W12,U12,U11,U10,U9,AA12,AB12,AA11 | 4:2:2 16-bit 格式：`[15:8]`=Y（每像素），`[7:0]`=Cb/Cr 逐拍交替 |
| 像素时钟 `HDMI_CLK` | FPGA→ADV7511 | Y8 | 与数据同域同相，720P60=74.25MHz / 1080P60=148.5MHz |
| 场同步 `HDMI_VSYNC` | FPGA→ADV7511 | Y11 | 与数据流对齐 |
| 行同步 `HDMI_HSYNC` | FPGA→ADV7511 | Y10 | 与数据流对齐 |
| 数据有效 `HDMI_DE` | FPGA→ADV7511 | AA9 | 窗口有效像素 |
| I2C `IIC_SCL_HDMI` | FPGA→ADV7511 | AB10 | 寄存器配置时钟 |
| I2C `IIC_SDA_HDMI` | 双向 | AB9 | 寄存器配置数据（7 位地址 `7'h39`，写 `0x72`/读 `0x73`） |
| 中断 `HDMI_INT`（可选） | ADV7511→FPGA | AB11 | 监视芯片状态（可暂不使用） |

### 3.3 最终 HDMI 座输出信号（由 ADV7511 产生，非 FPGA）

| 座上信号 | 内容 |
|---|---|
| 3 对 TMDS 数据差分 | 8b/10b 编码后的视频/控制字符流（HS/VS 嵌入蓝信道控制周期） |
| 1 对 TMDS 时钟差分 | 像素时钟（=FPGA 送入的 pix_clk 频率） |
| DDC（SCL/SDA） | 显示器 EDID 读取通道，ADV7511 直通 |
| HPD / +5V / CEC / HEAC | 热插拔检测与供电，板上已固定处理 |

### 3.4 新显示模块端口定义（替代 HDMI_top）

```verilog
module hdmi_out_adv7511 (
    input  wire        pix_clk,      // 74.25M(720P60) 或 148.5M(1080P60)，不再需要 x5
    input  wire        rst_n,        // 低有效（与 S1 按键极性一致）
    // 原流水线输入：保持不变
    input  wire [23:0] rgb888,
    input  wire        de,
    input  wire        h_sync,
    input  wire        v_sync,
    // 新输出：接 EES-331 引脚
    output wire [15:0] hdmi_data,    // 16 位 YCbCr422 总线
    output wire        hdmi_clk,     // = pix_clk 直出
    output wire        hdmi_hsync,
    output wire        hdmi_vsync,
    output wire        hdmi_de,
    output wire        hdmi_scl,     // I2C 配置
    inout  wire        hdmi_sda,
    input  wire        hdmi_int
);
```

### 3.5 模块内部逻辑（三个子模块）

#### ① rgb2ycbcr422（色彩转换 + 打包）

- BT.709 系数（720P/1080P 推荐）：
  - `Y  =  0.1836R + 0.6142G + 0.0620B + 16`
  - `Cb = -0.1006R - 0.3386G + 0.4392B + 128`
  - `Cr =  0.4392R - 0.3986G - 0.0403B + 128`
- 乘法用"常数移位相加"实现；3~4 级流水，延迟用 `de/hs/vs` 同步打拍补偿
- 422 打包：每个像素时钟输出 `{Y, C}`，C 通道按奇偶像素交替输出 Cb/Cr（ADV7511 寄存器需配置为对应的 422-16bit 输入风格）

#### ② adv7511_i2c_init（寄存器初始化，必做）

- ADV7511 上电默认处于掉电状态，**不初始化就没有任何输出**（黑屏第一嫌疑）
- 流程：上电延时（等电源/HPD 稳定，≥100ms）→ I2C 100kHz 写寄存器表 → 结束置 done 标志
- 关键寄存器组（初始化表需按此定制，完整序列实施时提供）：
  - `0x41[6]=0`：芯片上电
  - `0x15/0x16`：输入风格 = 4:2:2、16-bit、上升沿锁存
  - `0x18/0xCB/0xFB` 等：时钟与 PLL
  - `0xAF`：HDMI 输出模式
  - `0x98/0x9C/0x9D`：固定推荐值
  - AVI InfoFrame（`0x55~0x57` 区域）按分辨率填写
- I2C 主机可用简单 GPIO 位摆 FSM（SCL 手动翻转，SDA 开漏），不必例化 AXI_IIC

#### ③ 输出对齐

- `hdmi_data/de/hs/vs` 在 `pix_clk` 打一拍寄存后输出，保证与 `hdmi_clk`（=pix_clk）边沿建立保持裕量
- `hdmi_clk` 直接由 pix_clk 经 ODDR 或同相输出（Y8）

### 3.6 约束（XDC）要点

- 全部新 HDMI 引脚 `IOSTANDARD = LVCMOS33`（EES-331 PL 侧 Bank0/13/33/34/35 均为 3.3V）
- `TMDS_*`、`hdmi_en` 相关约束全部删除
- 引脚分配：见 3.2 节表格，或手册"PL 端 HDMI 模块管脚约束表"

---

## 4. 详细修正计划（分步实施与验证门）

| 步骤 | 内容 | 产出/验证门 |
|---|---|---|
| S0 决策 | 确认目标分辨率（建议 720P60 起步，74.25MHz 时钟裕量大）与色彩系数（BT.709） | 分辨率/时钟参数冻结 |
| S1 约束 | 新建 XDC：删除全部 TMDS/hdmi_en 条目，加入 3.2 节引脚；时钟 M19（100MHz PL 晶振）、复位 L18、LED/按键一并按手册补全 | 综合 0 引脚错误 |
| S2 转换模块 | 编写 `rgb2ycbcr422`（含打包），纯仿真对比 MATLAB/Python 定点模型，误差 ≤1 LSB | 仿真 PASS |
| S3 I2C 初始化 | 编写 `adv7511_i2c_init`（GPIO 位摆 I2C + 初始化表），仿真抓 SCL/SDA 波形核对地址 0x72 与寄存器序列 | 仿真波形 PASS |
| S4 工程集成 | BD/RTL 替换 `HDMI_top` → `hdmi_out_adv7511`；删除 `pix_clk_x5` 时钟；v_tc/VDMA/摄像头链路不动；综合实现 | 时序 WNS≥0 |
| S5 板级调试 | 分层验证（见 5.2 排查表）：①VIO/ILA 确认 I2C 写序列完成 → ②量测 Y8 有像素时钟 → ③显示器点亮 → ④颜色条测试 → ⑤接摄像头全链路 | 显示器稳定出图 |

### 4.1 风险与预案

| 风险 | 影响 | 预案 |
|---|---|---|
| ADV7511 未初始化/初始化表错误 | 黑屏 | 先跑只输出彩条的纯净工程，隔离前端问题；ILA 抓 I2C 确认 ACK |
| Cb/Cr 顺序接反 | 颜色错乱（紫/绿） | 色彩条测试快速定位，调换打包顺序即可 |
| Y/C 对齐差一拍 | 图像行错位/撕裂 | 仿真中固定检查 `de` 拉高首拍的数据 |
| 148.5MHz 时序紧 | 1080P 综合不过 | 先 720P 点亮，再提 1080P |
| HPD 时序 | 偶发不识别 | 遵循初始化延时 ≥100ms，监测 HDMI_INT |

---

## 5. 其余关键点补充

### 5.1 PS7 配置与本板适配（重要遗留项）

- **MIO Bank1 电压**：EES-331 手册明确 MIO Bank0=3.3V、**Bank1=1.8V**；当前 `display_test` 工程 PS7 中 Bank1 被配置为 3.3V（沿用原板预置）。UART1（MIO48/49）在 Bank1 上，**正式跑 EES-331 前应改为 1.8V**。
- **PL 时钟**：EES-331 PL 外部晶振为 **100MHz，引脚 M19**；原工程若使用其他输入时钟频率/引脚，clk_wiz 参数需同步调整。
- **PL 复位按键 S1**：引脚 L18，外部 4.7kΩ 上拉，**按下为低**（低有效复位）；LED0~LED7（V4/U6/U5/V7/W7/W6/W5/U7）**高电平点亮**。板级调试指示灯可直接用。

### 5.2 板级调试排查表（黑屏时按序检查）

| 序 | 检查项 | 手段 |
|---|---|---|
| 1 | ADV7511 供电（PVDD/AVDD/DVDD/DVDD_3V3） | 万用表 |
| 2 | I2C 初始化是否完成、有无 ACK | ILA 抓 SCL/SDA 或 VIO 标志 |
| 3 | Y8 是否有像素时钟输出 | 示波器 |
| 4 | DE/HS/VS 与数据对齐 | ILA |
| 5 | 显示器 EDID/HPD | 换显示器/线缆交叉验证 |

### 5.3 设计便利性说明

- 删除 `pix_clk_x5` 后，时钟结构简化为单一 74.25/148.5MHz，clk_wiz 只需一个输出，时序压力显著降低
- `HDMI_INT` 初期可不接逻辑，留引脚即可；进阶再用于监测中断
- SPDIF（AA8/Y9）、CEC、HEAC 与视频显示无关，悬空即可
- 音频（ADAU1761）为独立 I2C/I2S 外设，与本 HDMI 通路无耦合，比赛仅显示可不做

### 5.4 不变量清单（迁移中不许动的部分）

摄像头 `cam_captrue_data` 输出极性（`vid_ce` 高有效直连）、VDMA↔S_AXI_HP0 通路、GP0 控制链、v_tc 时序参数——这些与 HDMI 物理层改造完全解耦，保持原样。

---

## 附：关键证据索引

| 证据 | 位置 |
|---|---|
| HDMI 座仅接 ADV7511（原理图） | User Guide 第 32 页（ADV7511 接线图 + HDMI 接口电路图） |
| "仅支持 16 位 YCbCr 422 数据输入" | User Guide 第 23 节原文 |
| I2C 地址 0111001（7'h39） | User Guide 第 32 页 ADV7511 接线图左上角标注 |
| PL Bank 电压全 3.3V / MIO Bank1 1.8V | User Guide "Zynq-7000 AP SoC Bank Voltages" 表 |
| PL 时钟 M19 100MHz、PS_CLK F7 33.333MHz | User Guide 第 5 节 |
| LED 高有效原理图 / S1 低电平按键 | User Guide 第 28-29 页 |
