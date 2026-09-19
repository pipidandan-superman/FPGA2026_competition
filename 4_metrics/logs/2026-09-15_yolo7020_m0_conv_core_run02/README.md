# M0 conv_core 门重跑（run02）—— RTL V1.2 越界部分选择修复回归

日期：2026-09-15。结果：**11/11 全部 TB_CONVGEN_PASS，比对数与 run01 逐项相同
（零行为变化）**。

## 为什么重跑（M10 集成暴露的 RTL 缺陷）

M10 阵列集成（yolo_gemm_array 门）中，TB 的黄金核实例 OC=7/P_AW=4（OC_CW=3）
出现整层输出 X。定位链（sim_m10_dbg3→dbg6）证明根因在 `rtl/yolo_conv_core.v`：

- `bias_addr_o/m_addr_o/shift_addr_o = oc[P_AW-1:0]` 在 **P_AW > OC_CW** 时是
  越界部分选择——oc 的高位不存在，读出 X → 黄金核 bias/m/shift 服务全 X →
  requant 输出 X。同层 L3（OC=9 → OC_CW=4 = P_AW）完全正确，与
  OC_CW < P_AW 才坏的判据逐层吻合（L0 343 + L2 400 + L5 200 格 X）。
- M0 门 run01 的全部用例 P_AW = clog2(NP) = clog2(OC) = OC_CW（恰好相等），
  从未触发该路径——缺陷自 V1.0 潜伏至今。

## RTL 变更（V1.1 → V1.2）

- 新增 `localparam OC_PW = (P_AW > OC_CW) ? P_AW : OC_CW;`
  `wire [OC_PW-1:0] oc_ext = oc;`（隐式零扩展），三个参数地址端口改为
  `oc_ext[P_AW-1:0]`。
- 对一切 P_AW ≤ OC_CW 的配置逐位不变（M0 全部既有用例即此类）。

## 结果（与 run01 对照）

| 用例 | run01（V1.1） | run02（V1.2） |
|---|---|---|
| genE / genF / genG | 245 / 147 / 128 PASS | 同 PASS |
| genCrand / genCzero | 700 / 700 PASS | 同 PASS |
| genArand / genAext | 36864 / 36864 PASS | 同 PASS |
| genD / genB | 576 / 12800 PASS | 同 PASS |
| case0 / case0b | 409600 / 409600 PASS | 同 PASS |

## 命令与环境

- 编译：`vlog -quiet ../../rtl/yolo_conv_core.v ../tb_yolo_conv_core.v`
  （sim/msim）
- 批量：本目录 `run_all.sh`（11 例逐例 vsim `-c -novopt`，+STIM/+CASE/
  +WDT_MS 与 run01 相同；case0b 同命令行补 golden02）
- 环境：ModelSim SE-64 10.1c（win64，MGLS_LICENSE_FILE=D:/work/modelsim/
  win64/LICENSE.TXT），Windows 11 主机。

## 证据清单

1. 本 README.md
2. console_extract.txt（11 条 PASS 摘录）
3. run_all.sh（批量脚本）
4. sim_*.log × 11（原始 transcript，未编辑）
5. 激励复用 run01 冻结集（`sim/stim/gen*/`、`conv0_golden{00,02}`），
   哈希见 run01 目录 stim_sha256.txt。

## 结论

conv_core V1.2 通过 M0 门回归（零行为变化），M10 黄金路径修复成立；
M10 门（TB_GEMM_ARRAY_PASS）见
`2026-09-15_yolo7020_m10_gemm_array_run01/`。
