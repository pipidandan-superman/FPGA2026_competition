# AXI_LITE_test：实体BD工程

本次按用户指定在proj内创建实体工程，BD精确命名为AXI_LITE_test。
打开 [AXI_LITE_test.xpr](../proj/AXI_LITE_test.xpr)，在IP INTEGRATOR选择Open Block Design。

## 顶层与连接

2026-09-13修复：control_reset的aux_reset_in低有效，现与dcm_locked共同接const_one，mb_debug_sys_rst接const_zero。先前aux接0的位流已归档且禁止加载。新增官方复位IP仿真、HWH接线门控及1000轮/3次重载板测，详见[本次报告](../../../4_metrics/logs/2026-09-13_axilt_reg_board_run02/REPORT.md)。

- 自研模块顶层：[axi_lite_test_top.v](../rtl/axi_lite_test_top.v)。
  含AXI、时钟和复位接口标注；先Add Sources加入rtl下四个.v文件，
  即可从Sources将axi_lite_test_top作为Module Reference加入BD，也可使用Add Module。
- 系统包装：AXI_LITE_test_wrapper.v，由BD自动生成，综合顶层选择该wrapper。
- BD实例axi_lite_test_0对应自研模块；PS GP0经过SmartConnect连接S_AXI。
- FCLK_CLK0同时驱动GP0_ACLK、SmartConnect、寄存器模块及复位控制器。
- FCLK_RESET0_N进入proc_sys_reset，自动传播并核验低有效极性。
- 寄存器窗口0x43C00000–0x43C00FFF；本期没有DMA或BRAM外设。

工程通过相对路径直接引用独立rtl与sim目录，不引用临时证据目录源码。
仿真顶层tb_axi_lite及延迟后端测试也已登记到工程。

## 已核对的板级参数

参数来自既有已实现display_test工程的PS配置快照，不需要本轮重新解析手册。
实际新HWH已核对如下：

| 参数 | 值 |
|---|---|
| Vivado / 器件 | 2025.2 / xc7z020clg484-1 |
| PS晶振 | 33.333333 MHz |
| ARM频率 | 666.666687 MHz |
| DDR型号 | MT41K256M16 RE-15E |
| DDR总线 / 时钟 | 32 Bit / 533.333374 MHz |
| PS Bank0 / Bank1 | LVCMOS 3.3V / 1.8V |
| PL控制时钟 | 100 MHz |
| AXI寄存器数据宽度 | 32 bit |

不将PS的初始化导出文件当作本轮已重新启动或重新初始化板卡的证据。

## 构建结果与产物

综合、布局布线、write_bitstream通过。LUT719、FF1116、BRAM0、DSP0。
设置/保持裕量2.925/0.013ns；DRC错误0、黑盒0。

- [BIT](../proj/release/AXI_LITE_test.bit)
- [HWH](../proj/release/AXI_LITE_test.hwh)
- [XSA](../proj/release/AXI_LITE_test.xsa)
- [哈希清单](../proj/release/artifact_manifest.json)
- [本轮原始证据](../../../4_metrics/logs/2026-09-12_axilt_local_project_run01/)

实际实现输出也在proj/AXI_LITE_test.runs/impl_1/AXI_LITE_test_wrapper.bit。
release副本与实现产物、XSA内顶层bit/hwh一致。PYNQ成套使用AXI_LITE_test.bit/.hwh，
不混用此前axilt命名的旧发布包。

已存在工程不由create_local_project.ps1覆盖；GUI正常打开后可继续开发。
每次修改先记录源码快照和对应仿真，再对本独立工程执行综合/实现，
新结果另建证据目录并更新release配对清单。

本次范围截至生成bit，不做板卡下载、不合并主工程。
