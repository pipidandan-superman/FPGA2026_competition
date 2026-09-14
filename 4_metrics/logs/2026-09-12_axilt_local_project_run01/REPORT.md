# proj实体Vivado工程：AXI_LITE_test

结果：AXI_LITE_TEST_LOCAL_PROJECT_PASS。用户要求的工程创建、BD设计、综合、
布局布线和比特流生成均已完成。没有板卡下载或主工程合并。

## 位置

- 工程：E:/competition/2_fpga/2_axi_lite_test/proj/AXI_LITE_test.xpr
- BD：proj/AXI_LITE_test.srcs/sources_1/bd/AXI_LITE_test/AXI_LITE_test.bd
- .v模块顶层：独立rtl/axi_lite_test_top.v，实例axi_lite_test_0。
- 综合顶层：AXI_LITE_test_wrapper.v。
- 发布：proj/release/AXI_LITE_test.bit、AXI_LITE_test.hwh、AXI_LITE_test.xsa。

此次实体工程/生成树保存在proj是用户明确的新指令；
覆盖上一轮生成工程只能在证据run中的任务位置约定。
完整日志、参数、输入快照与产物副本仍在本run，四份工程日记在7_logs。

## 前置验证与关键设计

rtl_simulation_gate.json证明四份RTL与reg_sim_run02通过版本的SHA一致。
该仿真有26282项检查、1001条命令、三种子及延迟后端通过，未修改RTL后重贴旧PASS。
新工程引用../rtl的实时源码，并将tb_axi_lite与tb_slave_delay加入sim_1。

PS GP0 -> 官方SmartConnect -> 自研AXI-Lite寄存器模块，100MHz单控制域；
低有效FCLK_RESET0_N经proc_sys_reset同步释放。
CSR=0x43C00000/4KiB，BD名称AXI_LITE_test，器件xc7z020clg484-1。
板级PS参数从既有display_test.bd快照提取，无需读取手册PDF；
输出HWH验证33.333333MHz PS晶振、666.666687MHz ARM、
MT41K256M16 RE-15E / 32Bit / 533.333374MHz DDR及3.3V/1.8V MIO banks。
本期仅寄存器测试，BRAM未添加。

## 验收

- process_status.json：PASS，exit_code=0，无错误/关键警告。
- build_metrics.txt：SETUP_SLACK=2.925ns、HOLD_SLACK=0.013ns、黑盒0、DRC错误0。
- utilization.rpt：LUT719、FF1116、BRAM0、DSP0。
- release/artifact_manifest.json：顶层BIT/HWH与XSA内部成员逐字节一致；
  100MHz、CSR窗口和复位极性核验通过。
- local_project_receipt.json：实体XPR、BD及本地release交付成功。
- project_run_logs/：各个OOC、综合和实现run的完整原始日志/报告/启动脚本。
- recreate_bd.tcl：已保存的BD重建脚本。
- post_build_audit.json：源码引用、文件存在性、前后基线哈希和本地发布一致性检查。

运行中未遇到新的Vivado错误。原GUI环境读取问题已有本会话官方启动脚本
smoke_run03成功依据，本次直接复用已验证standalone后端，不重试错误的RDI环境。

## 产物SHA-256

BIT：5763f8e9adf8f1f1a59ec2fc72a6bdc9131e75feb5fdc4290529b64a39090f5f
HWH：931fb11a7cb4ab624534013d6c9a901ce77461793de42d076063d7d70e9a8040
XSA：a4ab3334482200e84728f120d2532d7fbc008b855f6b7edd6d8557e0ec353142

下一步可在Vivado直接打开本地XPR查看BD、添加/编辑模块。
若继续PYNQ实机阶段，使用新命名的成套release；板测状态仍PENDING。

