# 2026-09-18 run01 —— PE/GEMM 开发 G0：软件 PE oracle + 逐层 golden 复放等价

按两手册（1_docs/yolo_pe_design_manual_20260918.md / yolo_gemm_design_manual_20260918.md）
§11/§14 规定的第一步。**复用原则（用户指令）**：软件侧量化推理 golden 是唯一权威，
本 run 只做"位级精化 + 等价证明"，不另立 golden。

## 结果

| 门 | 内容 | 结果 |
|---|---|---|
| C1 | DSP 双乘打包 256³ 穷举 vs 两路独立乘 | **0 失配**（w 与 x1 各自全扫，2²⁴ 组） |
| C2 | p0/p1 ∈ signed17、\|w·x\|≤16256 | 全 True |
| C3 | RNE 定向边（−1.5→−2、−2.5→−2、0.5→0）+ ties-even 扫 s=1..62 | True |
| C4 | 饱和边界 ±130/±128 | True |
| C5 | SiLU 索引 = y+128 偏置寻址（≠补码字节，负数域不同）| True |
| C6 | 首层代数 acc+b_eff = Σw·x + b_q + 128Σw | True |
| C7 | K=2304/Kc=576 分块续算 == 单遍 | True |
| — | **PE_ORACLE_PASS**（oracle_result.json） | ✅ |
| R | **golden 链复放：rom_data + canvas → oracle 算术 → int8_<node> 位对拍** | **53 节点 × 5 帧 全部 0 失配（G0_REPLAY_PASS ×5）** ✅ |

复放覆盖：63 conv（含首层 u−128/pad−128/z 折叠、逐通道 M+shift、SiLU LUT）+ 
add（双路 requant、int32 求和一次饱和）+ 跨尺度 concat + maxpool5 + upsample2，
即 PE/GEMM 硬件要复现的全部节点（3 尺度 raw head 的 s16/s32 存储另立合同，不在本轮）。

## 复用链（等价性的证据结构）

```
软件量化推理（权威，golden npz = run04 golden/）
  = rom_data（weights/bias/lut/quant/schedule，sha 溯源 = run04）
  + intref_yolov8.py 语义（逐字转录进复放脚本）
  → gemm_golden_replay.py（oracle 整数算术逐 task 执行）
  → 与 golden int8_<node> 位级相等（5 帧 × 53 节点）
⇒ oracle 算术 ≡ 软件侧量化推理；RTL 只需对拍 oracle（golden_pe.hex / golden_tail.hex 已备）
```

## 过程缺陷与发现（留档）

1. **oracle 初版 P[16] 位/值混淆**：RTL 加的是 P[16] 单 bit，我写成 `P & (1<<16)`
   （0/65536）→ 256³ 穷举暴露 8.36M 失配。修复后 0。教训：位段选取必须写 `(P>>16)&1`。
2. **C3/C5 检查期望写错**（0.5→2 等三个错期望；C5 把 y+128 与补码字节划等号）——
   oracle 数学没错，检查侧错，已改对并显式断言二者在负数域不等。
3. **rom_data README 来源标注过时**：README 写"来源 run01"，实际四件套 sha 全部
   == **run04**（bias/weights/lut/quant 逐一核对）；run01/run02/run03 的 bias.bin
   彼此皆不同。追补（run01 ADDENDUM）已言明 run01 golden 为混合舍入语义产物、
   不作部署源——用 run01 golden 复放必然大面积失配（实测 53/53 芏失配，
   model.0 即对不上），改指 run04 后全绿。**建议后续修订 rom_data/README 的来源行。**
4. bias.bin 的 `b_off` 是字节偏移（int32 → 元素偏移须 //4）；与 run01 追补的
   b_off 4× 虚高 bug 同族，属历史坑。
5. weights.bin 布局 = [oc][ic][kh][kw] 连续展平（model.0 位级全对即证）。

## 文件

- pe_oracle.py（PE_ORACLE_PASS；golden_pe.hex / golden_tail.hex 已生成，附 sha 于 oracle_result.json）
- gemm_golden_replay.py（G0 复放，`python gemm_golden_replay.py <dir> <frame 0..4>`）
- oracle_console.log / replay_console.log / replay_result_f{0..4}.json

## 下一步（按 PE 手册 §11 顺序）

单 PE RTL（复用已验证 V1.2 DSP48E1 原语配置，**新目录**，不动冻结基线）+
TB 延迟计分板，对拍 golden_pe.hex；随后双累加器 → 小阵列 + 共享尾 → 规模化。
