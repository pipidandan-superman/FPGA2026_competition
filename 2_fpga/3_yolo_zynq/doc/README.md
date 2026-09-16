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
| `doc/` | 本 README、设计笔记、从 0_diaplay_test 借鉴的参数清单、节点记录 | 本文件 + 板上自检规程 + hw_contract（地址映射） |
| `proj/` | Vivado 工程 + 构建/集成 TCL（新建工程，不复制 0_diaplay_test 工程本体） | ooc_gate/：B0 OOC run01–03 + dbg 系列（run03 = UG479 合规批，dsp=142 稳定、150MHz 时序未过，真根因 addrgen 除法）；yolo_zynq_test/ 待 M13 授权 |
| `pynq/` | PS 侧 PYNQ 运行时：Overlay 加载、描述符提交、DFL/NMS（C/C++）、测试脚本 | 运行时 5 件（gen_schedule/intarith/yolo_decode/yolo_pkg/yolo_runtime）+ 板上自检 3 件（board_selfcheck* / board_pack_selfcheck）+ board_pack 清单；离线与板上均 128/128 位级 |
| `rom_data/` | 软件侧导出的模型数值包：weights.bin/bias.bin/lut.bin/schedule.bin/quant.json + manifest | G2 run04 部署包已落位（哈希核对，见 rom_data/README.md） |
| `rtl/` | YOLO 加速 RTL：GEMM 阵列、窗口生成、重定标/SiLU、搬运与调度 | **M0–M11 + M12A1 + UG479 合规批全绿 + B0 150MHz 收敛（v27 wns +0.005，fmax 150.11）**：12 文件冻结点 = pe_pack V1.2（DSP48E1 三级流水）/ gemm_array V1.10 / requant V1.2g（PIPE 7）/ addrgen V1.3 / ctrl V1.8（S_DRAIN 4）/ xbuf V2.2（BMG 输出寄存）/ dma V1.3 / dma_wr V1.5 / conv_core V1.2 |
| `sim/` | 仿真 testbench、golden 回放、首错定位脚本 | 13 个 TB + 15 个生成器/检查器；激励大数据（stim/、msim/）不入 Git；M11 门以 ModelSim 为准（xsim 有 TB 级 X 问题，msim_v13/ 为合规批目录） |

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
| 2026-09-15 | G2 run04 部署包落位 rom_data；PS 运行时离线 128/128 | 4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04、..._ps_runtime_run01 |
| 2026-09-15 | PS 板上全量自检 head 128/128 位级一致 | 4_metrics/logs/2026-09-15_yolo7020_ps_onboard_run01；doc/board_selfcheck_procedure.md |
| 2026-09-15 | G3 架构基线冻结（GEMM PE 阵列，M0–M13 门） | 1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md |
| 2026-09-15 | conv0 标量核 + M0–M9 单元门 + M10 阵列集成全绿 | 4_metrics/logs/2026-09-15_yolo7020_m0..m10_*_run01 |
| 2026-09-15 | M11 全网端到端：1 帧 63 conv 逐位 + head sha==run04 | 4_metrics/logs/2026-09-15_yolo7020_m11_fullnet_run01 |
| 2026-09-16 | M12 A1 五门全绿（Y 真 AXI 写主 + CSR/engine） | 4_metrics/logs/2026-09-16_yolo7020_m{8,9b,10,11,12}_*_run0* |
| 2026-09-16 | B0 OOC：DSP 238→142 修复；UG479 合规批（pe_pack V1.2 三级流水）门链全绿（M11 双跑 ModelSim）；150MHz 未过，−31ns 真根因 = addrgen 除法 | 4_metrics/logs/2026-09-16_yolo7020_ug479_compliance、..._m11_fullnet_xsim_failchain、proj/ooc_gate/、7_logs/2026-09-16/03 |
| 2026-09-17 | **B0 150MHz 收敛**：xbuf BMG 输出寄存合同 + 13 轮迭代（v13 −31.017 → v27 +0.005 PASS，fmax 150.11，dsp 140）；M10 run12/M12 csr run09 与 v26 逐拍同；M11 v27 run04 双绿（七项计数同 v13 + head sha==run04）——**B0 冻结批全链收口** | 4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v25..v27（含 WNS 轨迹表）、..._m10_gemm_array_run10..12、..._m12_csr_engine_run07..09、..._m11_fullnet_run04、7_logs/2026-09-17/01..03 |
