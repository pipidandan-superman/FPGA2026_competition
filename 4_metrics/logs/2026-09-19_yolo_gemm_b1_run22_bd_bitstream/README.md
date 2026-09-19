# run22 — B1 BD 集成 + 综合 + 布局布线 + 比特流（axi_gemm_test）

日期：2026-09-19　　结果：**全绿**——`write_bitstream Complete!`

证据：`run22_console.log`（分阶段 EES 标记）、`impl_timing_summary.rpt`、
`impl_utilization.rpt`、`impl_drc.rpt`、`axi_gemm_test_wrapper.xsa`、
脚本 `run22_bd_bitstream.tcl`；产物
`proj/axi_gemm_test/axi_gemm_test.runs/impl_1/display_test_wrapper.bit`（4,045,696 B）。

## 工程变更（用户指令："bd继续扩展…注意添加的rtl…不要copy，引用即可"）

1. **源引用**（add_files 无拷贝，`$PPRDIR/../../rtl/GEMM/…` 原位）：
   10 RTL（yolo_pe_pack.v + 7 个 .sv 中间层 + yolo_gemm_top.v）+
   6 IP .xci（4×bank TDP BMG + LUT BMG + ycap BMG）。`EES_BD_SRC` 逐条
   取证解析路径全在 rtl/ 原位。
2. **BD**（display_test.bd，save 后 JSON 真值验证）：
   - axi_ic0 `NUM_MI 1→2`；
   - `create_bd_cell -type module -reference yolo_gemm_top u_yolo_gemm`
     （与 u_yolo_csr 同 module_ref 机制；自动生成
     `display_test_u_yolo_gemm_0` 综合文件集）；
   - M01_AXI→s_axi；FCLK_CLK0→{M01_ACLK, s_axi_aclk}；
     peripheral_aresetn→{M01_ARESETN, s_axi_aresetn}（网成员
     `EES_BD_NETCLK_*` 全列取证，逐项复刻 u_yolo_csr 现网模式）；
   - 地址 `assign_bd_address -offset 0x43C00000 -range 0x10000`
     （u_yolo_csr 0x43C10000 原样未扰动——.bd 双值验证）；
   - `validate_bd_design` 无错误。
3. **构建**：清空旧工程增量检查点 → reset_run → 全新
   synth→impl→write_bitstream（-jobs 4）。

## 结果判据

| 项 | 值 | 判读 |
|---|---|---|
| 时序 | **WNS +4.954 ns / WHS +0.024 ns**，0 failing endpoints | 50MHz FCLK0 全约束满足；与 core 100MHz WNS+1.392（run20）的 2× 余量预期一致 |
| DSP | **68** | 与 run16/20 OOC 核心资源判据精确一致（64 阵列+4 尾乘）→ GEMM 数据通路真实在网表，无黑盒 |
| BRAM | 21 tile（15%） | GEMM 12×BRAM36+RAMB18 + 原设计 5 个 yolo_*_bram |
| LUT/FF/Slice | 8647 / 7512 / 3323（16.3%/7.1%/25.0%） | 轻负载 |
| DRC | **0 违例**（无 Black Boxes） | — |
| 层级 | routed 网表含 `u_yolo_gemm_0` | module_ref 例化被综合消费 |

综合前 XDC 评估的 "unresolved black boxes" WARNING [Project 1-498] 为
预综合读约束的标准行为，最终 DRC 无黑盒、资源对账闭合——非问题。

## 2025.2 工程模式 Tcl 坑（attempt1-6 逐个踩掉，全部已绕）

1. `get_modules` 命令不存在（工程模式无此 API）；
2. `-compile_order` 不列 top 未引用模块——module_ref 例化前
   yolo_gemm_top 不可达，鸡生蛋，不能用作在场检查；
3. file 对象无 `LOCATION` 属性——对象名字符串即解析路径；
4. 地址段 `set_property offset` 只读——正典 =
   `assign_bd_address -offset 0x43C00000 -range 0x10000 [segs]`；
5. `get_bd_pins` 配套选项是 `-of_objects`（无 `-of_nets`）；
6. 地址段对象的 offset 属性读回为空——取证真值 = 保存后的 .bd JSON。

## 板级窗口（B1 晨验，用户在场时执行）

比特流/XSA 就绪：`display_test_wrapper.bit` + `axi_gemm_test_wrapper.xsa`。
板测序列 = run21 TB 的 AXI-Lite 寄存器序列（PS 直驱 0x43C00000），
金 tile 预期值 = run21 oracle（S1 场景）。

## run22b 修复（2026-09-19 16:2x–16:30，GUI 并发会话踩踏事故）

**事故**：run22 全绿后用户在 GUI 打开工程报 BD 错
（[BD 41-1712/1726/2160/2164, IP_Flow 19-5622] Unable to resolve module-source
for u_yolo_gemm）→ 用户在 GUI 里重生成比特流失败并中止。根因：**GUI 会话
是批处理跑之前打开的，内存里是旧工程态（无 GEMM 源引用）**，module_ref
自然解析不了；GUI 退出时的保存把 `.xpr` 回写踩掉（16:09:06，GEMM 引用
清零），中止的实现跑又把 impl_1 留在半复位态。`.bd` 本体 / synth dcp /
run22 xsa 均未受损——设计零损失，纯工程元数据踩踏。

**修复**（`run22b_repair.tcl`，证据 `run22b_console.log`）：
- Stage A：16 个源引用重加（引用式，`EES_FIX_SRC` 逐条取证在 rtl/ 原位）；
- Stage B：BD 重开 → u_yolo_gemm cell + s_axi 解析 → validate → save →
  .bd JSON 双地址（0x43C00000/0x43C10000）验证无损；
- Stage C：**教训 = 用户中止的实现跑留下 `opt_design` 需 reset 的半复位态，
  必须 `reset_run impl_1`（synth 被标脏时再 reset synth_1）才能 launch**；
  全链重建至 write_bitstream Complete!；
- 落盘：显式 `close_project`（不依赖 exit 隐式保存）。

**修复判据 = 与原跑逐位同值**：bit 4,045,696 B、WNS+4.954/WHS+0.024、
DSP=68、LUT 8647、DRC 0 违例全部一致；`.xpr`（16:29:36）15 处 GEMM 引用
恢复（$PPRDIR/../../rtl/ 引用式）。xsa 16:30:08 再生。

**规程沉淀**：批处理要改工程时，用户 GUI 必须先关（本轮用户已配合）；
反之批处理跑动中 GUI 也不得开同一工程。两头都是"旧内存态保存会踩掉
磁盘真值"。
