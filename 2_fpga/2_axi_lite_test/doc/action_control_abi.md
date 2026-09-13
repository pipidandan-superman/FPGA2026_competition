# AXI-Lite 动作控制与 PL UART 输出协议

第一版执行已获用户批准。连续三次指三个不同新视频帧的推理结果；同一帧的界面刷新
不计数。各次置信度 >=0.75、动作同类才下发一次，左右类别暂不自动下发。

## 1. 数据路径

唯一有效的动作控制路径如下：

```text
PC 识别程序 -> PYNQ/PS -> AXI-Lite CSR -> PL 动作执行器
                                      |-> LED1..LED7
                                      `-> PL UART TX -> COM4
```

COM4 是 PL 动作结果的串口输出观察口，不是绕过 AXI-Lite 的 PS 到 PL 控制入口。
蓝牙透明回环保留在独立工程 `2_fpga/1_ble_test`，不接入本数据流。

## 2. 动作寄存器 ABI

数据宽度为 32 bit，地址窗口为 4 KiB，主工程基地址由 HWH 发现；当前 BD 约定为
`0x43C00000`。所有保留位写 0。

| 偏移 | 名称 | 权限 | 复位值与语义 |
|---:|---|---|---|
| `0x00` | `IP_ID` | RO | `0x4143544C`，ASCII `ACTL` |
| `0x04` | `ABI_VERSION` | RO | `0x00010000` |
| `0x08` | `CAPS` | RO | bit0=CSR，bit1=UART TX，bit2=七路动作 LED |
| `0x0C` | `SCRATCH` | RW | 0；支持任意 WSTRB，零 WSTRB 为无操作 |
| `0x10` | `ACTION_CODE` | RW | 0；必须完整字写，只接受 0..7 |
| `0x14` | `CMD_SEQ` | RW | 0；必须完整字写，BUSY/DONE 时禁止修改 |
| `0x18` | `CONTROL` | WO/读 0 | 1=`START`，2=`ACK`，必须完整字写 |
| `0x1C` | `STATUS` | RO | bit0=READY，bit1=BUSY，bit2=DONE，bit3=BT_READY（v1=0），bit4=UART_BUSY |
| `0x20` | `ACCEPT_SEQ` | RO | 最近接受的完整 32 bit 序号 |
| `0x24` | `DONE_SEQ` | RO | 最近完成的完整 32 bit 序号 |
| `0x28` | `LAST_ACTION` | RO | 最近完成的动作码，位于低 8 bit |
| `0x2C` | `ERROR_CODE` | RO | 执行器错误；正常为 0 |
| `0x30` | `EXEC_COUNT` | RO | 完成命令计数，32 bit 模运算 |
| `0x34` | `LAST_FRAME` | RO | 0；完成帧摘要 `{00, CRC8, SEQ8, ACTION}` |
| `0x38` | `OUTPUT_STATUS` | RO | bit0=COM4存在（1），bit4=UART_BUSY；其余位v1为0 |
| `0x3C` | `FRAME_COUNT` | RO | 完整帧计数；v1一条命令一帧，与EXEC_COUNT一致 |

提交顺序为：等待 READY，写 `ACTION_CODE`，写非零递增 `CMD_SEQ`，写
`CONTROL.START`。PL 在接受时锁存动作和序号、置 BUSY、更新动作 LED 并开始 UART
发送；完整帧发送结束后更新 `LAST_ACTION/DONE_SEQ/EXEC_COUNT`、清 BUSY、置 DONE。
PS 读取并核对结果后写 `CONTROL.ACK`，DONE 才会清除。

BUSY 或未 ACK 的 DONE 状态拒绝新 START。序号为 0、非递增序号、非法动作、非完整
字命令、非对齐地址、未映射地址和 RO 写均返回 AXI `SLVERR`，且不得触发 LED 或
UART 副作用。读写通道保持独立，B/R 反压期间响应必须稳定。

## 3. 动作映射

LED0/V4 保留为 OV5640 `cfg_done`，动作只使用 LED1..LED7。

| 模型类别索引 | 模型标签 | ACTION | 动作 LED | 管脚 |
|---:|---|---:|---|---|
| 无有效动作 | CLEAR | `0x00` | 全灭 | - |
| 0 | Down | `0x01` | LED1 | U6 |
| 1 | Left | `0x02` | LED2 | U5 |
| 2 | Right | `0x03` | LED3 | V7 |
| 3 | Stop | `0x04` | LED4 | W7 |
| 4 | Thumbs Down | `0x05` | LED5 | W6 |
| 5 | Thumbs up | `0x06` | LED6 | W5 |
| 6 | Up | `0x07` | LED7 | U7 |

动作灯为 one-hot 且保持到下一条有效命令；`CLEAR` 关闭全部动作灯。模型索引与动作码
采用 `ACTION = model_index + 1`，避免动作 0 与复位/无动作混淆。

## 4. PL UART 帧

串口为 9600 baud、8N1、无流控。每条已接受的 AXI 动作命令发送一个固定 7 字节帧：

```text
Byte 0  Byte 1  Byte 2  Byte 3  Byte 4  Byte 5  Byte 6
  A5      5A      SEQ    ACTION   CRC8     0D      0A
```

- `ACTION` 是唯一的动作语义字段，取值与上表一致。
- `SEQ` 为 `CMD_SEQ[7:0]`，仅用于串口侧关联；AXI 侧保留完整 32 bit 序号。
- `CRC8` 使用 CRC-8/ATM：多项式 `0x07`、初值 `0x00`、MSB first、无反射、无异或
  输出，覆盖 `A5 5A SEQ ACTION` 四个字节。
- `0D 0A` 是固定帧尾。帧头、序号、CRC 和帧尾均不改变动作含义。

PL 串口只发送，不等待 COM4 回包。系统完成语义以 AXI `DONE_SEQ/LAST_ACTION` 为准，
COM4 捕获帧用于外设联动与独立验证。

## 5. 验收边界

RTL 仿真必须覆盖 0..7 全部动作、one-hot 映射、逐字节 UART 波形和 CRC、BUSY 期间
拒绝、重复序号、ACK、非法动作、WSTRB、复位中断以及 B/R 反压。仿真 PASS 后才可
修改主工程 BD。主板验收必须同时证明视频链路、AXI 提交/完成、LED 人工观察和 COM4
逐帧字节比对；任何一项缺失均不能声明完整动作闭环 PASS。
