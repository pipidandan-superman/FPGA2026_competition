# 2026-09-18 验证摘要

## YOLO PL 硬件框图
按用户参考图绘制建议架构，使用可编辑 SVG 并导出 PNG/PDF。全网复用 GEMM，SiLU/Add/Concat/Pool/Upsample 在 PL，最终 DFL/Sigmoid/NMS 在 PS；特征缓存提供中间回流和 DDR 溢出。此图不是已完成 RTL 声明。
产物：[PNG](../../1_docs/figures/yolo_int8_pl_architecture_v2.png)、[SVG](../../1_docs/figures/yolo_int8_pl_architecture_v2.svg)、[PDF](../../1_docs/figures/yolo_int8_pl_architecture_v2.pdf)。
证据与生成脚本：[diagram run01](../../4_metrics/logs/2026-09-18_yolo_pl_diagram_run01/draw.py)。DIAGRAM_RENDER_PASS；已检查 PNG 标签和连线，修正输入箭头与重复 bias 表述。早期 yolo_int8_pl_hardware_block_diagram.svg 为未交付草图，v2 为交付版本。

## AXI-Lite CSR 架构设计
完成详细设计：[yolo_axi_lite_csr_design_20260918.md](../../1_docs/yolo_axi_lite_csr_design_20260918.md)。结论：32-bit AXI-Lite 控制面；固定控制状态使用 FF；descriptor/buffer/quant/LUT/result ring 使用模块内部推断 BRAM/LUTRAM；raw head 通过 DDR/HP 交给 PS 后处理。新设计要求 AW/W 独立握手、descriptor shadow/commit、结果 owner/seq/ack 协议，并兼容 0x43C1_0000 地址段。

## YOLO量化部署审查（完成）
证据：[audit run01](../../4_metrics/logs/2026-09-18_yolo_quant_audit_run01/)。
验证目标：包哈希一致、整数算术匹配、计算图闭合、软件准确率可复现；本轮不把 RTL/板测作为软件精度证据。
结果：包哈希 PASS；63 Conv 原始权重/偏置重建 PASS；5 深度样本、315 次独立 INT64 卷积 PASS；128 帧 raw-head SHA PASS；Add/Concat 分支尺度与边界算术 PASS。valid：FP32/INT8 mAP50 0.89394/0.90310，独立 mAP50-95 0.46252/0.47115。test：FP32/INT8 mAP50 0.72548/0.69213，独立 mAP50-95 0.42099/0.40528，INT8 mAP50 下降 0.03335，精度门未通过。
评估器问题：无预测类别被 AP 均值排除、NMS max_det 截断顺序存在边界缺陷；在本 128 帧上 NMS 集合无变化且各类均有预测，未改变旧数值。
完整报告：[yolo_quant_software_audit_20260918.md](../../1_docs/yolo_quant_software_audit_20260918.md)。原始证据：[audit run01](../../4_metrics/logs/2026-09-18_yolo_quant_audit_run01/)。
建议分区：PL 承担 63 Conv+SiLU、Add、Concat、MaxPool、Upsample；PS 只保留输入预处理和检测头 DFL/softmax/sigmoid/NMS。该分区在软件上保持同一 raw-head hash，见 `partition_result.json`。

## AXI-Lite CSR 子系统合同仿真（PASS，81/81）
证据：[sim run01](../../4_metrics/logs/2026-09-18_yolo_csr_sim_run01/)
（vivado_console.log / xsim.log / result.json / run_input_manifest.json）。
判定：EES_VIVADO_RESULT PASS + EES_SUMMARY checks=81 errors=0 + exit 0 +
无 fatal/error + 无看门狗触发 + 无 X/Z 拒绝。最终确认跑已移除全部临时探针。
覆盖：T1 身份/能力寄存器；T2 读写与 AW/W 两种到达顺序；T3 四表窗口读写 +
DESC_BASE 窗口搬移；T4 门铃全链（walker 取描述符→发布→结果环 w0/w1/w4/w10
入表→FRAME_DONE→RESULT_SEQ/HEAD_BYTES→ACK 消费）；T5 运行中写表 SLVERR +
E_CODE_TABLE_RUN + frame_end 门铃收帧 + W1C；T6 33 帧溢出（保留 32、SEQ=0x23、
溢出位）；T7 空环 ACK 协议错（排空后 bit9 + E_CODE_ACK_EMPTY）；T8 四条
SLVERR 路径（非对齐/未映射/环 RO/debug）。
批仿真链 5 个问题的修复全部留档于 console：启动器环境页式读取、ring 例化
端口名、RTL timescale 缺失、TB valid 悬挂死锁、desc 窗口地址合成 bit12 泄漏
（DUT 真实缺陷，wr_addr_w[13:0]-14'h1000 修复）。
方法沉淀：`6_skill/vita-vivado-batch-sim/references/xsim_ip_toolchain.tcl`。

## BD 集成（PASS，run01 第 4 轮）
证据：[bd run01](../../4_metrics/logs/2026-09-18_yolo_csr_bd_run01/)
（bd_integrate.tcl / vivado_console_bd_run4.log / result_bd_run4.json）。
判定：EES_VIVADO_RESULT PASS + exit 0 + validate 无 ERROR + BD 41-1348
异步复位 CRITICAL 清零。拓扑与地址已在落盘 display_test.bd 中逐项核对：
GP0→axi_ic0(1S1M)→u_yolo_csr @ 0x43C10000/64K；FCLK_CLK0→全部 ACLK +
rst_sys/slowest_sync_clk；FCLK_RESET0_N→仅 rst_sys/ext_reset_in；
rst_sys/peripheral_aresetn→ic ARESETN/S00/M00 + CSR s_axi_aresetn；
vcc_rst/dout→rst_sys/dcm_locked。XCI 证实 C_EXT_RESET_HIGH=0（value_src=
propagated，由低有效连接自动推导）。教训两条：① offset/range 只能设在
master 侧镜像段（processing_system7_0/Data/SEG_*），slave 侧只读；
② proc_sys_reset 极性参数只读勿手动 set，靠连接推导；dcm_locked 必须
显式绑 1，悬空综合成 0 = 板上永久复位。
待完成：synth/impl/bit（synth_bit.tcl 已就绪重跑）+ 资源/时序报告归档。

