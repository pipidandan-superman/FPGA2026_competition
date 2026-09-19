# 2026-09-18 日计划

## 任务A：YOLO量化部署审查
当前判断：run04 为待核实量化候选，软件、仿真与板测分开判定。
目标：审查现有量化推理正确性，生成实际网络计算图与硬件映射建议。
任务：核对包哈希与数值合同；复查运行时、golden及精度证据；输出图和风险排序。
非目标：不修改冻结 2_fpga，不启动板卡重配置或模型训练。
交付：审查报告、计算图、可复现审查证据。

## 任务B：YOLO PL AXI-Lite CSR 与表存储（本会话新增）
当前判断：设计合同已冻结（`1_docs/yolo_axi_lite_csr_design_20260918.md`）；
`rtl/ps_axi_pl/` 本日新建；5 个 BMG IP 已由 IP Catalog 生成（输出寄存全关，
读延迟 1 拍）；BD 现状仅 PS7 且 `PCW_USE_M_AXI_GP0=0`。
目标：按合同完成 CSR 子系统 RTL + 合同仿真全绿 + BD 集成 0x43C1_0000 + 出 bit。
任务（优先级）：
- P0 RTL 按 rtl-coding-standards 重构（EES-331 文件头/FSM三块/_i/_o/单语句行）
- P0 TB 合同仿真全绿（vita-vivado-batch-sim 启动器 + 4_metrics/logs run 目录）
- P1 BD 集成 + validate + 综合/实现/bit
- P2 code-review skill 审查
非目标：不动 axi_action(0x43C0_0000)；不实现 63 Conv 引擎；不启用 HP 口。
交付：`rtl/ps_axi_pl/*.sv` + BMG XCI + 仿真证据 + bit + 四件套更新。
用户三条现场指示（约束）：①模块内 IP 直接例化真实 Xilinx IP（注意输出寄存
时序）；②不许行为级/参数化描述冒充 IP；③能用 BRAM 尽量 BRAM。
④（追加）顶层必须是纯 Verilog-2001（.v），否则 BD Add Module 不识别。

## 任务B进展（当日）
- RTL 合规重构完成：10 文件全部换 EES-331 头/三块 FSM(walker V2.0/ring V2.0)/
  _i/_o 端口后缀；顶层转 `yolo_control_subsystem.v`（V2001，pkg 常量内联）。
- 重构中修复 3 个真实缺陷：walker BMG 读数据早采 1 拍（加 W_W0A/W_W0D 等待态）；
  regfile `irq` 输出悬空未驱动；顶层 `.soft_reset(1'b0)` 未接 ctrl_sreset。
- lint：xvlog 全部 11 文件（10 SV + 1 V）EXIT=0（临时目录 lint，非仿真证据）。
- TB：`tb/tb_yolo_control_subsystem.sv` 8 组合同测试 + EES 标记 + watchdog。
- 批仿真 TCL：`4_metrics/logs/2026-09-18_yolo_csr_sim_run01/sim_yolo_csr.tcl`
  （IP generate + xvlog/xelab -L blk_mem_gen_v8_4_12/xsim）。
- 阻塞：无 Vivado GUI 进程，启动器 -GuiPid 无从取——等用户开 GUI 后跑批仿真。

## 任务B进展（续：批仿真全绿）
- **P0 达成：合同仿真 81/81 全绿 PASS**（run01 目录，无看门狗、无 X/Z、
  exit 0 + PASS 标记，result.json state=PASS）。
- 仿真链 5 次迭代打通（每步证据见 03）：
  ① 启动器环境读取改页式 ReadProcessMemory（修"Cannot read environment"）；
  ② ring 内部例化端口名修复（xelab VRFC 10-3180）；
  ③ 11 个 RTL 全补 `timescale 1ns/1ps`（XSIM 43-4099 混合 timescale 拒绝）；
  ④ TB 驱动任务 NBA 时序缺陷（valid 悬挂 → aw_first 死锁看门狗）修复；
  ⑤ **DUT 真实 bug：desc 窗口地址合成**——8KB 窗口基址 0x1000 的 bit12
  泄入 [12:2] 切片，写入落在 1024+n 而非 n；改为显式减窗口基址
  （wr/rd_addr_w[13:0] - 14'h1000 再取 [12:2]），walker 即读到真描述符。
- TB 自身 2 处编码修正：T5 word0 0x0201→0x0101（bit8 才是 valid）；
  T7 排空改"ack 到空为止"有界循环（固定 32 次会把 tail 推过头）。
- 用户现场指示 ⑤：TDP BMG 底层是同一块物理 RAM，同址读写冲突必须结构性
  规避——已落实：tbl_locked=walker 非 idle 全程锁表写入；ring 靠 head/tail
  指针纪律（PS 只读已发布项、满则丢弃不覆写）；顶层注释写明不变式。
- **skill 固化完成**：`6_skill/vita-vivado-batch-sim/` 新增
  `references/xsim_ip_toolchain.tcl`（四阶段模板）+ SKILL.md 追加
  "Direct xsim toolchain for IP-based RTL"章节（exec 裸 exe、-L 预编译库、
  timescale 规则、TDP 冲突规避、无波形调试法）。

## 任务B进展（续：BD 集成收敛）
- **BD 集成完成（run01 第 4 轮 PASS）**：display_test BD = PS7(GP0+FCLK0
  100MHz+FCLK_RESET0_N) → axi_ic0(1S1M) → u_yolo_csr(模块引用 V2001 顶层)
  映射 **0x43C1_0000/64KB**；validate 无 ERROR；BD 已 save。
- 复位架构升级：直连 FCLK_RESET0_N 引发 4× BD 41-1348 CRITICAL（异步复位
  释放 recovery 风险）→ 加 proc_sys_reset 5.0 rst_sys + xlconstant：
  ext_reset_in=FCLK_RESET0_N（C_EXT_RESET_HIGH 由连接自动推导为 0=低有效，
  41-737 告警即手动 set 被拒，无害）、dcm_locked 绑 1（不绑则综合成 0=
  永久复位陷阱）、peripheral_aresetn→ic 三口+CSR aresetn。41-1348 全清。
- 脚本 `bd_integrate.tcl` 全程幂等（net_on/inet_on 守卫 + 旧复位网
  delete_bd_objs 重连），重跑收敛；证据 bd_run4 副本已留
  （vivado_console_bd_run4.log / result_bd_run4.json）。
- 综合启动时原 GUI(PID 23716) 已被关闭，经 settings64.bat + vivado.bat
  重新拉起 GUI 后继续；synth_bit.tcl（reset_run→launch_runs -to_step
  write_bitstream→utilization/timing 报告归档 run 目录）就绪待跑。

