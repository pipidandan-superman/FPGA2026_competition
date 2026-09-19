# 2026-09-18 执行计划

## 任务B：PS-AXI-寄存器-PL（当前主线，P0 已完成）
1. ~~RTL 10 文件合规重构 + 顶层 V2001 化~~（完成）
2. ~~合同 TB 8 组 + 批仿真 TCL + 全绿~~（完成：run01，81/81 PASS）
3. ~~BD 集成（下一步）：GP0 使能 → Interconnect → Add Module(V2001 顶层) →
   0x43C1_0000/64KB → validate → 不动 axi_action~~（完成：run01 第 4 轮 PASS，
   proc_sys_reset 同步复位，41-1348 清零）
4. 综合/实现/bit + 资源时序报告归档 `4_metrics/logs/2026-09-18_yolo_csr_bd_run01/`
   （synth_bit.tcl 就绪，GUI PID 变更后经启动器重跑）
5. code-review skill 审 RTL；PS /dev/mem 冒烟（读 ID=0x594F4C32）
模块/工具职责：RTL 在 2_fpga/3_yolo_zynq/rtl/ps_axi_pl；批仿真走
run_vivado_batch_ees.ps1 + sim_yolo_csr.tcl（skill 模板已固化）；
BD/bit 在 proj/axi_test。
关键文件：yolo_control_subsystem.v（窗口地址合成本次修复点）、
yolo_desc_walker.sv（W_W0A/W_W0D 读时序）、tb_yolo_control_subsystem.sv。
风险与回退：BD Add Module 若不识别 SV 依赖→顶层已 V2001 化即可；
bit 后 PS 冒烟失败→回 03 验证摘要的仿真证据定位（表窗口/环协议）。

## 任务A：YOLO 量化部署审查（完成）
1. 读取 run04 量化源码/清单、PYNQ运行时及M11/M13证据。
2. 独立检查哈希、图拓扑、量化算术及关键反例，保存完整输出。
3. 对比整数参考、软件驱动、RTL承证范围；统计计算/存储预算。
4. 生成报告与网络计算图；校验日志路径。
工具：Python、PowerShell、只读源码审查；RTL审查应用 rtl-v-sv-style。
风险：历史PASS可能对应不同版本；板测未完成；小数据集不足以证明泛化。
退路：明确标注不能复现或未覆盖项，不扩大PASS范围。

