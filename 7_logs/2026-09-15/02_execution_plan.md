# 2026-09-15 执行记录

## G2 量化整数参考：LSQ 尺度再拟合迭代至门限通过

接 2026-09-14 深夜状态（p99.99 裁剪，valid drop +0.0980）。本日按"每轮只改一项"继续：

1. **斜率诊断（定位首差层）**：用 golden npz 对每节点做 INT→FP 回归斜率，发现系统性增益误差 0.81–1.13（跨图一致、级联复合）：model.2.cv1 +13%、model.7 −19%、model.8.cv2 −18%、model.6.cv2 −14% 等；范数比与余弦分解表明误差主要是"斜率"分量而非纯正交噪声——可校准。
2. **逐层 LSQ 存储尺度再拟合**（本日唯一方法变更）：73 个拟合位（63 QConv 节点 + C2f Add 位 + 顶层 Concat 位），`S'=⟨v,fp⟩/⟨v,v⟩` 闭式解，v 取 INT 管线自身输出、fp 为 FP 模块输出，128 图校准子样本，定点迭代。requant 域与量化权重不动。
3. **迭代深度扫描**：×2 轮 → **valid drop +0.0176（门限通过）**；×3 轮 ×96 图 → +0.0278；×6 轮 → +0.0344（每轮 ~4% 中位收缩的饱和棘轮，过度收缩伤 AP）。最终采用 ×2 轮 ×128 图。
4. **固化**：G2 REPORT.md、manifest status=CANDIDATE、weights/bias/lut/quant + manifest 复制到 `2_fpga/3_yolo_zynq/rom_data/`（SHA-256 逐字节核对一致，附 README 说明只读部署工件性质）；golden 与 128 帧回归留在源 run 作 G3 对齐源。

有效下降轨迹（全程单变量）：0.8502（pre-BN 尺度 bug）→ 0.2606（BN 输出钩子）→ 0.2080（双尺度 SiLU LUT）→ MSE 裁剪否决（0.8937）→ 0.0980（p99.99）→ 0.0176（LSQ 再拟合 ×2）✅。

## G1 补记（完成于 2026-09-14，当日日志未覆盖）

`4_metrics/logs/2026-09-14_yolo7020_g1_fp32_baseline_run01`：G1_FP32_BASELINE_PASS。640/416/320 三尺寸对照，320 较 640 的 valid mAP50 差 −0.0278（320 更高），按计划选 320 为 G2 性能候选尺寸；420 图校准清单（纯 train 切分）与数据清单同轮产出。

## 本轮未做

- 未改任何 RTL/位流/板卡状态；未动 `0_diaplay_test`；test split 未参与任何调参。
- G3（单算子 RTL 对齐）与 PS PYNQ 侧开发留待下一轮。

## PS 上板全量 + G3 conv0 数值门 + PE 架构基线（2026-09-15 下午补记）

1. **PS 上板 run01 CLOSED**：128 帧全量 head 128/128 位级一致（判定
   PS_SELFCHECK_ONBOARD_HEAD_ONLY）；box 72/128 全属良性 libm ulp 类
   （子集 0/1/6 + 全量抽检 49/68/127 归因：近并列幸存者交换 + 并列行重排，
   受影响行均 conf≤0.01，无框数/类别变化）。45.34s/帧。
   证据 `4_metrics/logs/2026-09-15_yolo7020_ps_onboard_run01/`（REPORT + [01]–[12]）。
2. **G3 conv0 RTL 数值门 PASS**：标量核 vs golden00/02 全量 409600/409600
   零差异。修 2 处 10.1c 符号性 bug（拼接毒化 sum_b、三目 pad 常数零扩展）
   + 破解 vsim 挂死（必须 `-novopt`）。证据 `2026-09-15_yolo7020_g3_conv0_rtl_sim_run01/`。
3. **PE 架构基线冻结**：`1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md`。
   参数化 OC×N 输出驻留阵列；SIM-8×8（全网仿真）/BASE-8×16（主计划 §1.4
   回退档，无打包假设）/PROD-16×16（双打包 128 DSP，性能档）三实例；
   GEMM 形状全集实测枚举（63 conv、15 档 K、1.011 GMAC/帧）；M0–M13
   逐模块验证门 + 证据四件套规则。与主计划关系已显式记录（不推翻 §1.4，
   升级为参数化族，30fps 在 OOC+B1 证据前不作承诺）。
4. 板上仅新增 /home/xilinx/yolo_selfcheck/（保留）；未动 PL/服务/SD；
   未越 E:\competition；test split 未参与调参。

本轮未做：M0 合成测试矩阵及 PE 阵列 RTL（下一轮按架构文档 §9 顺序启动）。
