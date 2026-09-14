# PS–PL AXI-Lite / BRAM 独立验证工程

本目录是用户明确授权的独立开发区，当前实施**第一阶段：寄存器控制**。
第二阶段 BRAM 必须在寄存器板测通过后推进；不合并视频/蓝牙主工程。

## 当前入口

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

rtl/：源码；sim/：自检与协议激励；proj/：可重建脚本；
pynq/：软件驱动/板测；doc/：契约和证据索引。

构建时完整复制本目录到新的4_metrics/logs/<run>/source，生成Vivado工程和产物
位于该run，禁止将生成树放回源码目录。四份每日记录位于7_logs/YYYY-MM-DD。
BIT/HWH/XSA按同一构建的release目录成套使用。现阶段没有Git推送或主工程合并。

