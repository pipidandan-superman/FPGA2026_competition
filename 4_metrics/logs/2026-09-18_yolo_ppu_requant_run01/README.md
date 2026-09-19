# P2a — PPU requant 核 RTL 门 run01

- 日期：2026-09-18/19（深夜并行线）。DUT：`rtl_ppu/yolo_ppu_requant.sv`
  V1.0（x INT8 × M[0,2^31) → INT64 → RNE(ties-to-even, s=0 直通) → sat_i8，
  3 级流水 D+3，M/s 随元素入流水；结构镜像 GEMM 线 yolo_gemm_tail 二三级）。
- 命令：`ppu_requant_vecgen.py <本目录>` → `vlog -novopt` →
  `vsim -c -novopt tb_yolo_ppu_requant +GOLDEN=…/golden_requant.hex`。
- 结果：**EES_MODELSIM_RESULT PASS** — checks=11043 errors=0 lat_err=0
  （driven=6021 y=6020 flushed=1 last_seen=2，守恒 ✓）。
- 向量（反退化，生成期 13 项配额断言全过，5023 条）：
  真实 31 对×极值、5 选对全 x 扫描、**构造平局 339 例（q 奇 170 进位 /
  q 偶 169 保持 / 负积 169，覆盖 s=1..37 每档）**——对照 P1 事实：真实数据
  5 帧 10.82M 元素平局事件为 **0**，平局路径只有构造才能测到；
  饱和 −128/+127 共 1635、近界 869、死通道 M=0 15、恒等对 263、
  s=0..62 全 63 档、随机全域 3000。hex sha256=65ebf2a8…。
- TB 期望三源独立：python oracle（ppu_oracle.requant_seg，P1 已对软件
  golden 闭环）生成金文件 + TB 内不同构模型（截断除+floor 修正+RNE）
  双向交叉（模型≡金 + DUT≡模型）+ 手工钉值（±1.5/±2.5→偶）。
- 首跑两教训（已修，见 TB V1.1 头注）：
  ① 延迟记分板 cyc−tag 打戳在 vsim 事件序下与驱动任务同 negedge 竞争
  （xsim 下 GEMM 线 tail TB 同构代码恰好良性）→ 改 posedge 三级 valid
  镜像，调度顺序无关；② T3 恒等扫描 `$signed(k[7:0])-128` 在 k≥128 出
  9 位中间值 −256（任务入参截 0、自检按 −256 比）→ 8 位模回绕。DUT
  数值两跑全绿（首跑数据即 0 错），两错均在 TB 自身。
- 产物：golden_requant.hex、vecgen_result.json、vecgen_console.log、
  vlog.log、vsim_console.log、msim/transcript、脚本副本 ×3。
