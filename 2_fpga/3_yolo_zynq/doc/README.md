# 3_yolo_zynq：YOLOv8 手势检测 Zynq-7020 部署工程

创建：2026-09-14，依用户指令设立。主计划：[1_docs/yolo7020_hardware_deployment_plan_20260914.md](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)（r3）。

## 边界（先读）

1. **本工程独立于冻结视频基线**：`2_fpga/0_diaplay_test` 及其余既有目录只读借鉴，不改其 RTL/位流/服务；失败回退路径 = 不加载本工程位流即回到原状态。
2. 主线路线（计划 §10.1）：浮点基线 → 硬件一致整数参考 → 单模块 → 子图 → 整网 → 实时验收；软件侧量化与 golden 生成在 `3_host`/`4_metrics` 侧完成后，产物（weights/schedule/golden）投放到本工程 `rom_data/`。
3. 所有过程证据入 `4_metrics/logs/YYYY-MM-DD_<task>_runNN/`，本目录只放工程本体与设计文档；不在此堆放临时 dump。
4. 一切文件不超出 `E:\competition` 范围存放。

## 目录约定

| 目录 | 用途 | 现状 |
| --- | --- | --- |
| `doc/` | 本 README、设计笔记、从 0_diaplay_test 借鉴的参数清单、节点记录 | 本文件 |
| `proj/` | Vivado 工程 + 构建/集成 TCL（新建工程，不复制 0_diaplay_test 工程本体） | 空，待 G3 前 |
| `pynq/` | PS 侧 PYNQ 运行时：Overlay 加载、描述符提交、DFL/NMS（C/C++）、测试脚本 | 空，待 G2/G3 |
| `rom_data/` | 软件侧导出的模型数值包：weights.bin/bias.bin/lut.bin/schedule.bin/quant.json + manifest | 空，待 G2 |
| `rtl/` | YOLO 加速 RTL：GEMM 阵列、窗口生成、重定标/SiLU、搬运与调度 | 空，待 G3 |
| `sim/` | 仿真 testbench、golden 回放、首错定位脚本 | 空，待 G3 |

## 从 0_diaplay_test 借鉴的参数与模式（只读来源）

| 借鉴项 | 来源文件 | 用途 |
| --- | --- | --- |
| Overlay/外设地址分配 | `0_diaplay_test/pynq/overlay.hwh`、`current.hwh` | 新推理核寄存器段从 HWH 空闲地址区分配，避开 ACTL/VDMA/IIC 已占用段 |
| MMIO 访问模式 | `0_diaplay_test/pynq/axi_lite.py`、`mmio_ordered.c` | PS 寄存器读写次序与屏障约定 |
| 摄像头帧快照/VDMA 停启序列 | `0_diaplay_test/pynq/camera.py`、`camera_action_v1.py` | G6 视频接入时复用已验证的 VDMA_HALTED/BUFFER_FREED 安全序列 |
| 硬件合同模式 | `0_diaplay_test/pynq/action_hardware_contract.py`、`main_hardware_contract.py` | 本工程 `yolo_hardware_contract.py` 的版本/地址/校验写法参照 |
| 板上服务化与开机自启 | `0_diaplay_test/pynq/ees331-camera.service`、`install.sh` | 后期推理服务化的部署方式 |
| Vivado 构建/集成流程 | `0_diaplay_test/proj/build_*.tcl`、`integrate_*.tcl`、xdc | 新工程构建脚本与约束风格 |
| 平台与器件 | `proj/display_test_zynq7020_school`、`vitis/display_test_wrapper.xsa` | 器件 xc7z020clg484-1、时钟与引脚约束基线 |

实际取值以逐文件核对为准，本表是索引不是数值快照；每次取用在本目录登记来源与哈希。

## 里程碑记录

| 日期 | 节点 | 证据 |
| --- | --- | --- |
| 2026-09-14 | 工程骨架设立，README 边界与借鉴清单建立 | 本文件；7_logs/2026-09-14 |
