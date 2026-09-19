# P2e — PPU xfer 核 RTL 门 run01

- 日期：2026-09-19（深夜并行线）。DUT：`rtl_ppu/yolo_ppu_xfer.sv`
  V1.0（段序字节流拷贝 + 逐段可选 requant，手册 §5.2；恒等对
  (M=2^30,s=30) 走**硬件捷径**——S3 字节旁路 mux，结构性而非退化
  requant；段表写口地址自增、start/rst 清 wa_r 支持多任务轮转；
  MAXSEG=8；D+3 含气泡；drain=3 计数收尾；RNE 同 GEMM 尾
  移位+掩码式，s=0 旁路、M=0 死通道保留）。
- 命令：`ppu_xfer_vecgen.py <本目录>` → `vlog -novopt` →
  `vsim -c -novopt tb_yolo_ppu_xfer +GOLDEN=…/golden_xfer.hex`。
- 结果：**EES_MODELSIM_RESULT PASS** — checks=2842 errors=0
  lat_err=0（101 任务 1382 字节 × 装载交叉 + 逐拍运行比对 + T2
  rst 击杀重启复检）。
- 向量（101 任务 1382 字节，生成期配额断言全过）：真实 concat 任务
  段数/profile（schedule.json in_scale/out_scale，段数≤8 断言）×
  合成小长度；heads 型 6 恒等段；恒等/非恒等混排（首/中/尾）；单段
  任务含纯恒等；**len=1 边界 8 段连切**；**构造平局段 s=1..3 奇 M
  （段内每字节皆平局——奇 M 下 x≡2^(s-1) (mod 2^s) 全解填充）**；
  s=0 M=2^31-1 饱和轨、死通道 M=0、**M=1 s=0 全数据通路拷贝（与
  恒等捷径对照：同输出不同结构）**、all-min/all-max；s=0..62 全 63
  档单段轨任务（确定性覆盖）；随机任务（段数/profile/长度/字节）。
  平局 158、sat_i8 命中 476、恒等段 ≥15、死段 ≥2。
- 期望值三源独立：金文件=`ppu_oracle.requant_seg`（P1 已对软件
  golden 闭环）对**每一段（含恒等段）算全量 requant**——DUT 恒等段
  走捷径，DUT≡金即钉死"捷径≡全算"等价（x·2^30>>30 RNE==x ∀int8
  的 P0 结论落到门级）‖ TB 模型=截断除+floor 修正+平局到偶（与 DUT
  移位+掩码不同构）**同样无捷径**逐字节按段 profile 计算，装载期
  交叉 ‖ 运行期 DUT≡金逐拍（posedge 三级 valid 镜像记分板 +
  mv1 传输判定，vsim/xsim 调度序无关——P2a 教训①/P2d 教训③模式
  复用）。
- 用例：T1 全 101 任务（常供/随机间隔轮转——气泡）+ T2 rst 在飞
  击杀（task1，喂 40 字节后杀）+ 重启全量复检 + X 绷线 + y_last
  恰末拍 + 收尾静默/busy 归零/守恒 + 40ms 看门狗。
- 首跑两教训（run01a，见 vsim_console_run01a_fail_excerpt.md）：
  ① **数据链/有效链级数失配**——恒等旁路 x1→x2→x3→y_o 四级 vs
  v1→v2→y_valid 三级，DUT 数据滞后一拍而 y_valid 无 lat_err（ADD
  引擎数据在写拍组合入 y_o 故无此坑）→ 旁路 mux 改用 x2_r/id2_r
  （与 pa_r/s2_r 同级采样），删 x3_r/id3_r；② 失败 console 被重跑
  同名覆盖，只余 grep 摘录存档——**每次失败跑先另存再重跑**。
  另两处 pre-sim 自查修复（未进仿真）：S2 乘积误用 m2_r（晚一拍=
  错段 M）→ m1_r；wa_r 复位/启动不清零（多任务轮转读错段表槽）
  → rst/start 双清。
- 产物：golden_xfer.hex、vecgen_result.json、vecgen_console.log、
  vlib.log、vlog.log、vsim_console.log（终跑 PASS）、
  vsim_console_run01a_fail_excerpt.md、msim/transcript、
  脚本副本 ×3（yolo_ppu_xfer.sv / tb_yolo_ppu_xfer.sv /
  ppu_xfer_vecgen.py）。
