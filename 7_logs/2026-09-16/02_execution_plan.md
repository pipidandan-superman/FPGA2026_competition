# 2026-09-16 执行记录（M12 A1 批：Y 真 AXI 写主 + CSR/engine）

接 2026-09-15 深夜状态（M11 全网门 run02 已过、M12 A 段已授权"先跑a"）。
本日全程 RTL + 仿真回归，无 Vivado、无板卡操作。

## A1 件 1：M8 门 run03（ctrl V1.2 回归）——通过

`TB_CTRL_PASS cycles=699590 compared=699590*15 ldone=23 adone=1`（+rq_rdy_i
tie-high TB 一行改动，激励零改动 seed 808 复用）。接高电平 ⇒ 与 V1.1 run02
逐位一致；等待路径真实激励由 M10/M11 覆盖。证据
`4_metrics/logs/2026-09-16_yolo7020_m8_ctrl_run03/`。

## A1 件 2：M9b 门 run03（dma_wr V1.2 非对齐起始）——通过

Y 行起始 = oc_g·n_total + n_tile·N_EDGE 仅 4B 对齐（N=100 层），V1.1 的
8 对齐合同对行段化不成立。V1.2：内部下对齐 + 首/末字 wstrb 掩码；head=0
与 V1.1 逐位等价（A 组回归零差异）。45 命令/410,255B/3,240 AW 全绿。
**run03a 失败链教训**：非对齐命令 sum 失配而逐字节全对 ⇒ vecgen 黄金 sum
简写 bug（`addr+8*(i>>3)` 仅 8 对齐时等价）；捷径表达式扩展合同后必须
重推导。证据 `4_metrics/logs/2026-09-16_yolo7020_m9b_dma_wr_run03/`。

## A1 件 3：阵列 V1.2/V1.2a + M10 门 run03——通过（含失败链）

- V1.2：Y 从观测口换真 AXI4 写主（行段化器 SEG_IDLE/FILL/CMD/DR +
  u_dma_wr V1.2 + ctrl V1.2 rq_rdy 行首背压 + dsc_ybase 字段 +
  ldone/adone 排空门控）；TB V1.1 换 AXI 写从 BFM。
- **run02 失败链（23 字节）揪出行首准入在途竞态**：准入读前沿前
  seg_state_r，len-1 行序列每 IDLE 窗放进 4 个行首拍（1 吸收 + 3 落
  SEG_CMD 被丢），L0/L2/L5 = 5+12+6 = 23 与 FAIL 逐位吻合。V1.2a 修复：
  准入 = IDLE ∧ seg_infl_r==0（在途计数 d0+1/d3−1）；ywr_idle_w 同判据。
- run03：`TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447
  gold_wr=3247 ldone=6 adone=1` 与 V1.0 run01 六项同数；激励零改动。
  证据 `4_metrics/logs/2026-09-16_yolo7020_m10_gemm_array_run03/`。

## A1 件 4：M11 门 run03（全网 63 conv 回归，V1.2a 承接）——通过

- TB V1.1 同构改造：Y 写 BFM 散写按物理地址进 word 打包镜像 img（**一
  W 拍 = 恰一个 8B 对齐字：所有 strobe 拍合并成单 NBA**——逐 lane NBA
  同字互踩只留末 lane，smoke1 conv0 acc_err=357407 ≈ 51200×7 的根因，
  DUT 侧逐字节全对）；程序字 24 = y_base（dsc_ybase 源）。
- run03 全网：`TB_FULLNET_PASS convs=63 psops=65 compared=3553900
  dut_wr=3553900 head_bytes=149100 ldone=63 adone=1` 与 run02 七项
  逐项同数；63 conv 全 acc_err=0（非零计数=0）；headcheck
  `M11_HEADCHK_PASS sha256=9ce70525...` == run04 frame0 == run02。
  激励零漂移（stim 6 hex + vecgen + headcheck 与 run01 sha256 程序化
  比对全 SAME）。证据 `4_metrics/logs/2026-09-16_yolo7020_m11_fullnet_run03/`
  （四件套 + 失败链 smoke + smoke2 transcript + head_dump/headcheck）。
- 教训入档：验证侧镜像模型的写合并粒度必须与被测写口的原子性一致。

## A1 件 5：yolo_csr + yolo_engine_top + 门 run01——通过（首跑）

- rtl/yolo_csr.v V1.0：AXI-Lite 从（单在途、AW/W 同拍受理、字节 strobe
  合并）；描述符 12 影子 + CTRL 门铃/清统计 + STATUS（busy/dsc_ready/
  all_done 粘滞/dsc_pend/ldone 计数）+ IRQ_EN/IRQ_STAT(W1C) + LUT
  0x400 只写窗口；C_BASEADDR 参数化。寄存器图入 hw_contract/address_map.md
  （三处同步：合同 + RTL + TB 镜像）。
- rtl/yolo_engine_top.v V1.0：u_csr + u_array 纯布线；PROD 16×16 默认参/
  SIM 8×8 门实例同 RTL；X 字节口 A1 直通（A2 = xrowgen + 第二读 DMA）。
- sim/tb_yolo_engine_top.v V1.0：M10 TB 同构黄金链，PS 角色全走 AXI-Lite
  主 BFM（t0 影子模式往返自检 + 门铃/受理等待/ldone 轮询/IRQ 置起 W1C），
  +MAXLAYER 烟测开关。
- **smoke 失败链**：TB DESC1 拼接把 act/first/last 放 [14:12]（CSR 解包
  [18:16]）→ L0 act 丢失、SiLU 旁路，220 字节值错而计数全对；修复后
  smoke2 绿、全门 run01 首跑 PASS：
  `TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
  ldone=6 adone=1 csr=0`（与 M10 run03 六项同数 + csr=0；激励零改动）。
  证据 `4_metrics/logs/2026-09-16_yolo7020_m12_csr_engine_run01/`。
  教训：寄存器拼接/解包位域必须读回抽检。

## A1 收口（本日）——五件全绿

M8 run03 ✓ / M9b run03 ✓ / M10 run03 ✓ / M11 run03 ✓ / CSR-engine run01 ✓。
RTL 数值路径改动（阵列 V1.2/V1.2a、ctrl V1.2、dma_wr V1.2）已按 §5 履行
全链重跑义务，五门全部与改动前基线计数同一。A1 范围内无遗留；下一步
A2（loader V2 三件套，已授权"按照1做"）按序启动，B 段（OOC 综合）
待用户确认。

## 边界

- 未运行 Vivado、未动板卡/位流、`0_diaplay_test` 只读、数据本体不入
  Git、测试集不参与调参；B 段（OOC）与板卡待 A 绿后另行确认/授权。
