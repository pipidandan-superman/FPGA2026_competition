# run21 — B1 GEMM 顶层 AXI-Lite 块级仿真门（yolo_gemm_top V1.0）

日期：2026-09-19　　结果：**PASS ×2**（checks=544 rb_checks=417 errors=0，两轮逐数一致）

证据：`sim_top_console_pass1.log` / `sim_top_console_pass2.log`（EES_SUMMARY 行）、
`sim_gemm_top_axi.tcl`（编译/仿真正典）、`gen_ycap_ip.tcl` + `gen_ycap_ip_console.log`
（Y 捕获 BMG IP 生成）。

## 被测件

- `rtl/GEMM/yolo_gemm_top.v` **V1.0**（纯 Verilog-2001，BD Add Module 硬约束）：
  AXI4-Lite 寄存器文件 + `yolo_gemm_core` V1.1（run15/19 绿件）+
  Y 捕获 RAM `gemm_bm_ycap`（BMG SDP 8×128，.veo 逐端口例化）。
- 全真 IP 集合在线：4×bank TDP BMG + LUT BMG + ycap BMG + DSP48E1 PE
  （blk_mem_gen/unisim 库 + glbl）。
- 附带实证：**.v 顶层例化 .sv 子模块与 BD Add Module 同构路径可编译可仿真**
  （CSR 子系统先例的仿真侧补证）。

## TB = PS 角色（上板序列即本 TB 的寄存器写读序列）

`rtl/GEMM/tb/tb_yolo_gemm_top_axi.sv`：纯 AXI-Lite 驱动，core 信号只观察；
oracle 逐字承袭 run15（INT64 requant + RNE ties-even + 饱和 + LUT/旁路）；
活流 eq 队列 + tile_done 后 RAM 回读双重对拍。

| 场景 | 覆盖 | 活检 | 回检 |
|---|---|---|---|
| S1 全 8×16 K=64 act=1 | 装载/参数/LUT/start/轮询/回读全链 | 128 | 128 |
| S2 掩码 0x5A/0x0F0F K=40 act=0 | y_count=32、掩外坐标保旧值（无幻影写） | +32 | +33 |
| S3 双块 K=96（48+48 grp 乒乓） | 跨块累加 + 计算窗内并发装载对组 | +128 | +128 |
| S4 双 tile 队列 + 错误注入 | busy 中排队成完整第二 tile、start#3 拒绝、
流窗内 WCTL 悬挂/丢弃置 ld_pend_err、err_clr 保 done 粘滞、
soft_rst 全清且 ID 不变 | +256 | +128 |

## 门过程中发现并修复的 bug（按发现轮次）

1. **TB 哨兵值假通过**（run1 根因）：run_job_wait 初值 `32'hFFFFFFFF`（bit5=1）
   → 轮询条件永假不进循环 → 全部 tile 等待假瞬时、回读跑到计算中。
   改 st=0 先读一次再轮询。
2. **TB ld_done 采样竞态**（run1）：首读落在 ld_done 脉冲前 ~3 拍 → guard-100
   轮询循环（RTL 无错，纯 TB 侧）。
3. **top start-while-busy 拒绝破坏多块排队**（run2 根因）：原设计 busy 中拒绝
   start → S3 job1 被拒。改为仅 job_pend 占用时拒绝（run15 正典：busy 中允许
   排队，递交由 core job_ready 串行化）。
4. **y_count 的 tile 边界语义**（run4/5 根因，本轮最重要发现）：
   core 的 `job_ready = (feeder == S_IDLE)`——feeder 发完字即空闲，而单块 tile
   的**全部 y 拍都在末字之后**才出 ⇒ 排队/递交拍清 y_count 都会跨 tile 误累计
   （实测 256≠128）。正确边界是 y 流对齐的 **tile_done 脉冲**（array TAILW 出口
   =末 y 拍）。终态设计：活计数器 `y_count_r`（tile_done 拍清零）+
   锁存 `y_last_r`（同拍锁存，YSTAT 回读）——S1-S4 四场景全部 128/32/128/128
   语义自洽；`st_tile_done` 保留递交拍清零（新 tile 起点标志，递交早于上一
   tile 的 y 窗，其 tile_done 会重新置位）。
5. **TB 声明顺序 VRFC 10-3380**：task 共用暂存 `rd/guard2/st2` 声明移到
   task 区之前。

## 冻结的正典（B1 PS 驱动直接对应）

- 装载打包：每 k 三拍（W/Xlo/Xhi），WCTL 位序 {11 last,10 first,9:2 be,1 x_hi,0 is_x}；
- start 语义：job_pend 空闲即可排队；first=1 递交清 tile_done 粘滞；
- 轮询：STATUS{0 busy,1 job_pend,5 tile_done}；YSTAT{15:0 末 tile 计数}；
- 回读：YADDR 置址 → 隔 2 拍 → YDATA（读延迟 1）。

下一步：run22 BD 集成（axi_gemm_test：加引用源、M01 扩展、0x43C00000 映射、
综合/布局布线/比特流）。
