# run24 — B2 DMA 回环板级收官：BOARD_B2_PASS（一跑全绿）

日期：2026-09-19 10:20（板钟 Oct 22 为陈旧 RTC，锚点 boot_id
`c9815e42-cfcd-4341-88cc-611080c20575`）　　结果：**CKz BOARD_B2_PASS**，
A/B 两路零重试零错。

## 分工与被测件

- 用户（GUI）：axi_gemm_test BD 加 axi_dma_0（SG 关 / 64b 流+存储映射 /
  长度 20 / 仅对齐 / 同步时钟）、回环直连、连线自动化、综合布线出比特流
  （无仿真——官方 IP，接线由 validate+DRC+本板测覆盖）。
- 我（批处理零参与，纯文件预检+板测）：preflight_bd_check.txt 全绿后才上板。
- 被测件：impl_1 @17:59 bit（sha256 `6d91f2b5…`，4,045,696B）+ 配对 hwh
  （`0b35ee8f…`）；WNS+6.087/WHS+0.016/DRC0/DSP68（B1 基线不变）。

## overlay skill 七步逐条（zynq-pynq-overlay-workflow + ees331 正典）

1. 预检：boot_id 新鲜；**ees331-camera 本轮新形态**——相机已接回，服务
   active 期 journal 心跳显示真实帧流（frames 38724→38854、VDMA CR/SR 活跃、
   slots 轮转），~70s 后 camera.py 退出、dmesg `bitstream unlocked, ref=0` +
   `client exits pid(594)`、服务 failed 终态。**所有权空置且带显式释放证据**
   （比 run23 的 failed-terminal 记录更强）。fpga0=operating（相机残留），
   /dev/dri 无占用，getty 活。教训：我的首轮等待循环在 active 即 break——
   预检等待必须等**终态**，已沉淀进 skill。
2. 独立目录 /home/xilinx/gemm_b2_run24 + bit/hwh/驱动/脚本配对上传 +
   双侧 sha256 逐字节一致（3 文件）。
3. 所有权：见上，记录放行。
4. root（venv python3 + XILINX_XRT=/usr）驱动内分段门：
   CK1 HWH 合同 `['axi_dma_0','processing_system7_0','u_yolo_csr','u_yolo_gemm']`，
   **phys_addr** gemm=0x43c00000 / csr=0x43c10000 / dma=**0x40400000** 全中。
5. CK2 download → CK3 operating → CK4 **zocl 锁 +1**（1→2，收尾对账仍 2）。
6. 功能门 CK5-DB7（下表）。CK5 fork 牺牲子进程双首读（GEMM+DMA）一次通过。
7. 证据：board_run24.log（40 行，stdout+/dev/console 双通道）+ 本 README。

## 门明细（全部一次通过）

**路径 A（GEMM 回归——BD 动了 ic0/PS7，证明未波及）：**

| 门 | 结果 | 与 run23 对账 |
|---|---|---|
| CK6 S1 (seed 5119) | 128/128，y_count=128，STATUS=0x28 | 逐值相同 |
| CK7 S2 (seed 2240) | 32/32，y_count=32，stale@0=0x25 | 逐值相同 |
| CK8 S3 (seed 3396) | 128/128，y_count=128，STATUS=0x38 | 逐值相同 |
| CK9 soft_rst | STATUS=0/y_count=0/ID 保持 | 相同 |

**路径 B（PS-DMA 回环，HP0 ↔ DDR，CMA 缓冲）：**

| 门 | 内容 | 结果 |
|---|---|---|
| DB1 | 复位态：双通道 DMASR=0x1（Halted=1，SGIncld=0 硅上证实 SG 关） | PASS |
| DB2 | RS=1 起跑，双通道 Halted→0 | PASS |
| DB3 | 4096B 回环，S2MM 先武装后 MM2S；DMASR=0x1002（IOC+Idle）教科书值；逐字节对拍+尾不越界 | OK |
| DB4 | 尺寸扫描 137/**1**/1000/8192（对齐起点+部分拍尾） | 4/4 OK |
| DB5 | 连发 ×3 4096B 不停通道 | OK |
| DB6 | 停止+软复位清扫：DMACR 回 0x10002（**与 XCI 声明复位值逐位一致**）、DMASR 回 Halted | PASS |
| DB7 | 交叉存活性：软复位后 DMA 256B 恢复传输 + GEMM 全幅 S1 新种子(0x7E11) 重跑 128/128 | PASS |

总账：wop=3462 rop=863 **rb_ok=416 rb_bad=0 db_ok=9 db_bad=0**（A 路 288 +
DB7 重跑 128 = 416 自洽）。

## 板级结论

- **DMA→HP0→DDR 数据通路硅上闭环**：直连回环下 MM2S/S2MM 全尺寸（含 1B
  部分拍）零错，软复位后可恢复，与 GEMM 同位流共存互不干扰。
- **HP 口启用不构成 overlay 障碍**（fpga_manager 只写 PL；PS7 向导配置随
  FSBL 走）——本轮实证。
- CMA（pynq.allocate）+ HP 非一致口免 cache 维护，PYNQ 正典路径实测成立。
- 3462 次 GP0 写零挂死；新位流成为 GEMM+CSR+DMA 三从机共存基线（B3 垫脚石）。

## 新沉淀（已写入 skill/ees331.md）

1. ees331 相机档案更新：相机已接回，服务带真实帧跑 ~70s 后仍 failed（旧
   "35s 无帧"描述过时）；空置所有权判据升级为 dmesg unlock+client exit。
2. 预检等待必须等终态（active ≠ 终态）。
3. AXI DMA 回环正典：寄存器模型从 .xci memory_maps 转录（零猜测）、
   S2MM 先武装、双通道 IOC+Idle 轮询、W1C 清、allocate 免维护。
4. Vivado 2025.2 XCI 为 JSON（ip_inst/parameters/model_parameters）。

## 下一步

B3：DMA+GEMM 大 KC 连通（DMA 流接 GEMM 装载路径的桥设计需先立项——用户
单独授权）；板上现为 run24 位流基线。
