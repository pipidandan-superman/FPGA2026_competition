# 阶段状态与证据

更新：2026-09-12。状态：**REG_SIM_PASS / REG_BUILD_PASS / REG_BOARD_PENDING**。
用户授权的完整计划尚未全部完成；BRAM实现/验证在寄存器板测之后。

## 已完成

- 自研AXI-Lite协议层、寄存器层、执行器、集成顶层。
- 主仿真26,282项检查、1,001条命令、3个固定种子；延迟业务后端单独通过。
- Vivado2025.2布局布线和位流生成；LUT719、FF1116、BRAM0、DSP0。
- 设置/保持裕量2.925/0.013ns，DRC错误0、黑盒0、未约束内部端点0。
- 配对BIT/HWH/XSA及哈希清单。HWH核对CSR=0x43C00000/4KiB、控制时钟100MHz。
- Python驱动、ARM有序MMIO C源码、1000轮及三次重载板测脚本、演示Notebook。
- 8项驱动离线单测通过。ARM C库尚未在板端编译，PYNQ脚本尚未实机运行。

## 证据入口

- [最终寄存器仿真](../../../4_metrics/logs/2026-09-12_axilt_reg_sim_run02/vivado_console.log)
- [仿真进程回执](../../../4_metrics/logs/2026-09-12_axilt_reg_sim_run02/process_status.json)
- [成功构建](../../../4_metrics/logs/2026-09-12_axilt_reg_build_run03/vivado_console.log)
- [时序报告](../../../4_metrics/logs/2026-09-12_axilt_reg_build_run03/timing.rpt)
- [资源报告](../../../4_metrics/logs/2026-09-12_axilt_reg_build_run03/utilization.rpt)
- [配对发布目录](../../../4_metrics/logs/2026-09-12_axilt_reg_build_run03/release/)
- [交付哈希清单](../../../4_metrics/logs/2026-09-12_axilt_reg_build_run03/release/artifact_manifest.json)
- [最终软件与只读板卡检查](../../../4_metrics/logs/2026-09-12_axilt_offline_run02/result.json)

## 保留的失败与警告

- smoke_run01：GUI环境读取失败，未启动RTL。
- smoke_run02：生成Tcl含UTF-8 BOM，已改为ASCII wrapper。
- smoke_run03：XSim实际通过，旧wrapper错误使用LASTEXITCODE误报，现改读process_status。
- build_run01：逐项恢复PS参数导致电压设置顺序冲突，现改为一次性配置字典。
- build_run02：工具版本将复位极性参数设为只读、模块地址段实际名称不同；
  改为自动传播后检查极性，并按接口查找唯一地址段。
- release初次检查将SmartConnect子级HWH也计入顶层，现精确匹配axilt.hwh。
- 仿真有无RTL timescale及测试台声明顺序警告；未影响不含延时语句的同步RTL，
  两轮仿真均自然结束。综合实现无关键警告/错误。

## 未完成与接续

板卡192.168.240.10未返回SSH横幅，最终socket检查超时；Windows无COM6枚举。
这只说明当前无法执行PYNQ验收，不推断板卡硬件故障或实际启动模式。

下一步：确认SD启动PYNQ与以太网连通，使用validation.md的板端命令，
完成寄存器实机验收及原视频恢复，然后推进BRAM。
未操作板卡、未停视频服务、未修改原视频/蓝牙工程、未合并或push。
