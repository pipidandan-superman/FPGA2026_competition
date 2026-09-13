# 阶段状态与证据

## 2026-09-13：复位接线修复，寄存器板测通过

1000轮寄存器/命令、3次Overlay重载已实机通过；ARM MMIO库已在板端编译。UDP恢复60帧通过，用户已确认最终HDMI正常，独立寄存器阶段完整验收通过。当前发布包已替换为修复版，旧版完整归档，禁止再加载旧版。

根因是官方复位IP的低有效aux_reset_in接常量0，现改接常量1。纯RTL未改；新增官方IP复位仿真、HWH下载前门控、15项Python单测和实时持久化事件。构建100MHz时序/DRC通过。

[本次板测报告](../../../4_metrics/logs/2026-09-13_axilt_reg_board_run02/REPORT.md)。用户后续明确授权寄存器验收后集成主视频工程，BRAM仍未实现，不将原先两阶段全量集成要求混同本次寄存器范围集成。下方为历史记录，不代表当前状态。

## 最新：proj实体工程与指定BD已交付

已按用户新指令创建proj/AXI_LITE_test.xpr，BD精确命名AXI_LITE_test。
使用已通过仿真的相同4份.v源码，BD校验、综合、布局布线及bit生成通过。
新发布包位于proj/release/AXI_LITE_test.bit/.hwh/.xsa，设置/保持裕量2.925/0.013ns，
DRC错误/黑盒0，LUT719/FF1116。当前仍是寄存器阶段，未进行板测或主工程合并。
[BD工程说明](bd_design.md)；
[本轮回执](../../../4_metrics/logs/2026-09-12_axilt_local_project_run01/local_project_receipt.json)。
下方为上一轮隔离构建与板测接续记录；生成工程位置约定以本条及用户新指令为准。

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
