# rom_data｜G2 量化包（只读部署工件）

来源：`4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01`（G2 门限通过轮，valid mAP50 drop +0.0176 ≤ 0.02）。本目录文件为逐字节副本（SHA-256 已与源 run 核对一致；manifest.json 内含各文件源哈希）。

| 文件 | 用途 |
| --- | --- |
| `weights.bin` | 63 节点 INT8 权重，布局/偏移查 `quant.json` 各节点 `w_off` |
| `bias.bin` | INT32 折叠偏置（conv 偏置 + BN 折叠），`b_off` 索引 |
| `lut.bin` | SiLU 256 项 LUT（激活前域输入 → 激活后存储尺度输出），`l_off` 索引，无 LUT 节点长度 0 |
| `quant.json` | 节点表 + tensor_scales + 数值合同说明；PL/PS 侧加载参数的唯一权威 |
| `manifest.json` | 源 run 指纹（权重 SHA、校准方法、环境锁定） |

注意：

- 数值合同冻结于 r3 §4.2（W8A8、每通道 M+shift RNE、双尺度 SiLU LUT、首层 u−128 z 折叠）。RTL/PS 实现不得更改合同；如需重校准，回软件 run 重跑并整体替换本目录，不在此处改单值。
- golden 对齐源（全节点 int8+fp 张量、128 帧回归）不复制到本目录，位于源 run `golden/` 与 `regression_128frames.json`；G3 单算子对齐以它们为准。
- 本目录属于 `2_fpga/3_yolo_zynq`（用户授权的新建目录）；`2_fpga/0_diaplay_test` 仍为只读借用。
