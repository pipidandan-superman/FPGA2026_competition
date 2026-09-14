# PS–PL AXI-Lite：寄存器阶段交付

状态：REG_SIM_PASS / REG_BUILD_PASS / SOFTWARE_OFFLINE_PASS / REG_BOARD_PENDING。
完整用户计划仍未完成；按用户明确的验收顺序，BRAM阶段尚未开始。

## 已实现与测试

独立开发区：E:/competition/2_fpga/2_axi_lite_test。
自研axi_lite_slave、axi_lite_reg_bank、reg_test_executor、axi_lite_test_top，
以及PYNQ驱动、ARM有序MMIO辅助层源码、板测脚本、Notebook与可重建Vivado脚本。

- [最终RTL仿真](../2026-09-12_axilt_reg_sim_run02/vivado_console.log)：
  26282项检查、1001条命令、随机种子1/7/12345；延迟后端AXILT_DELAYED_BACKEND_PASS。
  正式失败/通过均以自然退出及process_status为准。
- [成功构建](../2026-09-12_axilt_reg_build_run03/process_status.json)：
  Vivado2025.2、xc7z020clg484-1、100MHz控制域。
  设置/保持裕量2.925/0.013ns；LUT719、FF1116、BRAM0、DSP0；
  DRC错误0、黑盒0、无时钟端点0、未约束内部端点0。
- [发布清单](../2026-09-12_axilt_reg_build_run03/release/artifact_manifest.json)：
  BIT/HWH与XSA顶层成员逐字节一致；CSR=0x43C00000/4096B，
  HWH实际100MHz及低有效外部复位通过。
- [8项驱动单测](../2026-09-12_axilt_offline_run02/driver_tests.txt)：
  含重复拒绝、回绕拒绝、错误结果不ACK、超时不自动重试。
- [交付审计](handoff_audit.json)：4份当前RTL与构建/仿真快照SHA一致；
  原视频BIT/HWH保持不变，15个入口链接存在。
- 项目13项技能路径审计通过，原始输出在offline_run02/skill_path_audit.txt。

## 未完成与阻塞证据

[板卡只读探测](../2026-09-12_axilt_offline_run02/board_preflight.json)：
192.168.240.10:22超时；此前SSH banner exchange也超时，Windows未枚举COM6。
没有执行板端程序、停止服务、重新编程、修改网络或重启板卡。
ARM C helper尚未板端编译，PYNQ实际MMIO与1000轮/三次重载尚未验收。
不把离线fake backend或TCP连接返回当成板测PASS。

接续条件：用户确认SD启动PYNQ和网线连通后，执行独立pynq/board_test.py，
校验实际Python/MMIO环境，测试期间暂时停止原视频服务，完成后恢复并复验视频。
然后才进入BRAM模块与官方IP仿真/板测。当前不合并主工程、不push。

## 保留失败

smoke_run01 GUI环境读取失败；smoke_run02 Tcl BOM；
smoke_run03实测通过但旧wrapper误判返回码，已修复；
build_run01 PS逐项配置顺序失败；build_run02只读复位参数及地址段名字错误；
build_run03最终通过。
初次发布检查误把SmartConnect子HWH计为顶层已修正。
offline_run02/handoff_audit.json中的FAIL是PowerShell JSON数组未展开的审计脚本错误，
不是硬件差异；本run修正数组枚举与UTF-8读取后全部通过。旧结果保留。

原始运行脚本/源码快照均保留。最终源码快照为本run/handoff_source，
构建快照和最后仿真快照中的RTL未变。波形默认不记录，自动产生的小WDB已移除；
完整控制台记录是本阶段仿真证据。

