# 2026-09-15_yolo7020_ps_onboard_run01 — PS 板端自检（首次上板）

## 目标

G2 部署包 + PS numpy 运行时首次在真实 ZYNQ PS（ARM Cortex-A9, SD/PYNQ Linux）
上运行回归帧，达成 `PS_SELFCHECK_ONBOARD`（判分口径 = PS_RUNTIME_OFFLINE_PASS
同款：head 字节 sha256 硬门 + box 解码精确相等）。

## 与主计划的关系（对齐声明）

- 对应计划 §10.5「穿插小规模板测，而不是最后才首次上板」精神：G3 前的
  B0 类板级冒烟，验证 PS 侧运行环境 + 产出板上 golden 基线。
- **不替代 G3/G5 任何门**：本 run 不加载位流、不动 PL；通过 ≠ 整网/精度 PASS。
- 下一步照计划：G3 单模块 RTL（首层 conv）vs golden 逐位对齐。

## 前置条件（用户执行/确认）

| # | 项 | 状态 |
| --- | --- | --- |
| 1 | SD 上电，等待 60–90 s | 用户已上电（2026-09-15） |
| 2 | **人工确认原 UDP 视频传输正常（PC 端收到流）** | ⬜ 待用户通知 |
| 3 | **人工确认原 HDMI 显示正常出图** | ⬜ 待用户通知 |
| 4 | PC 有线网卡 = 192.168.240.2/24 | ⬜ 连通性检查时一并核实 |

用户指令：2/3 确认之前不开始任何板上操作（SSH 只读检查也在内）。

## 输入（已冻结）

- 运行时：`2_fpga/3_yolo_zynq/pynq/{yolo_pkg,yolo_runtime,yolo_decode,intarith,board_selfcheck}.py`
- 部署包：`2_fpga/3_yolo_zynq/rom_data/`（= G2 真 RNE run04，manifest 4/4）
- 输入包：`pynq/board_pack/`（128 帧画布，PC 预验 128/128 PASS；
  inputs.npz sha256 `653ca86641bc4f79…`，expected.json `d2af97731e0025fa…`）

## 边界（与 doc/board_selfcheck_procedure.md 一致）

- 板上仅新增 `/home/xilinx/yolo_selfcheck/`；不装服务、不改 SD/BOOT.BIN、
  不停/不动 `ees331-camera`、不加载任何位流。回退 = 删除该目录。
- SSH 密码经 `EES331_SSH_PW` 环境变量 → pc_askpass.cmd，不进日志/命令行。

## 日志纪律（用户要求：所有关键动作留日志）

- 本目录 `console.log`：PC 侧每条 ssh/scp 命令及完整输出逐条追加（带时间戳）。
- 板端 `selfcheck_result/`：脚本自产 result_*.json + console_*.log，事后整体取回。
- 关键节点（连通性/上传/子集/全量/取回）各自在 console.log 中以
  `== [NN] <动作> ==` 分节标记。

## 执行序列（待前置 2/3 确认后）

1. 连通性：网卡配置 + TCP 22（只读）
2. 板端环境只读侦察：uname / python3 / numpy / 磁盘 / ees331-camera 服务状态
3. scp 上传（5 个 .py + rom_data/ + board_pack/）
4. 板端 `--frames 8` 子集 → 判定
5. 子集 PASS → `--frames 0` 全量 128 帧 → 判定
6. 取回证据 → 本目录；写 REPORT.md + 更新 7_logs 当日 03/04

## 结果

（执行后填写）
