# P2d — PPU add 核 RTL 门 run01

- 日期：2026-09-19（深夜并行线）。DUT：`rtl_ppu/yolo_ppu_add.sv`
  V1.0（**双路 requant 不逐路饱和**——A/B 保持 int64，手册 §2.2 字面
  合同 → int64 求和一次 → int32 合同截断（真实比率域永不触界仍字面
  实现）→ sat_i8 一次；双流会合接收：ready 不组合依赖对侧 valid；
  任务级 profile (Ma,sa,Mb,sb)；D+3 含气泡；drain=3 计数收尾；
  RNE 同 GEMM 尾移位+掩码式，s=0 旁路、M=0 死通道保留）。
- 命令：`ppu_add_vecgen.py <本目录>` → `vlog -novopt` →
  `vsim -c -novopt tb_yolo_ppu_add +GOLDEN=…/golden_add.hex`。
- 结果：**EES_MODELSIM_RESULT PASS** — checks=12679 errors=0
  lat_err=0（375 任务 6296 向量 × 装载交叉 + 逐拍运行比对）。
- 向量（6296 条、375 任务按 profile 分组，生成期配额断言全过）：
  真实 6 add 任务 profile 四元组×极值叉乘 294；全 x 对消/倍增扫描
  （恒等×恒等 / 恒等×大M / 大M×恒等）1533；**构造平局 lane-A 152 /
  lane-B 515（s=1..37，q 奇偶×积正负，构造域 m∈[1,2^31) 同 P2a）**
  含双路同时平局；**构造 int32 合同截断命中 1765**（s=0 大 M 单侧/
  双侧、±号）；死通道 15；恒等路 1600+；s=0 直通含 M=1 裸
  passthrough（y=sat(a+b)）；s=39..62 轨；**s 全 63 档覆盖断言**；
  随机全域 8 quad×500。
- 期望值三源独立：金文件=`ppu_oracle.add_q`（P1 已对软件 golden
  闭环）‖ TB 模型=截断除+floor 修正+平局到偶（与 DUT 移位+掩码
  不同构）+int32 截断+sat，装载期逐条交叉 ‖ 运行期 DUT≡金逐拍
  （posedge 三级 valid 镜像记分板，vsim/xsim 调度序无关——P2a
  教训①模式复用）。
- 用例：T1 全 375 任务（常供/双流独立随机间隔轮转——会合气泡）+
  T2 rst 在飞击杀（task1 n=49 喂 40 字节后杀）+ 重启全量复检 +
  X 绷线 + out_last 恰末拍 + 收尾静默/busy 归零/双流守恒 + 40ms
  看门狗。
- 首跑三教训（run01a/b，全在 TB/金文件侧，DUT 数值一次未错）：
  ① 金文件原单任务头混装全部向量而引擎 profile 是**任务级**——
  不同 quad 向量按 quad0 计算致 CROSS 假错 → 按 profile 分组多任务
  布局；② TB 喂数计数在"发出"递进而非"会合传输"，未收字节丢 →
  hold-until-transfer 协议；③ 传输判定在 negedge 事后采样 a_ready，
  末拍后 cnt==n 使 a_ready 已落 0 → 漏末拍死锁 → 改用 posedge 镜像
  mv1 判定（与检查器同源）。另：heredoc 内 `\\n` 经工具层转义不可
  靠，批量改文件用 Edit 工具。
- 产物：golden_add.hex、vecgen_result.json、vecgen_console.log、
  vlib.log、vlog.log、vsim_console.log（终跑 PASS）、msim/transcript、
  脚本副本 ×3（yolo_ppu_add.sv / tb_yolo_ppu_add.sv /
  ppu_add_vecgen.py）。
