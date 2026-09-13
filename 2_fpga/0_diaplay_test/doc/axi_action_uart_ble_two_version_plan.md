# PS→AXI-Lite→PL 动作 LED／UART／蓝牙两版实施方案

状态：`V1_IMPLEMENTATION_AUTHORIZED`（用户已确认两项默认设置，开始第一版）  
日期：2026-09-13  
执行门：第一版按仿真、构建、板测顺序推进并报告。第二版待第一版验收后另行推进。

2026-09-13 用户确认：左右暂不判断；连续三次定义为三个不同新视频帧的有效推理，
每次置信度 >=0.75、同一标签才下发一次。界面重复刷新同一帧不计数，中断重新计数，
稳定动作不重复发送；连续一秒无有效结果发送一次 CLEAR。

## 1. 已确认目标与当前工程事实

最终控制主链路必须使用 AXI-Lite：

```text
PL OV5640 -> PS VDMA/UDP -> PC 动作识别
                              |
                              v
                    以太网动作命令/确认
                              |
                              v
PYNQ/PS 动作代理 -> AXI-Lite CSR -> PL 动作执行器 -> LED
                                             |
                                             +-> COM4 UART TX
                                             `-> 板载 MLT-BT05 UART TX（第二版）
```

不能采用 `PC COM4 -> PL UART RX -> LED` 作为动作主通道，因为这会绕过已经开发和验证
的 AXI-Lite 寄存器接口。

当前可复用事实：

- 主工程是 `2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/`
  `display_test_zynq7020_school.xpr`，BD 名称为 `display_test`；
- 独立 AXI 工程位于 `2_fpga/2_axi_lite_test`，BD 名称为 `AXI_LITE_test`；
- PS GP0 当前给控制寄存器保留 `0x43C00000/4 KiB`，VDMA 保持
  `0x43000000/64 KiB`；
- 主视频、通用 AXI 寄存器、透明蓝牙桥已经有一次共存板测历史 PASS，但该版本没有
  实现动作寄存器语义，不能作为本方案验收结果；
- COM4 对应 PL USB-UART，引脚为 `PL_RS232_TX=A17`、`PL_RS232_RX=A16`，已验证
  9600/8N1；
- 板载蓝牙模块是 MLT-BT05，PL 到模块输入为 `BT_RX=AA13`，模块到 PL 为
  `BT_TX=Y13`，另有 `FPGA_BT_3V3=U14`、`BT_RESET_N=H15`；
- 现有 PC 蓝牙上位机通过 BLE GATT `FFE1` 收发/订阅通知，不是 Windows SPP 虚拟
  COM 口；既有证据已验证 BLE 与 COM4 透明传输的逐字节一致性；
- LED0/V4 已被摄像头 `sccb_cfg_done` 占用，动作只使用 LED1..LED7。

## 2. 对“串口是否冲突”的结论

硬件上不冲突。COM4 UART 和蓝牙模块 UART 是两组不同 FPGA 管脚：A16/A17 与
Y13/AA13，可以同时存在。

当前透明桥不能原样保留。它在 READY 状态直接把 `PL_RS232_RX` 转发到 `BT_RX`，而
新动作模块也需要驱动 `BT_RX`；若两者同时实例化会产生同一输出的逻辑所有权冲突。
第二版必须删除主 BD 中的 `ble_uart_bridge_0`，由动作输出模块独占这些输出。

推荐不实例化两个各自计时的发送器，而是让一个 UART TX 串行波形扇出到两个独立输出：

```text
                         +-> PL_RS232_TX/A17 -> COM4
action_uart_serial ------|
                         `-> BT_RX/AA13       -> MLT-BT05 -> BLE FFE1
```

这样两路源字节和位时序天然完全相同，也不存在双发送器启动先后差异。蓝牙上电/复位未
完成时 `BT_RX` 保持 UART 空闲高电平；第二版在 `BT_READY` 之前不接受动作 START。

主机资源也不冲突：COM4 由一个串口捕获进程独占；蓝牙上位机使用 BLE GATT，不占用
COM4。MLT-BT05 同一时刻只允许一个无线中心连接，因此板测时由 PC 上位机连接，未来
接机械臂控制器时则由控制器连接，两者不能同时占用蓝牙链路。

## 3. 动作语义和映射

协议层为七个模型类别保留稳定编码，0 表示无有效动作/清灯：

| 模型索引 | 标签 | ACTION | LED | 管脚 |
|---:|---|---:|---|---|
| - | CLEAR | `0x00` | 全灭 | - |
| 0 | Down | `0x01` | LED1 | U6 |
| 1 | Left | `0x02` | LED2 | U5 |
| 2 | Right | `0x03` | LED3 | V7 |
| 3 | Stop | `0x04` | LED4 | W7 |
| 4 | Thumbs Down | `0x05` | LED5 | W6 |
| 5 | Thumbs up | `0x06` | LED6 | W5 |
| 6 | Up | `0x07` | LED7 | U7 |

映射采用 `ACTION=model_index+1`，避免复位值 0 被解释为真实动作。LED one-hot 在
PL 接受 START 时更新，并保持到下一条有效动作；复位和 CLEAR 全灭动作 LED。

当前 PC 程序的真实限制必须保留：`gesture_viewer_core.py` 目前把 Left/Right 判为
`UNKNOWN`，不作为有效动作。因此：

- RTL/AXI/串口注入测试覆盖完整 0..7；
- 在线模型版默认只允许当前已启用的 Down、Stop、Thumbs Down、Thumbs up、Up；
- Left/Right 编码保留，但在方向校准验收前不得由模型自动下发。

识别到单一、允许的稳定标签后才下发。建议初值为连续 3 个推理结果相同且置信度不低于
0.75；重复稳定标签不重复触发。视频 stale、冲突或连续 1 秒无有效标签时仅发送一次
CLEAR。阈值和连续帧数作为 host 配置保存，不能隐藏在 RTL 中。

## 4. PC 到 PS 的动作回传

当前模型运行在 PC，而 AXI 主机在 PYNQ/PS，因此除视频的 PS→PC UDP 外，还必须增加
PC→PS 动作回传；COM4 不能承担该功能。

建议复用独立有线网口，在 UDP 5001 上使用固定长度二进制命令，视频继续使用 UDP
5000：

### 4.1 动作命令（16 bytes）

```text
0..3  MAGIC='ACTN'   4 VERSION=1   5 TYPE=1
6 ACTION             7 FLAGS=0     8..11 SEQ32, big-endian
12..15 CRC32 of bytes 0..11
```

### 4.2 PS 完成确认（20 bytes）

```text
0..3  MAGIC='ACTA'   4 VERSION=1   5 STATUS
6 ACTION             7 RESERVED=0  8..11 SEQ32, big-endian
12..15 DONE_SEQ32, big-endian       16..19 CRC32 of bytes 0..15
```

PS 动作代理只接受配置的 PC 地址、合法 CRC、ACTION 0..7 和单调非零序号。它把相同
`SEQ32/ACTION` 写入 AXI，等待 PL DONE，核对 DONE_SEQ/LAST_ACTION 后回复。网络超时
时，PC 不得换新序号盲发；可重发完全相同的序号，PS 根据 AXI ACCEPT/DONE 状态返回
缓存结果而不再次触发 PL。任意不确定状态均停止自动动作并记录证据。

动作代理由新的 `camera_action_v1.py` 复用 `camera.py` 的 VDMA 类，在同一服务进程
加载一次匹配 BIT/HWH，VDMA 与动作 CSR 各持有独立 MMIO。动作 socket 由独立工作线程
有界轮询，避免阻塞视频循环；PC 超时默认停止自动命令，PS 支持相同已完成命令去重；
所有 CSR 写读仍通过现有 ARM C 层的内存屏障。物理基地址从 HWH/IP 字典获取，Python
不写死基地址，只验证其与发布合同一致。

## 5. AXI 动作寄存器 ABI

动作控制使用独立 IP 身份，不能继续伪装成“输入按位取反”的测试执行器：

| 偏移 | 名称 | 权限 | 语义 |
|---:|---|---|---|
| `0x00` | `IP_ID` | RO | `0x4143544C`，ASCII `ACTL` |
| `0x04` | `ABI_VERSION` | RO | `0x00010000` |
| `0x08` | `CAPS` | RO | CSR/UART/LED/BLE 能力位；两版值不同 |
| `0x0C` | `SCRATCH` | RW | WSTRB 字节级读写验证 |
| `0x10` | `ACTION_CODE` | RW | 0..7，完整字写 |
| `0x14` | `CMD_SEQ` | RW | 非零递增 32 bit 序号，完整字写 |
| `0x18` | `CONTROL` | WO | 1=START，2=ACK，完整字写 |
| `0x1C` | `STATUS` | RO | READY/BUSY/DONE/BT_READY/UART_BUSY |
| `0x20` | `ACCEPT_SEQ` | RO | 最近接受的完整序号 |
| `0x24` | `DONE_SEQ` | RO | 最近完成的完整序号 |
| `0x28` | `LAST_ACTION` | RO | 最近完成的动作码 |
| `0x2C` | `ERROR_CODE` | RO | 执行错误码 |
| `0x30` | `EXEC_COUNT` | RO | 完成计数 |
| `0x34` | `LAST_FRAME` | RO | `{8'h00, CRC8, SEQ8, ACTION}` |
| `0x38` | `OUTPUT_STATUS` | RO | COM4/蓝牙电源、复位、ready 和 TX 状态 |
| `0x3C` | `FRAME_COUNT` | RO | 完整 UART 帧计数 |

START 锁存 `ACTION_CODE/CMD_SEQ`，更新 LED 并启动输出。BUSY 或旧 DONE 未 ACK 时拒绝
新 START。DONE 只在完整 7 字节 UART 帧结束后置位；第二版同一串行波形已同时输出到
COM4 和蓝牙引脚，因此不需要等待两个独立发送器。DONE 只证明 PL 已完成管脚发送，
不能证明无线接收端已经收到；后者必须由 BLE 上位机证据确认。

## 6. PL UART 动作帧

两版均固定为 9600 baud、8N1、无流控，发送：

```text
Byte0   Byte1   Byte2   Byte3    Byte4   Byte5   Byte6
0xA5    0x5A    SEQ8    ACTION   CRC8    0x0D    0x0A
```

`ACTION` 位于 Byte3，是唯一承载动作语义的字段；其他字段只负责封装。`SEQ8` 等于
`CMD_SEQ[7:0]`。CRC 使用 CRC-8/ATM，多项式 0x07、初值 0、MSB-first、无反射、无
最终异或，覆盖 `A5 5A SEQ8 ACTION`。

## 7. 第一版：AXI→LED + COM4 动作帧

### 7.1 PL 模块

```text
axi_lite_slave                 已验证五通道适配，继续复用
axi_action_reg_bank            动作 ABI、访问权限、序号与状态
action_uart_tx                 9600/8N1 字节发送器
action_command_executor        LED 映射、CRC、7 字节帧调度、DONE
axi_action_control_top         可独立仿真的动作控制核心
video_axi_action_uart_top      50 MHz、可直接拖入 BD 的 Verilog 顶层
```

所有新 FSM 按项目规则使用严格三段式，复位状态名为 `STATE_IDLE`。BD 保留 PS、VDMA、
摄像头和 HDMI；把旧通用 AXI 测试 cell 替换为动作控制 cell，地址仍为 0x43C00000；
删除透明蓝牙桥和全部 BT 外部端口，只新增 `PL_RS232_TX` 与 `ACTION_LED[6:0]`。

### 7.2 软件

- PYNQ：动作 ABI 驱动、PC→PS 动作代理、序号/超时/ACK、事件日志；
- PC 模型：稳定性门、动作映射、UDP 命令和确认，不直接打开 COM4 发送；
- PC 验证：COM4 只读捕获器，以 Windows `SerialPort` 实现，不向项目模型环境新增未经
  锁定的 pyserial 依赖；按帧解析并与 PC 命令、PS ACK 做关联。

### 7.3 验收

1. 独立 RTL 自检：AW/W 三种顺序、读写并行、B/R 反压、16 种 WSTRB、权限/地址错误、
   0..7 动作、重复序号、BUSY、ACK、CRC、UART 位宽与复位中断；
2. 独立 Vivado `AXI_LITE_test` 动作配置构建：无黑盒/DRC Error，时序通过；
3. 主 `display_test` BD 构建：视频地址不变，动作 CSR 合同、A17 与七路 LED 约束正确；
4. 板上注入测试：每个动作至少 20 次，1000 条总命令，AXI 序号/计数/帧逐条一致；
5. COM4：捕获全部 7 字节帧，头尾、CRC、SEQ8、ACTION 零错误；
6. LED：用户确认 0..7 的全灭/one-hot 顺序，V4 摄像头灯不受影响；
7. 共存：HDMI 动态、UDP 400 帧零协议错误、动作命令和 COM4 同时运行；
8. 真实识别：只对已启用类别执行，保存图像帧号、置信度、网络命令、AXI DONE 和 UART
   帧的同序号证据。

第一版通过后单独发布 `display_test_axi_action_uart.bit/.hwh/.xsa` 及哈希，不用后续
第二版的结果覆盖第一版证据。

## 8. 第二版：第一版 + 蓝牙动作镜像

第二版只在第一版完整 PASS 后开始。AXI、动作映射和 COM4 帧保持不变，增加：

```text
bluetooth_power_reset_fsm      100 ms 上电 + 1 s 复位释放等待
action_output_router           同一 UART 波形扇出至 A17 与 AA13
video_axi_action_ble_top       暴露 BT_RX/电源/复位，BT_TX 仅保留未来输入
```

主 BD 不再存在透明桥。`PL_RS232_RX` 不用于动作；`BT_TX` 在本版不参与完成条件，可不
暴露或只作为保留输入。`BT_READY` 仅表示 PL 的上电时序完成，不能表示 BLE 已连接。

蓝牙验证使用现有 `3_host/ble_console` 的 MLT-BT05 未配对直连模式，订阅 FFE1 通知并
记录原始 HEX。因为 BLE 通知可能分片或合并，验证工具按字节流搜索帧头和帧尾并校验
CRC，不能假定“一条通知正好等于一帧”。同一批动作同时得到：

- PC 模型/注入器期望帧；
- PS AXI ACCEPT/DONE；
- COM4 原始帧；
- BLE FFE1 RX NOTIFY 原始字节。

四方按完整 SEQ32、低 8 位 SEQ、ACTION、CRC 和顺序比对。至少 1000 条注入命令、
每类动作至少 20 条，要求 COM4 和 BLE 均无缺帧、重帧、乱序或 CRC 错误；再做真实
识别子集验证。HDMI/UDP/VDMA 同样必须共存通过。

板测时 PC 蓝牙上位机就是无线接收端，因此能证明“MLT-BT05 已把 PL UART 字节通过
BLE 发到上位机且内容正确”。它不能证明未来机械臂已经执行。未来接机械臂若要求可靠
闭环，应另立第三阶段：定义控制器 ACK/错误/急停语义，使用 `BT_TX` 接收并由 PL/PS
关联确认；本两版不提前声称机械臂闭环。

第二版独立发布 `display_test_axi_action_ble.bit/.hwh/.xsa`，保留第一版包用于摄像头、
AXI、LED 和 COM4 的快速故障隔离。

## 9. 可复现工程与文件边界

| 路径 | 计划内容 |
|---|---|
| `2_fpga/2_axi_lite_test/doc` | 动作 ABI、帧格式、验证矩阵 |
| `2_fpga/2_axi_lite_test/rtl` | 可复用 AXI 动作核心、UART、蓝牙上电模块 |
| `2_fpga/2_axi_lite_test/sim` | 自检 TB、UART/CRC 参考模型、回归 Tcl |
| `2_fpga/2_axi_lite_test/proj` | 独立 `AXI_LITE_test` 的可重建 Tcl 与构建入口 |
| `2_fpga/2_axi_lite_test/pynq` | 动作 CSR 驱动与软件单测 |
| `2_fpga/0_diaplay_test/rtl/control` | 两个主 BD Verilog 包装顶层 |
| `2_fpga/0_diaplay_test/proj` | v1/v2 确定性 BD 集成与构建 Tcl |
| `2_fpga/0_diaplay_test/pynq` | 视频服务内动作代理、发布审计 |
| `3_host/model_env` | 稳定动作决策与 UDP 命令发送 |
| `3_host/ble_console` | 第二版 BLE 字节流捕获/导出 |
| `4_metrics/logs/<run>` | 仿真、构建、板测原始证据，失败永久保留 |
| `7_logs/2026-09-13` | 当日计划、执行、验证和交接索引 |

每版构建前保存源文件哈希、BD Tcl、地址表和约束表；构建后记录 utilization、timing、
DRC、blackbox、BIT/HWH/XSA SHA-256。上板仍使用现有 SD/PYNQ 系统，只替换匹配的
BIT/HWH；每次测试后恢复原服务并由用户确认 HDMI。

## 10. 审核后执行顺序与停止条件

1. 用户审核动作映射、稳定阈值、两种帧和 v1/v2 范围；
2. 固化文档与 Python 参考编解码器；
3. 实现并通过 v1 独立 RTL/软件仿真，报告后暂停；
4. 建立 v1 BD、综合实现、生成位流，报告后暂停；
5. 经用户确认测试窗口后做 v1 板测和 HDMI/LED 人工确认；
6. v1 完整 PASS 后实现并仿真 v2；
7. 建立 v2 BD、构建、COM4+BLE 双捕获板测和人工确认；
8. 两版分别归档，再选择性提交个人分支 `codex/full/pipidandan-superman`。

任一门失败立即保留失败证据并停止推进，不用重试成功覆盖失败；地址/HWH 不匹配、
UART/CRC 错误、蓝牙未连、AXI 状态不确定、视频中断或 LED 映射不符均是硬停止条件。

## 11. 当前未验收草稿

在用户发出“先审核方案再执行”的指令之前，本轮已新增以下初稿：

- `2_fpga/2_axi_lite_test/doc/action_control_abi.md`；
- `2_fpga/2_axi_lite_test/rtl/action_uart_tx.v`；
- `2_fpga/2_axi_lite_test/rtl/action_command_executor.v`；
- `2_fpga/2_axi_lite_test/rtl/axi_action_reg_bank.v`。

以上为审核前的历史草稿清单。用户批准第一版后已补齐控制顶层、扩展寄存器、PC/PYNQ
软件并完成 RTL 自检；当前进度以 `action_v1_status.md` 和当日验证摘要为准。
