# 2026-09-03 HDMI 工程布局失败分析

## 结论

综合已完成；失败发生在 Vivado `place_design` 的 IO Clock Placer 阶段，尚未进入 `route_design`。主要错误是：

```text
ERROR: [Place 30-574] Poor placement for routing between an IO pin and BUFG.
ERROR: [Place 30-99] Placer failed with error: 'IO Clock Placer failed'
```

Vivado 指出的对象是相机像素时钟：

```text
cam_pclk_0_IBUF_inst (IBUF.O) is locked to IOB_X1Y36
cam_pclk_0_IBUF_BUFG_inst (BUFG.I) is provisionally placed on BUFGCTRL_X0Y0
< set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_0_IBUF] >
```

`cam_pclk_0` 在 XDC 中分配到 `AA22`。用 XC7Z020 CLG484 器件库查询，`AA22` 属于 Bank 33，封装功能是普通 IO：

```text
AA22: BANK=33, PIN_FUNC=IO_L7P_T1_33
```

它不是 `MRCC`/`SRCC` 时钟能力引脚。而 `cam_captrue_data` 中 `cam_pclk` 被用作多组寄存器的采样时钟，并通过 `vid_clk` 输出，因此综合器会为其插入全局时钟缓冲。普通 IO 到 BUFG 不满足专用时钟规则，导致 IO Clock Placer 失败。

这不是 HDMI 新增 23 个引脚的引脚冲突，也不是资源不足或一般布线拥塞。

## 待确认修复方案

### 方案 A：先按 Vivado 建议降级该时钟规则

在 XDC 增加：

```tcl
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_0_IBUF]
create_clock -period <camera_pclk_period_ns> -name cam_pclk [get_ports cam_pclk_0]
```

优点：不修改 RTL/BD，能最快让布局继续；OV5640 PCLK 频率通常较低，可能可以满足采集时序。

缺点/风险：Vivado 明确说明该覆盖“highly discouraged”；IO 到 BUFG 使用非专用路径，时钟插入延迟和偏斜不可控；必须重点检查 WNS/TNS/Hold，不能仅以实现完成判定成功。

### 方案 B：改造相机 PCLK 时钟结构

把相机采样逻辑改为不把 `AA22` 普通输入当作全局时钟，例如基于稳定系统时钟过采样并同步相机信号，或调整硬件/引脚使 PCLK 进入时钟能力引脚。

优点：时钟结构更规范，避免非专用时钟路径带来的不确定性。

缺点/风险：采集 RTL/BD 需要修改并重新验证；板卡引脚 `AA22` 由手册固定，若不改硬件，必须改采样架构；工作量和验证范围明显大于方案 A。

## 当前建议

建议先采用方案 A 作为阻塞解除手段，并把它视为“实现可继续”而不是最终时序结论。重新实现后必须审查时序报告；若相机时钟域 WNS/Hold 不合格，再进入方案 B。

## 证据

- 原始实现日志：`vivado_impl_runme.txt`
- Opt 后 DRC：`display_test_wrapper_drc_opted.rpt`
- AA22 器件能力查询：`pin_capability_vivado.txt`
- 相机 PCLK 使用点：`E:\competition\2_fpga\0_diaplay_test\rtl\ov5640_data_cap\cam_cap_data.v`
