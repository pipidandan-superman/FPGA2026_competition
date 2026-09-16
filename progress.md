# 项目进度总览（progress.md）

更新：2026-09-16（G3 M12 A1 批五门全绿收口后同步）。本文件是全项目唯一的顶层进度管理视图，按"软件 / 硬件"两部分维护；每个条目只写状态与结论，详细过程、命令行与原始证据见对应链接。更新纪律：每批次收口时同步更新本文件 + `README.md`（顶层动态）+ `HANDOFF.md`（交接）+ `7_logs/YYYY-MM-DD/`（当日四件套）；任何"PASS"结论以 `4_metrics/logs/` 下的运行证据为准。

**一句话现状**：软件线量化合同与 PS 运行时已板上位级闭环；硬件线 G3 卷积引擎 M0–M11 全绿 + M12 A1 承接批五门全绿（Y 真 AXI 写主/CSR/engine 组装），A2 loader V2（已授权）待做，B 段 OOC / M13 板卡未启动（需单独授权）。

---

## 一、软件

| # | 里程碑 | 日期 | 状态 | 结论 / 关键数字 | 证据入口 |
|---|---|---|---|---|---|
| S1 | 手势模型 v1（YOLOv8n，7 类） | 2026-09-07 | ✅ | Roboflow hand-gesture v6；test mAP50 0.730（Stop/ThumbsUp/Up/Down 优，Left/Right/ThumbsDown 弱项）；PC 全链（摄像头→UDP→ONNX CPU→JSON）P50 62ms | `3_host/model/MODEL.md`、`7_logs/2026-09-07/` |
| S2 | 数据集补强 | 2026-09-14 | ✅/进行中 | v6 ZIP 删档留哈希；HaGRID 384p 下载与公开集调研完成（方向类缺口有据） | `4_metrics/logs/2026-09-14_gesture_*` |
| S3 | G1 FP32 基线 | 2026-09-14 | ✅ | 640/416/320 三尺寸；320 较 640 valid mAP50 反高 0.0278 → G2 采用 320 | `4_metrics/logs/2026-09-14_yolo7020_g1_fp32_baseline_run01/` |
| S4 | G2 量化整数参考（W8A8） | 2026-09-14 | ✅ | valid mAP50 0.8939→0.8763，drop +0.0176 ≤ 0.02 门限 | `4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01/` |
| S5 | G2 真 RNE 合同（run04，部署源） | 2026-09-15 | ✅ | 修复 bias_eff/平局两处量化缺陷后重跑，valid drop −0.0092；数值合同冻结（每通道 M/shift RNE 平局到偶、双尺度 SiLU LUT、首层 z 折叠）；部署包 weights/bias/lut/quant+manifest 落位 `2_fpga/3_yolo_zynq/rom_data/`（哈希核对） | `4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04/` |
| S6 | PS 运行时（numpy 整数推理） | 2026-09-15 | ✅ | 调度编译器 + intarith 运行时对 run04 包 **128/128 帧位级一致**（离线） | `4_metrics/logs/2026-09-15_yolo7020_ps_runtime_run01/` |
| S7 | PS 板上全量自检 | 2026-09-15 | ✅ | 真实 ARM PS（PYNQ 2.7/numpy 1.21.5）整网 head **128/128 位级一致**；box 72/128，56 帧差异全归因 ARM/x86 libm ulp（conf≤0.01，良性）；45.34s/帧（纯 numpy 未优化） | `4_metrics/logs/2026-09-15_yolo7020_ps_onboard_run01/` |
| S8 | 上位机与工具链 | 2026-09-08～11 | ✅ | UDP Viewer V1.2（BGR 修正冻结）、BLE Console v1.1（双向 61.7s 核对）、SD Builder v0.2.2（整合镜像板测 PASS，IMG 本地不入库） | `3_host/`、`8_tools/`、`9_pynq/sd/README.md` |

**软件当前限制 / 待办**：① test split drop +0.0571（FP 基线本身 0.7255、npos 少；未参与调参，如实报告；提升候选=偏置校正/QAT，单变量推进）；② 45.3s/帧为纯 numpy 未优化值，实时化靠 PL 加速主线（NEON 后处理仅按需）；③ golden 权威源 = run04 `golden/` npz + `regression_128frames.json`，冻结不复改。

---

## 二、硬件

| # | 里程碑 | 日期 | 状态 | 结论 / 关键数字 | 证据入口 |
|---|---|---|---|---|---|
| H1 | 视频链基线（OV5640→VDMA→ADV7511 HDMI） | 2026-09-06/07 | ✅ 冻结 | 480p 视觉 PASS，冻结 BIT/XSA/ELF 哈希成套；`2_fpga/0_diaplay_test` 为只读基线 | `4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/` 等 |
| H2 | UDP 视频到 PC | 2026-09-08 | ✅ 冻结 | C1.2 配对 6.3fps、丢帧/CRC ~0.9%；R/B 字节序修正冻结 | `4_metrics/logs/2026-09-08_udp_color_swap_fix_run01/` |
| H3 | PYNQ/Linux 摄像头双路输出 | 2026-09-11 | ✅ | SD 启动自动加载，HDMI+UDP 同步实时画面；120s 600 帧 VDMA 零错误 | `4_metrics/logs/2026-09-11_pynq_camera_run01/` |
| H4 | PL 板载蓝牙（MLT-BT05） | 2026-09-12 | ✅ | PL UART AT 板测 PASS（ILA 捕获 rx=4F）；PC↔板 BLE 双向 61.7s/11 轮一致 | `4_metrics/logs/2026-09-12_ble_board_at_response_run01/` |
| H5 | PS–PL AXI-Lite 独立工程 | 2026-09-12/13 | ✅ | 自研 4 份 RTL，100MHz WNS 2.925ns；1000 轮命令板测通过；AXI 复位修复后视频服务共存 | `2_fpga/2_axi_lite_test/`、`4_metrics/logs/2026-09-13_axilt_reg_board_run02/` |
| H6 | PL 重加载 v1.4 + 动作 LED | 2026-09-13 | ✅ | 两轮 A→C 上板成功（一轮断电后）；5 类手势 LED 对应用户确认 | `4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run0{1,2}/` |
| H7 | G3 架构基线冻结 | 2026-09-15 | ✅ | GEMM PE 阵列（输出驻留 OC×N，K 逐步进）；三实例 SIM-8×8 / BASE-8×16 / PROD-16×16；63 conv、15 档 K、1.011 GMAC/帧；M0–M13 逐模块门与证据四件套规则成文 | `1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md` |
| H8 | G3 标量核 + M0 通用 conv 核 | 2026-09-15 | ✅ | conv0 核 golden00/02 全量 409600/409600 零差异；参数化通用核 11/11（含假绿教训：合成激励反退化 + 真实数据回归双保险；V1.2 修复后 run02 回归同数） | `4_metrics/logs/2026-09-15_yolo7020_g3_conv0_rtl_sim_run01/`、`..._m0_conv_core_run0{1,2}/` |
| H9 | G3 M1–M9 单元门 | 2026-09-15 | ✅ | DSP48E1 双 int8 打包（2^24 穷举 0 败，偏置布局）/acc/wbuf/xbuf/requant/silu_lut/addrgen/ctrl/dma 全绿（M8 695092 周期×15 输出；M9 21 万字节零差异） | `4_metrics/logs/2026-09-15_yolo7020_m1..m9_*_run01/` |
| H10 | G3 M10 阵列集成（SIM-8×8） | 2026-09-15 | ✅ | M1–M9 全链集成 6 层流 438,447 格 vs 黄金零差异；真实层 R1/R2 对 run04 逐位一致；集成揪出 4 个 RTL 缺陷并全链重跑 | `4_metrics/logs/2026-09-15_yolo7020_m10_gemm_array_run01/` |
| H11 | G3 M11 全网端到端（SIM-8×8） | 2026-09-15 | ✅ | 1 帧全 63 conv **3,553,900 格逐位零误差** + head sha256 == run04 frame0（6 张量拆分逐字节全对）；65 个 PS 微操作 intarith 语义执行；k1×1 几何首覆盖；RTL 零改动 | `4_metrics/logs/2026-09-15_yolo7020_m11_fullnet_run01/` |
| H12 | G3 M12 部署承接（拆 A1/A2/B 三段） | 2026-09-16 | ◐ A1 全绿 | **A1 五门全绿**：M8 run03（ctrl V1.2 rq_rdy 回归）、M9b run01–03（dma_wr 真写主 + V1.2 非对齐）、M10 run03（阵列 V1.2a Y 真 AXI 写主，六项与 run01 同数）、M11 run03（全网七项与 run02 同数 + head sha 复命中）、CSR/engine run01（AXI-Lite CSR + engine 组装，首跑过）；§5 全链重跑义务已履行。**A2 loader V2 三件套已授权待做**（W 跨 n_tile 持久/X 行段流式宽写/requant 重叠，预算 ~3.95M 拍 < 5M）；**B 段 OOC 需用户确认** | `4_metrics/logs/2026-09-16_yolo7020_m{8,9b,10,11,12}_*_run0{3,3,3,3,1}/`（6 目录） |
| H13 | G3 M13 整合构建 + 板测 | — | ⬜ 未启动 | 与相机管线同位流，板上 vs PC；**需用户单独授权** | 基线 §5 |

**硬件当前边界**：① RTL 仿真证据链全部绿（`2_fpga/3_yolo_zynq/rtl/` 15 文件 + `sim/` 15 TB + 16 生成器/检查器；最新 = dma_wr/csr/engine_top）；② Vivado/OOC 从未运行，**帧率不对外承诺**（BASE-8×16 ≈12.6fps 峰值估算、PROD-16×16 30fps 仅目标）；③ 板卡加载/位流替换逐次单独授权；④ `0_diaplay_test` 冻结基线只读。

---

## 权威入口

- 当日验证摘要 / 下次启动：`7_logs/2026-09-15/03_validation_summary.md`、`04_next_start_guide.md`
- 交接与历史：`HANDOFF.md`；顶层动态：`README.md`
- G3 设计基线（状态字为权威）：`1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md`
- 主计划 r3：`1_docs/yolo7020_hardware_deployment_plan_20260914.md`
