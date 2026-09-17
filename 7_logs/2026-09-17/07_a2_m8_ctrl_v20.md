# M8 ctrl V2.0 门（2026-09-17，授权链"按照1做"+"先做A2"+"继续"）

**结果：PASS（首跑）**——`TB_CTRL_PASS compared=136014 cycles (14 outputs/cycle)
ldone=25 alldone=1 snaps=2286`（xsim m8v20，日志 m8_run1.log）。

## 变更（rtl/yolo_ctrl.v V1.8 → V2.0，设计笔记 §2.1）

1. **走序双模** `dsc_walk_i`：0 = n 外 × oc 内（V1.x 序）；1 = oc 外 ×
   n 内（n 每 tile 步进、oc 在 n 回绕时步进）。统一 decode：
   `step_oc = walk ? last_n : 1`；`step_n = walk ? 1 : last_oc`。
2. **S_RQ 退役 → S_SNAP**：等 `snap_rdy_i`（影仓空）后推进 tile；
   `snap_o` = **寄存脉冲**（退出沿置位，S_TILE/S_TWAIT 首拍整拍电平）。
   rq_cnt/rq_limit/rq_* 端口全删（尾引擎在 gemm_array V2.0 侧）。
3. **S_TWAIT（新）**：层末等 `tail_idle_i && seg_idle_i` 再 S_LDONE。
4. **tile_rdy 拆分**：`wbuf_rdy_i && xbuf_rdy_i && params_rdy_i`。
5. **bank 每 buffer 一对**（w/x rd/wr）：**值变化沿翻转**——实现期定案，
   比设计笔记原文"装填计数器奇偶"更严格：单 tile 轴（oc_tiles/n_tiles==1）
   两种走序下均不翻（W/X 跨整个扫描复用、免重装），任一走序的翻转数
   = 该轴值变化数（walk0: w 每 tile、x 每 oc_tiles；walk1 对称）。
6. V1.6/V1.7 尾宽预存/暂存链保留并推广双走序（`oc/n_to_last` 直比式，
   前进沿仍纯寄存器装载）；rq_limit 乘法器下线（B0 时序只会更好）。

## snap_o 采到寄存式的理由（vecgen 自检抓出，留档）

组合解码 `S_SNAP && snap_rdy` 的脉冲只横跨"退出沿前的半个周期"：
posedge+#1 采样约定下（发射 = 本拍驱动 + 沿后状态组合输出），沿后状态
已离开 S_SNAP，**任何发射都看不到该脉冲**（首版 vecgen 断言
n_snap==0 即此）。改为退出沿寄存、次拍整拍电平后：TB 可见、无毛刺、
影仓捕获拍末沿读 acc 仍是终值（acc 清零 NBA 与捕获同沿，旧值语义），
零裕度风格与 V1.x S_RQ 进入拍相同，M10 数值链复核。

## 向量集（sim/ctrl_vecgen.py 重写，SEED 808）

- 25 层：L0 real conv0 w0；L1..L15 15 档 K×n=100 walk 交替；
  L16..L18 n 400/1600/6400 全 w1；L19/L20 oc=24 尾 8 双走序对照；
  L21/L22 单 tile 双走序；L23 极小 1/1/1 w1（零翻转）；L24 last w1。
- 136014 拍 / 2286 tiles / k_beats 116147 / snap 2286（==tiles）/
  w,x 翻转 14/2254（与走序逐层推导值吻合）/ tile 等待 4579 拍
  （三路归咎 1543/1521/1515）/ snap 背压 1392 拍（含 ≥2 拍深）/ TWAIT
  停顿 55 拍（tail/seg 双路均有且发生过同拍重叠）。
- 覆盖断言全过：15 K 档、5 N 档、双走序各含 n/oc 尾事件+单 tile 层、
  all_done 恰 1、acc_clr==tiles+等待、drain==4×tiles、背靠背+间隔切换。

## 证据

4_metrics/logs/2026-09-17_yolo7020_m8_ctrl_run04/（xvlog/xelab/run 日志
+ stim_manifest.json 含全文件 sha256）。

## 后续（本批未做）

- gemm_array V2.0 + M10 改造（loader W/X 拆分、第二 DMA、REQUANT_UNITS、
  acc 影仓乒乓消费 snap_o、X 组合口退役）——ctrl 新端口的对接方。
- CSR dsc_walk 影子位 + address_map.md 同步 + M12。
- M11 全网 vecgen dsc_walk 逐层最优；B0 OOC v28+（ctrl rq 乘法器下线、
  wbuf V3.0 +32 RAMB36 增量复核）。
