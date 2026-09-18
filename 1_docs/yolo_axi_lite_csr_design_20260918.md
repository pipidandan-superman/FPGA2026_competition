# YOLO PL AXI-Lite CSR 与表存储设计

## 1. 设计结论

建议设计独立的 yolo_control_subsystem，内部包含 AXI-Lite 从机、固定控制寄存器、描述符 BRAM、buffer 表 BRAM、量化参数表、SiLU LUT 和结果元数据环形队列。

AXI-Lite 采用：

- 地址宽度 32 bit，数据宽度 32 bit，WSTRB 4 bit；
- 单次最多一个未完成读和一个未完成写；
- 地址 4 字节对齐；
- AW/W 通道独立握手，不能要求 AWVALID 和 WVALID 同拍；
- 控制/状态寄存器使用片上 FF；
- 描述符、buffer 表、量化参数、LUT 和结果队列使用模块内部推断 BRAM/LUTRAM；
- AXI-Lite 只负责控制和低速表配置，权重/特征图/raw head 继续由 AXI HP DMA 访问 DDR。

不要把全部 CSR 做成外部 AXI BRAM Controller。推荐在同一个控制模块内推断 RAM，并从模块内部导出表项接口。

## 2. 为什么不能继续沿用当前 CSR

当前 yolo_csr 适合“写 LUT、写一层 DESC 和 BASE、START、轮询 layer_done”的流程。完整 YOLO 图还需要 63 个卷积、大量 Add/Concat/Pool/Upsample、多组 buffer、量化尺度、分支所有权、检测头发布和 PS 消费确认。

现有版本还把 AW 和 W 只有在同一拍有效时才接收。AXI4-Lite 的地址和数据通道可以独立到达；新模块必须使用独立 AW holding register 和 W holding register，二者都收到后再产生写提交。

## 3. 地址空间

基础地址继续使用 0x43C1_0000，避开现有 action IP 的 0x43C0_0000。

| 区间 | 用途 | 存储方式 |
|---|---|---|
| 0x0000–0x00FF | 固定控制、状态、错误、帧和输出寄存器 | FF |
| 0x0100–0x01FF | 调度器、队列和中断寄存器 | FF |
| 0x0200–0x02FF | DMA/缓存/性能计数器 | FF/计数器 |
| 0x1000–0x2FFF | descriptor table aperture | BRAM |
| 0x3000–0x3FFF | buffer table aperture | BRAM |
| 0x4000–0x4FFF | quantization parameter table | BRAM/LUTRAM |
| 0x5000–0x5FFF | SiLU LUT bank | LUTRAM 或 BRAM |
| 0x6000–0x6FFF | head/output metadata ring | LUTRAM/BRAM |
| 0x7000–0x7FFF | debug snapshot / trace window | 可选 BRAM |

## 4. 固定寄存器表

以下均为 32 bit 访问，偏移相对于 0x43C1_0000。

### 4.1 身份、能力和全局控制

| 偏移 | 名称 | 访问 | 位域 | 说明 |
|---:|---|---|---|---|
| 0x000 | ID | R | [31:0] | 0x594F4C32，新模块 ID |
| 0x004 | VERSION | R | [31:16] major, [15:0] minor | 当前建议 0x0300 |
| 0x008 | CAP0 | R | [7:0] OC tile, [15:8] N tile, [23:16] PE lanes, [24] graph-op PL, [25] head DMA, [26] IRQ | 硬件能力 |
| 0x00C | CAP1 | R | [7:0] max descriptor log2, [15:8] LUT banks, [23:16] BRAM table depth | 硬件能力 |
| 0x010 | CTRL | W | bit0 ENABLE; bit1 SOFT_RESET; bit2 START_FRAME; bit3 STOP; bit4 ABORT; bit5 CLR_STATUS; bit6 FLUSH_CACHE; bit7 ARM_IRQ | 脉冲或状态位 |
| 0x014 | STATUS | R | bit0 IDLE; bit1 RUNNING; bit2 FRAME_DONE; bit3 ERROR; bit4 DESC_EMPTY; bit5 DESC_FULL; bit6 HEAD_VALID; bit7 PS_ACK_WAIT; [15:8] current op; [31:16] frame sequence | 状态快照 |
| 0x018 | ERROR_STATUS | R/W1C | bit0 AXI-Lite; bit1 DMA read; bit2 DMA write; bit3 descriptor; bit4 buffer; bit5 quant; bit6 LUT; bit7 timeout; bit8 overflow; bit9 protocol | W1C 清除 |
| 0x01C | ERROR_INFO | R | [7:0] error code, [15:8] op, [23:16] descriptor id, [31:24] port | 最近错误 |
| 0x020 | MODEL_ID | RW | [15:0] model id, [31:16] quant profile id | 对应 manifest |
| 0x024 | GRAPH_CRC | RW | [31:0] | descriptor/quant/LUT 合同 CRC |
| 0x028 | FRAME_ID | RW | [31:0] | 当前输入帧号 |
| 0x02C | FRAME_CFG | RW | [9:0] width, [19:10] height, [23:20] format, [24] letterbox_done | 输入合同 |
| 0x030 | INPUT_BASE_LO | RW | [31:0] | 输入地址低字 |
| 0x034 | INPUT_BASE_HI | RW | [31:0] | 64 bit 地址高字 |
| 0x038 | INPUT_STRIDE | RW | [15:0] bytes/line | 输入行步长 |

### 4.2 输出和 PS 结果接口

PL 输出三个 raw head，PS 负责 DFL、Softmax、Sigmoid 和 NMS。

| 偏移 | 名称 | 访问 | 位域 | 说明 |
|---:|---|---|---|---|
| 0x040 | HEAD_BASE_LO | RW | [31:0] | raw-head DDR 地址低字 |
| 0x044 | HEAD_BASE_HI | RW | [31:0] | 地址高字 |
| 0x048 | HEAD_STRIDE | RW | [23:0] | head buffer 步长 |
| 0x04C | HEAD_BYTES | R | [31:0] | 当前帧输出字节数，约 149100 B |
| 0x050 | HEAD_FORMAT | RW | [7:0] layout, [15:8] quant profile, [23:16] stride mask | PS 解码格式 |
| 0x054 | RESULT_SEQ | R | [31:0] | PL 发布序号 |
| 0x058 | RESULT_FRAME_ID | R | [31:0] | raw head 对应帧号 |
| 0x05C | RESULT_STATUS | R/W1C | bit0 valid; bit1 overflow; bit2 dropped; bit3 crc_ok; bit4 ps_owned | 结果所有权 |
| 0x060 | RESULT_ACK | W | bit0 consume; bit1 drop; bit2 retry | PS 消费确认 |
| 0x064 | RESULT_RING_HEAD | R | [7:0] | PL 发布指针 |
| 0x068 | RESULT_RING_TAIL | RW | [7:0] | PS 消费指针 |
| 0x06C | RESULT_MAX_DET | RW | [15:0] | PS NMS 的 max_det |
| 0x070 | RESULT_CONF_Q | RW | [15:0] | 可选定点置信度阈值 |

不要把最终框坐标、类别、置信度展开成大量 CSR。PL 只发布 raw-head buffer 地址、字节数、帧号和有效位；PS 读 DDR 后写 RESULT_ACK。

### 4.3 调度器和 descriptor queue

| 偏移 | 名称 | 访问 | 位域 | 说明 |
|---:|---|---|---|---|
| 0x100 | DESC_CFG | RW | [7:0] depth, [15:8] stride words, [16] circular | descriptor 配置 |
| 0x104 | DESC_BASE | RW | [31:0] | BRAM aperture 起始索引 |
| 0x108 | DESC_COUNT | RW | [15:0] | 本帧有效项，当前约 104 |
| 0x10C | DESC_HEAD | R | [15:0] | PL 读取指针 |
| 0x110 | DESC_TAIL | RW | [15:0] | PS 提交指针 |
| 0x114 | DESC_DOORBELL | W | bit0 commit, bit1 frame_end | 提交队列 |
| 0x118 | DESC_CURRENT | R | [15:0] | 当前项 |
| 0x11C | DESC_DONE_COUNT | R | [15:0] | 完成数量 |
| 0x120 | DESC_ERROR_ID | R | [15:0] | 出错项 |
| 0x124 | SCHED_CFG | RW | bit0 overlap; bit1 graph_ops; bit2 spill_ddr; bit3 strict_order | 调度策略 |
| 0x128 | SCHED_STATUS | R | bit0 conv_busy; bit1 graph_busy; bit2 dma_busy; bit3 wait_buffer | 调度状态 |

### 4.4 DMA、缓存和性能计数器

| 偏移 | 名称 | 访问 | 位域 | 说明 |
|---:|---|---|---|---|
| 0x200 | DMA_CFG | RW | [3:0] HP mask, [7:4] burst log2, [8] read combine, [9] write combine | DMA 参数 |
| 0x204 | DMA_STATUS | R | [3:0] read outstanding, [7:4] write outstanding, [15:8] response errors | AXI 状态 |
| 0x208 | DMA_RD_BYTES | R | [31:0] | 读字节统计 |
| 0x20C | DMA_WR_BYTES | R | [31:0] | 写字节统计 |
| 0x210 | CACHE_STATUS | R | bit0 xbuf_full; bit1 ybuf_full; bit2 wbuf_full; bit3 graph_fifo_full | 缓存状态 |
| 0x214 | PERF_CYCLES | R | [31:0] | 当前帧周期 |
| 0x218 | PERF_MACS_LO | R | [31:0] | MAC 计数低字 |
| 0x21C | PERF_MACS_HI | R | [31:0] | MAC 计数高字 |
| 0x220 | PERF_STALL | R | [31:0] | 等待周期 |
| 0x224 | PERF_CLEAR | W | bit0 clear | 清性能计数 |

## 5. BRAM/LUTRAM 表设计

### 5.1 Descriptor BRAM

建议 128 项 × 32 个 32-bit word，即每项 128 B，总容量约 16 KB。当前完整图约 104 个任务，保留 24 项余量。采用 BRAM36 双口或分 bank BRAM，通过 0x1000–0x2FFF aperture 访问。

字段建议：

| word | 内容 |
|---:|---|
| 0 | opcode、valid、last、first、activation、walk、ownership |
| 1 | descriptor id、dependency id、next id |
| 2 | input0/input1/output buffer id |
| 3 | weight buffer id、bias/scale table id、LUT id |
| 4 | OC、N |
| 5 | K、IC |
| 6 | IH、IW |
| 7 | OH、OW |
| 8 | KH、KW、SH、SW |
| 9 | PH、PW、tile OC、tile N |
| 10 | weight offset/stride |
| 11 | parameter offset/stride |
| 12 | quant profile、input/output scale id |
| 13 | graph flags、Concat part count、pool/upsample mode |
| 14 | expected output bytes |
| 15 | descriptor CRC/debug tag |
| 16–31 | opcode 需要时复用的 64-bit 地址/扩展字段 |

PS 预加载 descriptor，运行时只更新 DESC_TAIL 和 doorbell。

### 5.2 Buffer table

建议 128 项 × 8 个 word，每项 32 B：word 0/1 为 64-bit base，word 2 为 size，word 3 为 line stride，word 4 为 C/H/W，word 5 为 scale id、数据类型、owner、valid，word 6 为 producer descriptor，word 7 为 consumer count/debug。

descriptor 只保存 buffer id，不重复保存所有 64-bit 地址。

### 5.3 Quant table

每个 quant profile 建议 16 B：word 0 为 M，word 1 为 shift、round mode、saturation mode、zero-point，word 2 为 input/output/stored scale index 和 LUT id，word 3 为 scale CRC/debug。

M 和 shift 由软件离线生成；PL 不做浮点或运行时 frexp。

### 5.4 SiLU LUT

建议 LUTRAM 优先，BRAM 次选。地址 8 bit，输入 [-128,127] 加 128，数据 8 bit signed；每个 bank 为 256 × 8 bit；允许 16 或 32 个 bank，descriptor 保存 LUT id。LUT 更新只允许在 IDLE 或 LUT_LOAD 状态，运行时禁止改写当前 bank，并使用 bank version/CRC 防止 PS 和 PL 使用不同表。

### 5.5 Result metadata ring

建议 16 或 32 项 × 64 B 的 LUTRAM/BRAM，保存 frame_id、result_seq、head_base、head_bytes、三尺度 shape、quant profile、CRC、valid、owner、error。真实 raw head 仍放 DDR，ring 只保存描述信息。

## 6. 存储方式决策

| 内容 | 推荐方式 | 原因 |
|---|---|---|
| ID、CTRL、STATUS、IRQ、指针 | FF | 少量、需要即时读写 |
| descriptor table | BRAM | 容量大、顺序读取、节省 FF/LUT |
| buffer table | BRAM | 64-bit 地址和 shape 不应展开为寄存器 |
| quant table | LUTRAM/BRAM | 可配置、访问规律 |
| SiLU LUT | LUTRAM 优先，BRAM 次选 | 256×8 小表，多 bank 并行读 |
| result metadata | LUTRAM/BRAM | 小型队列、双口访问 |
| raw head/feature map/weights | DDR + AXI HP | 数据量大 |
| 最终框/类别/置信度 | PS 内存 | PS 负责 DFL、sigmoid、NMS |

不建议用大量 reg 数组保存 descriptor，或把 raw head 和最终框展开成 CSR。

## 7. 推荐运行时事务

PS 写模型、图 CRC、输入和 head 配置；PS 通过 aperture 预加载 descriptor、buffer、quant、LUT；PS 写 DESC_COUNT、FRAME_ID 和 DESC_DOORBELL.commit；PL 调度 63 Conv 加 Add/Concat/Pool/Upsample；PL DMA 写三个 raw head；PL 发布 RESULT_RING 元数据并置 HEAD_VALID；PS 读取 raw head，执行 DFL/Softmax/Sigmoid/NMS；PS 写 RESULT_ACK.consume；PL 释放 buffer，进入下一帧。

## 8. 资源和时序建议

- AXI-Lite 固定 32 bit；64-bit 地址拆成 LO/HI 或放入 buffer table。
- 固定寄存器控制字建议不超过约 80 个 32-bit word，约 2560 个 FF。
- 16 KB descriptor、4 KB buffer、4 KB quant/LUT、2 KB result ring 优先映射 BRAM/LUTRAM。
- AXI 写接收、地址译码和 BRAM 写入分级寄存，避免 GP0 写路径直接扇出到全部 LUT/descriptor RAM。
- LUT 写入使用一拍寄存化的 we/address/data，不把 AXI 握手组合信号直接扇出到 LUT bank。
- descriptor 使用 shadow/commit：PS 修改 inactive bank，commit 后 PL 才切换。
- RESULT_VALID、RESULT_ACK、DESC_HEAD/TAIL 使用 owner 和序号协议，避免 PS/PL 同时占用 buffer。

## 9. 与主工程兼容

现有 axi_action_0 仍使用 0x43C0_0000–0x43C0_0FFF；新的 YOLO CSR 继续放 0x43C1_0000–0x43C1_FFFF。旧的 PC 识别结果下发寄存器保留在 action IP；YOLO 新 CSR 只负责推理控制、raw head 发布和结果消费确认，不把动作控制协议和模型推理协议混在一个寄存器文件里。

本设计是架构建议，不代表 RTL 已实现。下一步应先冻结寄存器合同，再定义 AXI-Lite、BRAM aperture、descriptor scheduler 和 result ring 的模块边界，最后用软件模型生成 descriptor 并逐层对照量化 Golden。
