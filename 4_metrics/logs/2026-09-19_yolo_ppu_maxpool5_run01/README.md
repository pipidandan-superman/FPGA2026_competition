# P2c — PPU maxpool5 核 RTL 门 run01

- 日期：2026-09-19（深夜并行线）。DUT：`rtl_ppu/yolo_ppu_maxpool5.sv`
  V1.1（5×5 s1 SAME maxpool，pad(−128) 语义以**有效位掩码**实现、不物化
  pad 字节；(H+2)×(W+2) 处理网格：输入步握手、pad 步自走；深度
  4(W+2)+5 延迟线导出 25 抽头——同列跨行恒隔 L=W+2 步；max 读**移位后**
  语义（idx−1，idx0=in_data）；种子 −128 同 oracle；in_ready 反压，
  CHW 线性输出 D+1 寄存；MAXW=64 参数界延迟线，包内 W=10）。
- 命令：`ppu_maxpool5_vecgen.py <本目录>` → `vlog -novopt` →
  `vsim -c -novopt tb_yolo_ppu_maxpool5 +GOLDEN=…/golden_maxpool5.hex`。
- 结果：**EES_MODELSIM_RESULT PASS** — checks=13962 errors=0
  （首跑 checks+errors=2843+11119=13962，与 PASS 跑逐拍全对账，无漏拍）。
- 向量（11 形状×11 图案，I/O 26670 字节，生成期逐形状断言
  padded≡masked）：包内真实 (128,10,10)（SPPF 池化链）+ 合成重掩码边角
  1×1×1 / H=1 / H=2 / W=1 / W=3 / H=W=3<5 / 16×16；图案含
  **全−128 张量（pad 值==数据值，等价性刀刃）**、全+127、边框−128/
  内部随机、边框随机/内部−128（pad 永不胜出）、ramp、行/列条纹、
  棋盘、±双轨随机、全域随机。
- 期望值三方互证（手册 §2.2 等价性实证义务）：
  金文件=python **pad 模型** `ppu_oracle.maxpool5_padded`（P1 已对软件
  golden 闭环）‖ TB 模型=按输出位置**直接索引**的掩码 max（与 DUT 流式
  延迟线抽头不同构）→ 装载期交叉把 pad≡masked 钉死在全部对抗张量上；
  运行期 DUT≡金文件逐拍比对（含 out_last 恰在末拍）。
- 用例：T1 全 11 金形状（25% 随机供数间隔反压）+ T2 rst 在飞击杀
  （case (2,4,7) 喂 10 字节后杀）+ 重启同形状全量复检 + X 绷线 +
  收尾静默/busy 归零/输入守恒 + 40ms 看门狗。
- 首跑教训（V1.0→V1.1，已修，见 RTL 头注；FAIL 原始日志存
  `vsim_console_run01a_fail.log`）：V1.0 的 5×5 tap 阵列按**移位前**
  tap_r 计算 max，本步刚收的字节（窗口最右列）被漏掉 → 窗口整体滞后
  一列，11119 错。深挖后发现更深一层：tap 阵列若每步全移则行历史每行
  多移 W+2 次 → 根本性重构为延迟线（本步字节=idx0、历史按
  idx=(4−r)L+(4−t) 直取，天然对齐全部 H/W≥1）。移位后语义教训与
  P2a 首跑①同族：**采样点必须与数据代次显式对齐，不得靠数组当下值**。
- 产物：golden_maxpool5.hex、vecgen_result.json、vecgen_console.log、
  vlib.log、vlog.log、vsim_console.log（PASS）、
  vsim_console_run01a_fail.log（V1.0 首跑）、msim/transcript、
  脚本副本 ×3（yolo_ppu_maxpool5.sv / tb_yolo_ppu_maxpool5.sv /
  ppu_maxpool5_vecgen.py）。
