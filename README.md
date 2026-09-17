# 小月文刀队｜AMD 具身智能赛道

> 全项目进度总览（软件/硬件两部分）：[progress.md](progress.md)。本 README 只保留最近动态，历史细节见 [HANDOFF.md](HANDOFF.md) 与 `7_logs/`。

## 2026-09-17/18 yolo7020：A2/B0 收口 → 板级位流 PASS → M13 两跑双冻结 → 转 JTAG 裸机

**硬件线（G3）**：A2 loader V2 三件套收口（M10 门复绿同基线数；层边界 LUT 预载双洞竞态修复=tail_idle_w 全排空契约；冻结 gemm_array V2.0c 等）→ **M11 run05 全网双绿承证**（TB_FULLNET_PASS 七项 + head sha==run04 冻结）→ M12 OOC：v28@150MHz FAIL(−8.750) 守"板后优化"决策改 **v28b60@60MHz first-light PASS(+0.806)** → **板级 BD 构建 PASS（run8 wns+0.954，yolo_a2.bit/xsa 解出；八跑剥洋葱坑全记录）**。

**M13 板测**：板端驱动 PC 自测双绿（pl_m11.py PL_M11_PASS 全七项）后两跑上板——run01(0x30000000)/run02(0x08000000 证据驱动全空窗口) **均 2–10 分钟内板硬失联**（ping/串口死、无 panic），DDR 段占用假设否定；根因排序①/dev/mem RAM 别名 mmap 13MB 直写机制（run01 冻点在纯 CPU 写阶段）②HP 互连挂死 ③FCLK0 未证。按"每失败路径一次重试即停"守规保留现场。**用户决策：转 JTAG 启动 + Vitis 裸机开发**（平台/应用工程已建于 `proj/board_sys/yolo_a2_board/vitis`，挂死现场可 xsct 读 PC——正是排冻结根因的对路工具）。

**run9 BD 修正批（09-18）**：用户 GUI 检出并手工修三处（DDR/FIXED_IO make external→100 条 IOSTANDARD 警告根因、PS 勾选 IRQ_F2P、60MHz 疑问=有意 first-light 决策）；批处理侧 `write_bd_tcl` 收编用户权威 BD 为正典 `yolo_sys_bd.tcl`（**IRQ_F2P 引脚物化机制=ps7 全配置一次性 set_property -dict 灌入**，手工逐对 set 得 41-721 disabled），XDC 删 create_clock 消 18-1056，三连 re-apply FREQ_HZ=60M（GUI 保存会丢 module_ref 接口属性）。重跑 **run9c PASS（wns+0.623，CRITICAL WARNING 总数=0，三类警告全清零）**，yolo_a2.xsa/bit 已更新。证据：[run09](4_metrics/logs/2026-09-18_yolo7020_board_build_run09/README.md)。

## 2026-09-16 yolo7020：G3 M12 A1 承接批五门全绿（Y 真 AXI 写主 + CSR/engine）

**硬件线（G3）**：M12 拆 A1/A2/B 三段后的 A1 批（纯 RTL+仿真，授权"先跑a"）单日五门全绿——M8 run03（ctrl V1.2 回归）· M9b run01–03（dma_wr Y 真 AXI4 写主 + V1.2 非对齐起始）· M10 run03（阵列 V1.2a 换 Y 真 AXI 写主，六项与 run01 同数）· M11 run03（全网 63 conv 回归，七项与 run02 同数 + head sha 复命中）· **CSR/engine run01 首跑过**（`yolo_csr.v` AXI-Lite 从 @0x43C1_0000 + `yolo_engine_top.v` 组装，PS 真控制路径成为门断言对象；寄存器图入 `hw_contract/address_map.md` 三处同步）。RTL 数值路径改动的 §5 全链重跑义务已履行；证据 6 个 run 目录四件套（`4_metrics/logs/2026-09-16_yolo7020_*`）。**下一步**：A2 loader V2 三件套（已授权）→ B 段 OOC（待用户确认）。

## 2026-09-15 yolo7020：量化合同板上位级闭环 + G3 卷积引擎 M0–M11 全绿

**软件线**：G2 真 RNE 合同 run04（valid drop −0.0092）为部署源，部署包落位 `2_fpga/3_yolo_zynq/rom_data/`（哈希核对）；PS numpy 运行时离线 128/128 帧位级一致；随后在真实 ARM PS 上全量自检 **128/128 帧 head 位级一致**（box 差异全部为良性 libm ulp 类），45.34s/帧未优化。证据：[run04](4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04/) · [PS 运行时](4_metrics/logs/2026-09-15_yolo7020_ps_runtime_run01/) · [板上自检](4_metrics/logs/2026-09-15_yolo7020_ps_onboard_run01/REPORT.md)。

**硬件线（G3）**：架构基线冻结（[GEMM PE 阵列](1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md)，SIM-8×8/BASE-8×16/PROD-16×16 三实例 + M0–M13 逐模块门）后，单日完成 12 个门全部通过：conv0 标量核 409600/409600 → M0 参数化通用核 11/11（含"合成激励反退化+真实数据回归"假绿教训）→ M1 DSP48E1 双 int8 打包 2^24 穷举 0 败 → M2–M9 单元门全绿 → **M10 阵列集成**（6 层流 438,447 格零差异，揪出 4 个 RTL 缺陷并履行全链重跑义务）→ **M11 全网端到端**（1 帧全 63 卷积 **3,553,900 格逐位零误差** + head sha256 == run04 frame0；65 个 PS 微操作按 intarith 语义执行；k1×1 几何首次覆盖）。RTL 共 12 个 `.v`/`.sv` 文件 + 13 个测试台 + 15 个激励生成/检查脚本，全部 Verilog-2001，每个门独立 run 目录四件套留证（`4_metrics/logs/2026-09-15_yolo7020_m0..m11_*`）。

**边界**：M12（OOC 综合/Vivado）与 M13（板卡整合）未启动，需单独授权；OOC 时序落地前不对外承诺帧率；`2_fpga/0_diaplay_test` 冻结基线未动。本批 RTL/仿真/证据/文档已上传个人分支 `codex/full/pipidandan-superman`（PR 待队友审核）。

## 2026-09-13 PL重加载v1.4与动作LED复现

当前唯一PL重加载交付为`8_tools/EES331_PL_Reloader_v1.4/`；旧v1.0～v1.3不再发布。固定动作BIT/HWH经v1.4完成两轮A→C上板成功，第二轮发生在用户确认断电重启之后；Stop、Up、Down、Thumbs Up、Thumbs Down均已由用户确认对应LED4/7/1/6/5。当前结论是2/2成功样本，不是长期冷启动稳定性保证。

队友必须先按[零歧义上板指南](1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md)确认原HDMI/UDP动态基线，再只点击一次加载。动作识别要从v1.4内部“打开动作识别”启动；直接双击识别EXE默认`protocol=null`，只显示识别结果而不会下发LED。精选证据见[第一轮](4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run01/REPORT.md)、[断电后第二轮](4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run02/REPORT.md)与[重开诊断](4_metrics/logs/2026-09-13_action_viewer_reopen_diagnosis_run01/REPORT.md)。原SD、BOOT和冻结`2_fpga`均未纳入本次变更。

## 2026-09-12 BLE Console v1.1 与手动复现

推荐未配对GATT接入已集成上位机：三次无缓存读取/保持门控、自动通知、断连停止发送。
31项离线/Tk测试、新版后端60.5秒三轮双向及真实EXE按钮双向字节核对通过；
用户另行确认双向通信成功。TX只是发送记录，HEX旁的文本替代字符不是数据损坏，
端到端结果以另一端实际收到的HEX为准。

[操作与验证状态](1_docs/doc/ees331_ble_validation_status_2026-09-12.md) ·
[上位机源码及说明](3_host/ble_console/README.md) ·
[方案v1.2](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md) ·
[本次发布范围](4_metrics/logs/2026-09-12_ble_v11_publish_run01/REPORT.md)。
本地新EXE在8_tools/EES331_BLE_Console_v1.1，旧包保留；本次上传源码、说明、精选证据，
不上传运行依赖树或凭据。冻结FPGA不改；长期/重连/机械臂/AXI-BRAM仍待分阶段执行。

## 2026-09-12 最新蓝牙里程碑

PC与板载MLT-BT05已通过短时双向通信：未配对GATT保持61.703秒，11轮、每方向166字节全部一致，结束主动断开。COM4有线AT正常；不等于长期压力、Windows PIN配对稳定、机械臂互通或正式AXI/BRAM控制通过。复现时直接通过BLE上位机连接并订阅FFE1，COM4=9600/8N1用于另一端收发核对，不需ILA。

入口：[验证状态与复现](1_docs/doc/ees331_ble_validation_status_2026-09-12.md) · [完整开发方案v1.1](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。下方历史阶段状态以本段及最新验证报告为准；当前电平桥不能替代正式字节级UART/FIFO。


本项目面向全国大学生嵌入式芯片与系统设计竞赛 2026，当前选择：

> **AMD 具身智能赛道（赛题 3.2）**
> **作品名称：锐眼·智行——具身智能分拣**
> **应用场景：视觉识别与自动分拣**

系统架构：

> **AMD Ryzen AI PC（上位机"大脑"）+ AMD Zynq-7000 FPGA（实时"小脑"）异构协同**

## 当前进展与交付入口（2026-09-11）

- 本批归档已上传 `codex/full/pipidandan-superman`（内容提交 `ae1384a`），[草稿 PR #3](https://github.com/pipidandan-superman/FPGA2026_competition/pull/3) 等待审核；未合入 main。推送核对见 [回执](4_metrics/logs/2026-09-10_session_archive_upload_run01/upload_result.json)。
- **EES-331 SD → Linux Shell 已启动**：原始串口见 [uart_pynq_log.txt](4_metrics/logs/2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt)。网络、Jupyter、自定义 Overlay 和完整分拣闭环仍需分别验收。
- **SD Builder v0.2.2**：[Windows EXE](8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.2.exe) · [使用说明与源码](3_host/pynq/sd_boot_builder_v02/README.md)。当前只保留 EES-331 版本，默认基线为 `9_pynq/sd/01_base_ees331`，支持 XSA/FSBL/设备树/完整 IMG、摄像头 PYNQ 应用注入及自定义输出路径。
- **已验证写卡镜像**：本机统一入口为 `9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`，SHA-256 `8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`。该镜像已于 2026-09-11 完成 SD 启动、OV5640 配置、HDMI 动态画面和 PC UDP 动态画面验证。
- 写卡使用 [Win32DiskImager 安装器](8_tools/win32diskimager-1.0.0-install.exe)；零基础操作、手工部署和开发流程见 [PYNQ 教程](1_docs/PYNQ零基础开发与EES331摄像头工程实战.md)。
- **AIPC 借用报告**：[两页 Word 报告](<1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx>)。正文和排版检查完成，队员/学校/联系方式、团队编号及机型确认仍待补充，尚未提交申请。
- 9 月 8 日裸机 UDP 摄像头传输及 PC 端 BGR 修复结论继续有效，详见下方原始记录；不能将这些结果直接计作 Linux/PYNQ 网络验收。
- [交接文档](HANDOFF.md) · [当日验证记录](7_logs/2026-09-10/03_validation_summary.md) · [关键证据与上传范围](4_metrics/logs/2026-09-10_session_archive_upload_run01/REPORT.md)。本轮仅归档和更新文档，冻结 `2_fpga/` 无改动。

## 项目目标

以下为规划目标，不代表已完成；实际通过项以上方证据和下方板测记录为准。模型部署后端、机械臂控制接口和加速模块需在器材确定后验证。

构建一套具身智能视觉分拣系统，在真实环境中完成"感知→决策→控制→执行"的完整闭环。Ryzen AI PC 在本地运行 YOLO 目标检测模型（ROCm），识别目标物体并规划抓取策略；Zynq FPGA 在 PL 端完成图像采集与预处理、CNN 特征提取加速、多轴舵机精确控制与硬件级安全保护。两者通过 Ethernet 通信，协同完成机械臂自动抓取与分拣。

## 系统分工

| 角色 | 平台 | 职责 |
|------|------|------|
| 大脑（AI 决策） | AMD Ryzen AI PC | YOLO 目标检测推理（mAP ≥ 0.7）、位姿估计、抓取策略规划、人机交互界面 |
| 小脑（实时控制） | AMD Zynq-7000 FPGA | OV5640 图像采集、PL 端图像预处理、CNN 加速推理、多轴舵机 PWM 控制、轨迹插值、HDMI 实时显示、硬件安全逻辑 |
| 通信桥梁 | Ethernet（UDP） | 双向数据流：检测特征上行、控制指令下行、状态反馈上行；RTT < 5 ms |

## 闭环链路

```
摄像头感知 → FPGA 预处理与 CNN 推理 → 通信上传 → AI PC 识别与规划
    → 控制指令下发 → FPGA 轨迹插值 → 多轴舵机执行 → 机械臂抓取
    → 视觉反馈验证 → 循环下一目标
```

## 赛道核心要求

### 设计约束与计划（正式验收待完成）

- 上位机必须为 AMD Ryzen AI PC，型号不限；已规划，设备待落实
- 必须包含基于 AMD 器件的 FPGA/Zynq 设计，并说明其实际作用；拟定 CNN 加速与控制功能；HDMI 已有独立板测
- FPGA/Zynq 不能仅作为普通 USB、串口或 GPIO 转接板使用；需用最终实现和测量证明 FPGA/Zynq 的作用
- 必须给出 AI PC 与 FPGA/Zynq 的通信方式和数据流；已有裸机 UDP 证据，最终系统仍需集成
- AI 决策到物理执行的闭环必须完整，至少完成一项真实物理任务。计划验证机械臂抓取与分拣

## 平台与工具链

| 组件 | 说明 |
|------|------|
| 上位机 | AMD Ryzen AI PC（拟借用，型号待确认） |
| AI 推理 | YOLO 端侧部署；后端与版本待设备兼容性验证 |
| FPGA 板卡 | 依元素 EES-331（Zynq-7000 XC7Z020 CLG484-1） |
| FPGA 开发工具 | 当前 SD Builder 使用 AMD Vivado / Vitis 2025.2；2020.2 为历史参考工程 |
| 仿真工具 | ModelSim |
| 通信方式 | Ethernet（UDP，RTT < 5 ms） |
| 机械臂 | 4-6 自由度舵机机械臂（待采购） |
| 摄像头 | OV5640（DVP 并行接口，已有） |
| 显示器 | HDMI 480p60 通过 ADV7511（已有） |

## 核心量化指标（赛题 3.2.4.3 必报）

| 指标 | 目标 |
|------|------|
| 任务闭环成功率 | ≥ 90%（50 次重复测试） |
| 端到端响应延迟 | P50/P95/P99/最大值，待标定 |
| AI 任务效果 | mAP@0.5:0.95 ≥ 0.7 |
| AI 推理延迟 | ≤ 30 ms / 帧（batch=1） |
| FPGA CNN 推理延迟 | ≤ 5 ms / 帧 |
| FPGA vs. CPU 加速比 | ≥ 5× |
| AI PC ↔ FPGA RTT | ≤ 5 ms |

详细指标与测量方式见 `1_docs/赛题方向/设计方案_具身智能视觉分拣.md` 第 5 节。

## 现有工程基础

| 工程 | 路径 | 说明 | 复用状态 |
|------|------|------|----------|
| OV5640 + HDMI 显示 | `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true` | 纯 PL 视频采集与显示链路 | 直接复用 |
| PS 端神经网络 | `E:\FPGA_Project\2020_2\cnn_PS_final` | 手写数字识别，NN 推理运行在 ARM PS 端 | 架构参考 |
| PS+PL 神经网络 | `E:\FPGA_Project\2020_2\cnn_PS_PL_ACC_final` | PL 硬件加速 + OV5640/HDMI 视频链路 | CNN 加速器架构复用 |

## HDMI / ADV7511 适配进展

**当前冻结基线：`camera-hdmi-visual-pass-20260907`。** OV5640 画面已通过 S2MM 写入 DDR、MM2S 读出并经 HDMI 输出，板端三张照片归档为 `BOARD_VISUAL_PASS`；完整 UART 验收仍待用同一 BIT + 同一 ELF 复测。

EES-331 显示适配按 **480p60（640×480@60，25 MHz 像素时钟）** 完成 RTL 与 ModelSim 仿真。当前 ADV7511 输出链路使用 **BT.601 limited-range CSC**、`R0x15=01`、`R0x16=38`、`R0x48=08`、16 位 YCbCr422 逻辑数据和 EES-331 板级字节交换。

### 活跃模块层级

```text
hdmi_out_adv7511_v1_0
├─ rgb2ycbcr422
└─ adv7511_cfg_top
   ├─ adv7511_controller
   ├─ adv7511_iic_data_xfer
   └─ iic_protocal
```

源码位于 `2_fpga/0_diaplay_test/rtl/hdmi_new`；当前 BD 顶层为 `hdmi_out_adv7511_v1_0`。下载冻结 BIT 并加载配套 ELF 后，必须手动复位一次摄像头采集，复位后实时画面才能正常稳定显示；这是当前冻结恢复流程的必要步骤。详细版本说明见 `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md`。

### 验证状态

| 项目 | 结果 |
|------|------|
| 视频像素检查 | PASS，16/16 |
| ADV7511 寄存器写入检查 | PASS，18/18 |
| Verilog 顶层复现证据 | `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22` |
| BD Module Reference | PASS |
| EES-331 XDC 引脚检查 | PASS，23/23 |
| PS UART 通信 | 板级 PASS |
| Vivado 实现 | PASS，11060/11060 nets fully routed，0 routing errors |
| 时序收敛 | PASS，WNS 9.510 ns，TNS 0.000 ns，constraints met |
| PS VDMA + HDMI 彩条 | BOARD VISUAL PASS |
| OV5640 + PS VDMA + HDMI | BOARD VISUAL PASS，2026-09-07 |
| OV5640 + PS VDMA 完整 UART 验收 | 待复测，同一冻结 BIT + ELF |
| 主工程 Zynq ENET0 配置等效性（vs 回环工程 21 项 PCW） | PASS，2026-09-08 |
| 主工程 lwIP UDP 回环 + 摄像头 HDMI 同板共存 | BOARD PASS（`MAIN_ETH_LOOPBACK_PASS`），2026-09-08 |
| 自定义 UDP 视频协议 + 上位机（Python/exe）设计 | 文档交付，2026-09-08 |
| 主工程 →PC UDP 视频流 B1（1 fps 彩条，640 包/帧，921.6 KB/帧） | BOARD PASS（`UDP_TX_B1_PASS`），2026-09-08 |
| 主工程 →PC 摄像头实时画面 C1（快照选槽，~5 fps） | BOARD PASS（`UDP_CAMERA_C1_PASS`），2026-09-08 |
| C1.1/C1.2 质量优化（双缓冲 + 分块拷贝 + 突发整形） | BOARD PASS（`C12_QUALITY_PASS`：1533+ 帧丢帧=0/CRC 错=0 @4.77 fps），2026-09-08 |
| C2 提速首轮（66ms 间隔） | BOARD PASS（`UDP_CAMERA_C12_FREEZE_PASS`：6.3 fps、丢帧/CRC ≈0.9%），2026-09-08 |
| UDP 相机帧色差（红蓝互换）根因修复（上位机 BGR 解码，板端零改动） | BOARD VISUAL PASS（`UDP_COLOR_FIX_BOARD_STREAM_VISUAL_PASS`），2026-09-08 |

## 归档目录

```text
competition/
├─ README.md
├─ 1_docs/      # 分类索引见 1_docs/README.md：doc/赛题方向/datasheets/figures/legacy/第三方资料(仅本地)
├─ 2_fpga/      # RTL/HLS、构建脚本、.bit/.xsa/.hwh、综合实现报告
├─ 3_host/      # 模型、上位机应用、部署脚本与清单
├─ 4_metrics/   # metrics.csv、原始日志、测试脚本、截图/波形证据
├─ 5_report/    # 设计报告、复现说明、归档清单
├─ 6_skill/     # 可复用 Skill 与工具说明
├─ 7_logs/      # 内部工程日志（不替代 4_metrics/ 下的提交证据）
├─ 8_tools/     # Builder、Win32DiskImager 等本机工具
└─ 9_pynq/sd/   # 面向写卡的基础/集成镜像归档和哈希清单
```

## 当前状态

- AMD 具身智能赛道已确定，应用场景已冻结为**视觉识别与自动分拣**；
- 设计方案已固化至 `1_docs/赛题方向/设计方案_具身智能视觉分拣.md`；
- HDMI ADV7511 RTL、实现、时序和板级显示已完成；
- PS UART 板级通信已验证；
- 2026-09-07 冻结 OV5640 → VDMA → DDR → VDMA → HDMI 可视化显示基线；
- 2026-09-08 主工程 PS 使能 ENET0（MIO16..27 + MDIO 52..53 + PHY 复位 MIO47），新 XSA/BIT 与 V3.1 固件（lwIP RAW UDP 回环 + 原 VDMA/HDMI 逻辑）板级验证通过：UDP 回环 `RX=TX` 且摄像头 HDMI 显示正常；
- 2026-09-08 板→PC UDP 视频流 B1 通过（1 fps 彩条、640 包/帧、921.6 KB/帧、丢帧/CRC=0），配套图形接收端 `EES331_UDP_Viewer.exe` 与协议设计文档；
- 2026-09-08 **C1.2 质量版固化**（`udp-camera-c12-pass-20260908`）：双缓冲快照 + 分块拷贝 + 突发整形 + 66ms 间隔（实测 6.3 fps、丢帧/CRC ≈0.9%），配对 BIT `7CB11F7D...` + ELF `3E295D51...` + XSA `30644B31...`；
- 2026-09-08 **UDP 色差修复固化**（`udp-color-fix-pass-20260908`）：相机帧红蓝互换根因为 VDMA 小端打包（UDP type=0x01 载荷字节序 `[B,G,R]`），上位机已按类型感知解码；**最新接收端为 `3_host/udp_video/dist/EES331_UDP_Viewer.exe`（31,187,867 B，SHA-256 `a4b75ed3...`，gui V1.2）**，板端零改动；证据 `4_metrics/logs/2026-09-08_udp_color_swap_fix_run01/`；
- CNN PS+PL 加速架构已有历史工程基础；
- 下一步：提速 15 FPS（C2.2：发送错误码诊断 + lwIP220 调参）→ 多轴 PWM 控制器开发 → 通信协议实现 → YOLO 部署 → 联调。

## GitHub

远程仓库：<https://github.com/pipidandan-superman/FPGA2026_competition>

## 开发原则

1. 区分赛题文件中的要求、当前工程已验证事实和未来计划。
2. 每次验证保存完整原始日志，不以摘要替代证据。
3. 先完成单任务实时闭环，再评估多任务和多传感器扩展。
4. 不将未通过综合、时序和板级验证的功能描述为已实现。

## SD/PYNQ 摄像头运行入口（2026-09-11）

使用 `9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img` 写卡后，SW8 保持 SD 启动即可自动运行摄像头业务。连接 OV5640、HDMI 和网线后上电，等待约 60 至 90 秒；`ees331-camera.service` 会自动加载 PL、配置 VDMA、输出 HDMI，并向 `192.168.240.2:5000` 发送 UDP 视频，无需启动 Vitis、JTAG 下载、Jupyter 或手动 Python。

PC 有线网卡设置为 `192.168.240.2/24`，然后运行 `3_host/udp_video/dist/EES331_UDP_Viewer.exe`。开发板业务地址为 `192.168.240.10/24`。当前结果为 `PYNQ_CAMERA_HDMI_UDP_PASS`、`SD_REBOOT_AUTOSTART_PASS` 和集成 IMG 板级复现 PASS；用户已确认 HDMI 与 PC 均显示随动作变化的实时画面。此前 PC 零帧现象由网线未连接导致，不是镜像或相机服务故障。

源码与部署说明见 `2_fpga/0_diaplay_test/pynq/README.md`，镜像入口和写卡说明见 `9_pynq/sd/README.md`，原始证据见 `4_metrics/logs/2026-09-11_pynq_camera_run01/REPORT.md`。若改刷 `9_pynq/sd/01_base_ees331` 中的 EES-331 最小系统 IMG，则仍需手工安装业务文件、CMA、网络和 systemd 服务；通用 PYNQ-Z2 镜像不再作为项目基线。

## SD Builder v0.2.2：指定部署包输出目录

[当前 EXE](8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.2.exe) 增加“部署包输出目录”输入和浏览选择。留空沿用默认位置；指定后生成独立子目录，复制 ZIP、可选 IMG 和校验清单并逐文件读回验证。清理后重新打包版本大小 22,464,864 字节，SHA-256 `b104e7ca7fcdf54d80382195c9374a459f71f68c62fa2593fe1cc4ec7ad5760b`，自检通过；默认 EES-331 基线已改为 `9_pynq/sd/01_base_ees331`。
