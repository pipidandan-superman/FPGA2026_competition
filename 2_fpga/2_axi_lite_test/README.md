# PS–PL AXI-Lite / BRAM 独立验证工程

本目录是用户明确授权的独立开发区，当前实施**第一阶段：寄存器控制**。
第二阶段 BRAM 尚未实现。用户2026-09-13新增授权：独立寄存器验收后，先进行已验证寄存器功能的主视频工程集成及共存验收，不将BRAM混入。

## 当前入口

2026-09-13修复版：官方复位IP辅助输入改接非有效电平，1000轮寄存器/命令及3次重载通过，UDP恢复通过，HDMI最终确认单列。旧错误位流保留在证据目录，不再用于下载。[板测与故障报告](../../4_metrics/logs/2026-09-13_axilt_reg_board_run02/REPORT.md)。

- [Vivado实体工程](proj/AXI_LITE_test.xpr)：BD名称为AXI_LITE_test。
- [BD设计文件](proj/AXI_LITE_test.srcs/sources_1/bd/AXI_LITE_test/AXI_LITE_test.bd)
- [实体工程创建脚本](proj/create_local_project.ps1)
- [BD结构、板级参数与产物](doc/bd_design.md)

- [架构、寄存器及接口契约](doc/register_abi.md)
- [验收、构建与板测操作](doc/validation.md)
- [阶段与证据索引](doc/status.md)
- [Vivado重建入口](proj/run.ps1)
- [PYNQ驱动](pynq/axilt.py)
- [正式板测脚本](pynq/board_test.py)
- [交互演示](pynq/demo.ipynb)

## 分工与模块

PS/PYNQ加载BIT/HWH、发起MMIO、检查序号/结果、超时和记录证据。
PL自研五通道AXI-Lite协议、寄存器权限/字节使能、命令锁存和执行。

```text
PYNQ / PS M_AXI_GP0
   -> 官方 SmartConnect
      -> axi_lite_slave
         -> axi_lite_reg_bank
            -> reg_test_executor
```

协议层与寄存器层有独立ready/valid请求和响应；双向都允许业务后端延迟。
PS、SmartConnect、复位IP为官方IP。FPGA器件xc7z020clg484-1，Vivado2025.2。
目标控制时钟100MHz，复位经proc_sys_reset同步释放。
CSR测试窗口0x43C00000/4KiB；驱动从HWH读取，合并时可重新分配。

第二阶段将增加 bram_portb_adapter、bram_loopback_engine、
官方单端口AXI BRAM Controller及4KiB TDP RAM，不提前宣称这些模块已完成。

## 保存方式

rtl/：源码；sim/：自检与协议激励；proj/：实体Vivado工程及可重建脚本；
pynq/：软件驱动/板测；doc/：契约和证据索引。

按用户2026-09-12最新指定，实体工程及生成树保存在proj，完整构建证据另存
4_metrics/logs/<run>。run.ps1仍提供run内隔离仿真/构建；源码快照排除实体工程生成树。
proj/release保留与本次工程配对的BIT/HWH/XSA及哈希清单。
四份每日记录位于7_logs/YYYY-MM-DD。现阶段没有Git推送或主工程合并。
