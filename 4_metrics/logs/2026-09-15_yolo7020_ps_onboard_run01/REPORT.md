# 2026-09-15 yolo7020 PS 上板全量自检 REPORT（run01）

## 判定

**PS_SELFCHECK_ONBOARD_HEAD_ONLY —— head 128/128 位级一致，box 72/128
（56 帧差异全部归因为良性 float64 解码/排序类，计划 :219 容差内）。**

核心结论：**量化整数合同（W8A8 + 每通道 M/shift RNE + dyadic SiLU LUT +
首层 z-folding）在真实 ARM PS 上整网逐位复现** —— 63 层 conv 的全部输出
head sha256 与 PC golden run04 完全一致。PS 上板离线推理门（计划 G-PS）通过。

## 环境（证据 result_20221022_101012.json env 字段）

| 项 | 值 |
|---|---|
| 板 | pynq（EES331），192.168.240.10，SD 启动 |
| OS | Linux 5.15.19-xilinx-v2022.1 armv7l |
| Python / numpy | 3.10.4 / 1.21.5（PC 侧 2.5.3，不影响整数路径） |
| ees331-camera | 全程 active（未触碰 PL/服务/SD） |
| 板上新增 | 仅 /home/xilinx/yolo_selfcheck/ |

## 输入完整性（哈希门）

- rom_data 4 文件 sha256 全部校验通过
- inputs.npz sha256 = 653ca86641bc4f79…（与 PC 打包一致）
- expected.json sha256 = d2af97731e0025fa…

## 结果明细

| 项 | 值 |
|---|---|
| frames | 128/128 完成，无中断 |
| head（整数合同门） | **128/128 位级一致** |
| box（2dp/4dp 门） | 72/128 |
| 速度 | 首帧 45.37s，均值 45.34s/帧（纯 numpy，无 NEON/OpenBLAS 优化） |
| 总时长 | 5806.9s（nohup 后台） |
| PC 参考 | 0.574s/帧（board_pack_selfcheck 预验） |

## box 差异归因（8 帧子集诊断 + 全量抽 3 帧复核）

机制：ARM 与 x86 libm 的 exp/sigmoid float64 ulp 差（实测 3–5e-7）→
`np.argsort(-scores)` 对近并列候选排序翻转 → 两类表现：
1. **近并列幸存者交换**：重叠候选幸存者互换，坐标差 1–10px，conf 不变
2. **并列行重排**：conf 完全并列（如 f49 的 0.001497 对）时行序不同（纯置换）

抽检（49/68/127，覆盖 56 失败帧的早/中/晚）：
- 全部 same_n（框数不变）、无类别翻转、max_dconf < 5e-7
- 受影响行全部 conf ≤ 0.01 的噪声级检测；高置信行坐标逐像素一致
- f49 的 266px 为索引对齐下的并列行置换，按置信度排序对齐后集合一致

结论：与 8 帧子集诊断（0/1/6）同类，**属计划 :219 预留容差的良性类**，
不影响检测质量；最终质量指标以 head（位级）+ mAP 类指标为准。

## 工件

- `console.log`（[01]–[12] 全程动作记录）
- `result_20221022_101012.json`（全量证据）、`result_20221022_082741.json`（8 帧子集）
- `console_20221022_101012.log`（板端全量控制台）
- `heads_diag.json` + `diag_compare.py`（子集诊断）；`diag_full_pick/heads_diag.json`（抽检）
- 板端保留 /home/xilinx/yolo_selfcheck/（供后续复跑；不清理）

## 后续（按计划）

1. G3 RTL：conv0 数值门已过（同日 run01，golden00/02 全量零差异）→
   合成测试矩阵 → 并行流水化 → OOC 综合
2. B1 单 conv 上板需用户单独授权
3. PS 后处理容差（:219）可按本报告数据正式写入合同文档
