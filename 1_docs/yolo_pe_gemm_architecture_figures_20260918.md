# PE / GEMM 详细架构图

2026-09-18。根据 PE 与 GEMM 设计手册绘制的建议架构，不等同于实际 RTL 连线或综合网表。本次不修改 RTL。

## 1. PE 内部数据通路

![PE](figures/yolo_pe_detailed_architecture_20260918.png)

[SVG 矢量图](figures/yolo_pe_detailed_architecture_20260918.svg) · [PDF](figures/yolo_pe_detailed_architecture_20260918.pdf)

单 PE 用一颗 DSP48E1，对同一个 signed INT8 权重和两个 signed INT8 激活计算两个乘积。先解包，再分别进入 DSP 外的 INT32 累加器。图中给出打包、位宽、借位修正、权重延迟以及 E0/E1/E2/E3 采样事件。

## 2. GEMM 引擎总图

![GEMM](figures/yolo_gemm_detailed_architecture_20260918.png)

[SVG 矢量图](figures/yolo_gemm_detailed_architecture_20260918.svg) · [PDF](figures/yolo_gemm_detailed_architecture_20260918.pdf)

推荐起点为 TO=8、TN=16、Kc=576、单活动累加 tile，尾部 R=1 或 2。WBUF 双缓冲有效容量 9 KiB，XBUF 为 18 KiB。缓冲容量不等于物理 BRAM 颗数；后者由端口和 bank 布局决定。

参数和 LUT 的装载、W/X 发射和结果写回均由 PL 自主管理。控制连线为功能级抽象；cmd、completion、错误和 loader/bank 状态须按手册实现握手。图中的状态说明框不是独立数据通路模块。参数化尾部并行度 R 与模型矩阵维度 K、OC、N 不混用。

## 3. PE 阵列展开

![阵列](figures/yolo_gemm_pe_array_20260918.png)

[SVG 矢量图](figures/yolo_gemm_pe_array_20260918.svg) · [PDF](figures/yolo_gemm_pe_array_20260918.pdf)

8×16 指 128 个输出位置，由 8×8=64 个双乘积 PE 实现。每行共享一个权重，每列对共享两个激活，每输出位置保持独立 INT32 部分和。图中无连接点的交叉线不表示相连，省略行列和结果读出线只简化显示；所有有效累加器均接入分组读出选择器，不能理解成只读最后一行。

此处采用广播外积，不是相邻 PE 逐拍传递操作数的脉动阵列。扩展至 16×16 时，乘法核心变为 128 DSP，活动累加状态变为 8192 bit；尾部资源和控制另计。

## 来源与验证范围

- [PE 设计手册](yolo_pe_design_manual_20260918.md)
- [GEMM 设计手册](yolo_gemm_design_manual_20260918.md)
- [生成脚本、SHA-256 与检查记录](../4_metrics/logs/2026-09-18_yolo_pe_gemm_figures_run01/)

本次完成图形渲染和视觉检查，未运行新的 RTL 仿真、综合或板测。数值正确性和时序仍按两份手册各自的验证门验收。
