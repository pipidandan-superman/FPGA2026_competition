# run23 — B1 GEMM 板级收官：BOARD_B1_PASS（一跑全绿）

日期：2026-09-19 10:27　　结果：**CK10 BOARD_B1_PASS**（S1/S2/S3 全过，零重试）

证据：`board_run23.log`（CK 全程 + 双通道 /dev/console 同步）、驱动 `pl_gemm_b1.py`
（自检 oracle 独立）、`run_b1.sh`、`display_test_wrapper.bit`（sha256
`6082d8b58f0029b350dbddc53049081954cf17067f57f7f163c8d19aea414ec2`）+
`display_test_wrapper.hwh`（`ed17c546…`，自 run22b xsa 抽取、与 bit 同基名配对）。
板端目录 `/home/xilinx/gemm_b1_run23/`（双侧 sha 逐字节一致）。

## 被测件

`axi_gemm_test` impl_1 bit（16:29:46，run22b 修复重建批，WNS+4.954/DSP68/DRC0）。
BD：PS7 GP0 → axi_ic0 → {M00 u_yolo_csr @0x43C10000, M01 u_yolo_gemm @0x43C00000}。

## 上板流程（zynq-pynq-overlay-workflow skill 七步正典，逐条对照）

1. 预检：boot_id `1ab63a0b-a6e2-453e-a0e7-d09380369aa4`（up 6 min 冷启动）；
   ees331-camera `failed` 终态（相机已拆，非恢复目标）；fpga0=operating（开机
   camera overlay 残留）；`/dev/dri` 无进程占用（pgrep 撞远端 shell 自匹配已
   排除，ps 查无）→ **所有权空置记录放行**
2. 独立目录 + bit/hwh 配对上传 + 双侧 sha256 一致
3. root（venv python3 + XILINX_XRT=/usr）加载，分段门：
   - CK1 合同：`ip_dict=['processing_system7_0','u_yolo_csr','u_yolo_gemm']`，
     **phys_addr=0x43c00000/64K**（PYNQ 3.0.1 键名）+ CSR 0x43c10000 双从机
   - CK2 download → CK3 operating → CK4 **dmesg zocl 锁 +1**（pre=1 post=2）
   - CK5 **fork 牺牲子进程首读**（run06 纪律）：`OK 20260919`；随后
     GEMM ID=0x20260919 / CSR ID=0x594F4C32 VER=0x0300 双身份命中
4. 功能三场景（序列 = run21 TB 正典，oracle = Python 独立复刻）+ CK9 清扫

## 功能判据（全部一次通过）

| 门 | 场景 | 结果 |
|---|---|---|
| CK6 S1 | 全 8×16 K=64 act=1（LUT i^A5） | **128/128 回读 0 错**，y_count=128，STATUS=0x28（bit3 ld_done+bit5 tile_done，错误位 6-9 全 0） |
| CK7 S2 | 掩码 0x5A/0x0F0F K=40 act=0 线性旁路 | **32/32**，y_count=32，**幻影槽 addr0 保 S1 旧值**（got=exp=0x25） |
| CK8 S3 | 双块 K=96 grp0/grp1 乒乓 + 计算窗内并发装载 grp1 | **128/128**，y_count=128，STATUS=0x38（含 bit4 blk_done，语义自洽） |
| CK9 | soft_rst 清扫 | STATUS=0、y_count=0、ID 不变 |
| 总账 | — | wop=2464 rop=601 **rb_ok=288 rb_bad=0** |

oracle 数学逐字承袭 run15/run21（INT64 累加 + C 截断除 + floor 修正 +
RNE ties-even + 饱和 ±127/−128 + sat_addr=q+128 + LUT/线性旁路）；激励为本轮
独立确定性 PRNG（分布纪律同 TB：1/16 角点表 + 均匀 [−128,127]；s∈1..62
跳过 TB 的 hh-X 角点）。装载完成判据用 **STATUS.bit3 ∧ LDLEN 双长度组合**
（严于 TB 单粘滞位，防 S3 双 48 同长块的陈旧粘滞假通过窗）。

## 板级结论

- **GEMM 数据通路在真实硅片全功能闭环**：装载（192/120/144 拍三拍打包）→
  参数/LUT → start/轮询 → Y 捕获 RAM 回读，三场景 288 坐标与独立 oracle
  位级一致——run21 仿真语义（含 y_count 锁存/tile 边界）在板上复现。
- **2464 次 GP0 写零挂死**：M13 时代"YOLO 位流 GP0 写毒"在
  axi_ic0+module_ref+AXI-Lite 架构上确认不存在（CSR 线先例再证）。
- 板存活收尾：uptime 正常、fpga operating、zocl 锁计数与 CK4 对账。

## 下一步

B1 线收官。B2（PS-DMA 独立回环）→ B3（DMA+GEMM 大 KC）→ B4 全联，
均需用户单独授权（板上动作一律用户在场）。
