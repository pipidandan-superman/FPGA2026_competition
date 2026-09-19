# 08 号工作日志 — run09：P1.2 bank+feeder 一体门（2026-09-19 白班）

## 任务

P1.2（批准计划）：`yolo_gemm_bank`（双组宽字 TDP + 64b 流式装载写口）与
`yolo_gemm_feeder`（唯一 k 计数器 + 出口级组 MUX + rd_busy 硬门控）一体过门，
三层 tier（4×4 KC8 / 8×16 KC64 / 8×16 KC576）。判据：全遍历 errors=0 +
off-by-one 专项 PASS。

## 过程（编年）

1. RTL 起草（bank V1.0 / feeder V1.0）+ TB 八阶段（R1-R8）+ tier 包装 + tcl。
2. **v1 编译失败**：xvlog VRFC 10-3186——untyped task 端口（wgrp/xgrp/fstb/lstb）
   默认 1-bit logic 不能位选；全部改 `input integer`。
3. 期间自查两处设计强化：
   - feeder 末地址拍 `blk_active` 笔误（写成置 1 会永久死锁 S_STREAM）；
   - **rd_busy 硬门控**：原"非读选组即可装"在停拍冻结段不安全（ren 已冷、
     字仍在飞，放行写会在恢复读时同址冲突）→ feeder 导出
     `rd_busy = S_STREAM ∥ v1 ∥ v2`，bank `ld_ok[g] = (g!=rgrp) ∥ ~rd_busy`。
   - R3 晚到阶段重设计（两组 sticky loaded 下原检查必假错 → 重装压顶 +
     hold_check_en 中途检查点）。
4. **v2 三层 FAIL（56/26/27）**。错误归类（三层交叉定位，无需波形）：
   - **bank W 首拍写址 NBA 竞态**（DUT 唯一 RTL bug）：tier2 的
     `got=afa73b2adeecdf00`（=块1 word0）跨块恒定残留 + 块1 侥幸通过
     （rst 后旧值恰 0）+ R5 末 X-only 装载清 wk_cnt → R6 全写"反常自愈"
     ——三特征共同锁定：wr_first 的清零是 NBA，本拍写仍用旧终值。
     同类隐患：w_final 长度收口（len=1 W-only 块 first=last 同拍锁错长度）。
   - **TB 单元层越界**：R4 len=9×3/LSET+5、R8 len=9 超 KC=8（镜像越界读 X
     与 DUT 地址回绕各半的假数据错）。
   - **TB ld_done 假丢**：ldjit 随机隙在末拍后插入，让过单拍脉冲。
   - **TB EXP_WORDS 差一**：R7 小块和误记 13（实 12）。
   - X 侧天然免疫的证明：hi 半字写总在本块首拍后 ≥1 拍，清零已落地。
5. 修复：bank 加 `w_wa = wr_first ? 0 : wk_cnt` 组合旁路（写与 w_final 同改，
   计数器化简 `wk_cnt <= w_wa+1`）；TB 加 L9/LLONG 钳位 localparam、
   ldjit 门 `kk < len-1`、EXP 公式修正；另加 DBG plusarg 探针（本轮未启用）。
6. **v3 三层 PASS**（150/271/1295，errors=0，守恒精确，bank_err=0）。

## 结论与沉淀

- P1.2 判据满足；读侧 V2 契约定稿：**无 k0（块基址活在装载顺序）**、
  换组拍=观测 ISSUE 拍、rd_busy 覆盖全字流窗。
- 教训（三条入 README）：①"首拍清计数"必须配套组合写址旁路（NBA 与本拍
  访问同拍竞态）；② TB 长度族必须 KC 钳位（越界镜像 X × DUT 回绕 = 假错源）；
  ③ 单拍脉冲断言的采样点必须与事件紧贴，中间的随机等待是断言杀手。

## 证据

- 控制台：`../../4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run09_bank_feeder/`
  （bf_console.log=v1 / bf_console_v2.log=FAIL 取证 / bf_console_v3.log=PASS）
- RTL：`2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_bank.sv`（V1.1）、
  `yolo_gemm_feeder.sv`（V1.0）；TB：`tb/tb_yolo_gemm_bankfeeder.sv`、
  `tb/tb_gemm_bank_tiers.sv`

## 下一步

P1.3 run10a：三体合并（bank+feeder+array），复跑 run06 全矩阵，
检查数严格对齐 846/4250/6881。
