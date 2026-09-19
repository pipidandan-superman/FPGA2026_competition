# EES-331 项目交接

## 2026-09-19（深夜）run25 频率门收官 BOARD_FREQ100_PASS（FCLK0 50→100 MHz）

- **背景**：用户在 Vivado GUI 将 PS7 FCLK0 改 100 MHz、重生成比特流并上板通电，按 overlay skill 七步正典单独验证（用户已决策：频率门与 B3 分开）。期望纪律：同种子 ⇒ 所有 gate 值必须与 run23/24 位相同，偏差即频率耦合缺陷。
- **终态（attempt-3 一跑全绿）**：CK_F 真 **100.000 MHz**（raw `0xF8000170=0x00200500` = IO_PLL 1000÷5÷2，verify-only 零 SLCR 写）；S1/S2/S3 + DB1-DB7 全部值与 run23/24 **逐位相同**（y_count 128/32/128、幻影槽 0x25、STATUS 0x28/0x38、DMASR 0x1002、wop=3462/rb_ok=416/db_ok=9 双零错）→ `BOARD_FREQ100_PASS`，**无频率耦合缺陷**。预检 WNS+0.405 @10ns、DRC 0、DSP 68。板上现挂 **100 MHz 版 GEMM+CSR+DMA 三从机基线**。
- **CK_F 三次尝试 + 自我修正（全留档）**：attempt-1 假 FAIL（我凭记忆的寄存器布局解码错 + 信 pynq 150 报告——时钟本来就是真 100）；probe_clk2.py（raw /dev/mem）钉死板卡常数：晶振 **33.3333 MHz**、IO PLL FBDIV=30→1000 MHz；此间误判 pynq 布局为 bug → attempt-2"修复"写被**硬件拒写 bits[3:0]**（wrote=0x205 readback=0x200）→ 裁定反转：**pynq ZYNQ_CLK_FIELDS=硬件真值**（DIV0[13:8]/DIV1[25:20]/SRCSEL[5:4]，bits[3:0] 保留写忽略）；restore_clk.py 恢复 0x00200500；驱动 v3 全绿。**pynq 3.0.1 唯一真缺陷 = 参考时钟模型（50 vs 33.333 ⇒ 所有 MHz 报告 1.5× 高：报 150=真 100、报 75=真 50）**，门控一律 raw SLCR + PLL FBDIV 推真值。
- **勘误入档**：run23/24 下载后寄存器值曾在我方分析文本中误写 0x00140500（重构算术错误，非观测）；正确值 = **0x00400500 = IO÷5÷4 = 真 50.00 MHz**（干净 RMW 模型 + attempt-1 实测类比证实）——**B1/B2 回溯完整性成立，依据修正**。
- **归位**：33.333 晶振 / 1.5× 报告偏置 / 0xF8000170 布局与 bits[3:0] 写忽略 = 板卡固有事实，入 ees331 板卡画像（不进 skill，四层归位原则）。
- **Git**：本批推送 run25 证据（add -f 申报 bit/hwh/log + sha）+ 7_logs/12 + 根文档三件 + ees331 画像。main 不动。
- **下一步**：B3 DMA+GEMM 大 KC（桥接设计立项 + 4 授权决策点待用户）→ B4 全联；板上动作用户在场。

## 2026-09-19（晚）PE/GEMM 上板线 B1+B2 板级双收官 + overlay skill 通用性修正与同步

- **背景**：晨间 G2 架构收敛与执行计划批准（8×16 基线、Kc=576/1024、双组 TDP PPRAM 禁 FIFO；`1_docs/yolo_gemm_g2g4g7_execution_plan_20260919.md`）后，白班连推两条链（证据 `7_logs/2026-09-19/07–09`，git 11b3b7b/8fca71b）：**IP 硬指标重做链 run11–16**（用户硬指标=数据通路全真 IP、DSP48E1 primitive 合规、例化逐端口对 .veo；六门 PASS，OOC 资源判据精确命中 BRAM36=12+RAMB18=1、DSP=68）+ **WNS A+B 收敛链 run17–20**（tail V2.2 并行逐位判决 `ru=prod[s−1]&(rem|prod[s])` 纯 OR 树无宽进位链，**100MHz WNS+1.392** TNS/THS=0）。本批承接 B1/B2 上板与收尾。
- **B1（GEMM 顶层上板）三门收官**：run21 顶层门（`rtl/GEMM/yolo_gemm_top.v` V1.0=AXI-Lite 寄存器文件+core V1.1+ycap 坐标捕获，544 checks 两轮一致；关键语义=tile 边界取 y 流对齐的 tile_done 脉冲，y_count 双寄存器）；run22/22b BD+比特流（工程 `proj/axi_gemm_test`，M01 u_yolo_gemm @0x43C00000/64K 与 u_yolo_csr 共存；WNS+4.954 @50MHz、DSP=68 与 OOC 对账无黑盒、DRC0；22b 修复 GUI 会话互斥踩掉的 .xpr，reset_run 全链重建终态逐位同值）；run23 板级 **BOARD_B1_PASS**（一跑全绿：S1/S2/S3=TB 正典序列+Python 独立 oracle，**288/288 回读零错**（y_count 128/32/128、幻影槽保旧 0x25、STATUS 0x28/0x38 自洽），2464 次 GP0 写零挂死——M13 写毒在本架构确证不存在）。
- **B2（PS-DMA 回环）run24 板级收官 BOARD_B2_PASS**：分工=用户 GUI 加 axi_dma 7.1（SG 关/64b 流+映射双宽/SG_LENGTH_WIDTH=20/仅对齐）M_AXIS_MM2S→S_AXIS_S2MM 直连回环 + M_AXI 经 axi_mem_intercon→PS7 HP0，我纯文件预检+板测（**零仿真，官方 IP，用户决策**）。预检全绿（时序 WNS+6.087/DRC0/DSP68 不变；地址表 DMA=0x40400000/64K；连线/配置/寄存器模型从 .xci memory_maps 逐字转录，零猜测）；上板一跑全绿：A 路 GEMM 回归与 run23 **逐值相同**（BD 加 M02+HP0 未波及），B 路 4096/137/1/1000/8192 全对拍（1B 部分拍）+连发×3+软复位恢复（DMACR 回 0x10002 与 XCI 复位值逐位一致）+交叉存活性（DMA 复位后 GEMM 新种子 S1 重跑 128/128）；总账 wop=3462 rb_ok=416 rb_bad=0 db_ok=9 db_bad=0。**板级结论：HP 口启用不构成 overlay 障碍（fpga_manager 只写 PL）实证；CMA(allocate)+HP 非一致口免 cache 维护成立；板上新基线=GEMM+CSR+DMA 三从机共存**。
- **overlay skill 修正（用户指令，经二次纠正按通用性归位）**：SKILL.md 增三条**通用方法论**（预检等终态，active≠终态；PS-PL 口使能（GP/HP/ACP/IRQ）是 FSBL 侧配置不碍 overlay；寄存器模型从 IP 生成元数据（XCI memory maps）转录不凭记忆）；ees331.md 仅更新相机条目过时事实（相机已接回，~70s 真帧后 failed 终态+dmesg 显式 unlock+client-exit）；**IP/工程特定内容不进 skill**（用户原则：skill 是通用 overlay 方法论，不针对某 IP/工程）——AXI DMA 驱动纪律归 PG021+驱动文件头 docstring（pl_b2_loopback.py），地址表/连线/run 证据归 4_metrics/7_logs；四层归位原则沉淀记忆 skill-generality-principle。已同步四路径（主树 `.claude/skills/` 与 `6_skill/`、worktree 同名两份，sha256 逐字节核对全同）。
- **Git**：B1 已推 `af407c0`（86ae8a7 RTL/BD feat + bb13563 证据 19 文件含 add -f 大文件 sha 申报 + merge origin/main——MODEL.md 冲突双保留：v2 骨架+我方 Zynq 部署节移出折叠块附 09-19 更新行）；本批推送 = run24 证据（add -f 申报 bit 4,045,696B sha256=6d91f2b5…、hwh 325,120B sha256=0b35ee8f…、board_run24.log）+ 7_logs 10/11 + 根文档三件 + skill 四路径同步。main 不动。
- **下一步**：B3 DMA+GEMM 大 KC（需桥接设计立项：MM2S 流→GEMM 装载口握手协议，用户单独授权）→ B4 全联；板上动作用户在场。板上现挂 run24 三从机基线。

## 2026-09-19（隔夜并行批）PPU 非线性算子线七门全绿 + 迁移入库

- **背景**：用户隔夜授权并行线（防撞暂存区 `2_fpga/parallel_task`，全产物隔离、迁移待各线收口后用户主导），与 PE/GEMM 线并行开发 YOLOv8n 图算子（requant/upsample2/maxpool5/add/xfer；view 零拷贝无 RTL）；09-19 晨用户指令有序迁移主树、日志并入主根、推送个人分支。
- **七门全绿**：P0 手册+ABI 事实核验 **28/28**；P1 oracle 全图回放对软件 golden **5×53=265 位级 0 失配**；P2a–e 五算子核 RTL 门 **EES_MODELSIM_RESULT PASS**——requant(11043)/upsample2(643001)/maxpool5(13962，pad 物化≡有效位掩码双模型交叉)/add(12679，双路 int64 不逐路饱和→int32 合同截断字面实现)/xfer(2842，恒等段字节旁路捷径≡全量 requant 门级钉死——金文件对恒等段也算全 requant)。期望三源独立（oracle 金‖TB 截断除模型装载交叉‖运行期逐拍）+ posedge 三级镜像延迟记分板 + rst 在飞击杀重启复检；反退化配额生成期断言全过（构造平局/饱和轨/死通道/s 全 63 档）。
- **迁移落位**：RTL 每算子一夹 `2_fpga/3_yolo_zynq/rtl/PPU/{requant,upsample2,maxpool5,add,xfer}/` + TB 集中 `rtl/PPU/tb/`；vecgen+ppu_oracle 平铺 `sim/`（oracle 导入已改本目录）；手册 `1_docs/yolo_ppu_design_manual_20260918.md`（ABI 冻结 V1.0，§7 已注记 P2 执行状态）；证据七 run 目录并入 `4_metrics/logs/`；日志并入 `7_logs/2026-09-19/06_ppu_parallel_line_closeout.md`（01–05 属 GEMM 线未动）。迁移验证：SHA 对账 12/12 全同 + vecgen 新位再生成一致 + 10 文件 vlog 烟测过。`parallel_task/` 保留归档不再更新。
- **注意**：`rtl/yolo_requant.v`（M 线 conv 尾 requant）与 `rtl/PPU/requant/yolo_ppu_requant.sv` 同义不同物，勿混用。
- **Git**：commit `fa26666`「非线性算子」上传 `codex/full/pipidandan-superman`（52f2ab5 快进；main 不动）。
- **下一步**：**P3 已撤销独立门（2026-09-19 用户决策）**——schedule.json 邻接反查：41 任务 = 16 view（零拷贝无 RTL）+ 25 引擎任务，其中 16 个输入全直连 conv 输出（64%），仅 9 个有引擎→引擎输入且全为 DDR 缓冲级耦合（add→concat ×4 / add→add ×2 / maxpool5×3→concat / upsample2→concat ×2）；PPU-only 集成 = 自写 walker + 自写 DMA BFM 复放 P2 已钉死的数值，conv↔图算子的真合同在单验中不存在（手册 §7 撤销注记为权威）。walker/描述符译码并入 GEMM 线 G4 共定合同（§10 D2 同步），41 任务回放降级为 P4/G5 bring-up 二分调试工具。PPU 线仿真阶段就此收官，P4/G5 与 GEMM 线汇合（双线协调，不单方启动）。

## 2026-09-19（凌晨自主批）PE/GEMM 手册线仿真门全链收官 + run07 综合评估 + 板测计划

- **背景**：用户睡前指令——完成 GEMM 上板准备、更新日志/handoff/readme/progress、关键成果上传个人分支（overlay skill、AXI 寄存器设计、GEMM）。overlay skill 与 CSR/AXI 寄存器设计经核实**已在分支上**（f542dc3/5007593/ae8da88/c7080d4，无差异），本批上传增量 = PE/GEMM 线。
- **③b/④ 阵列门三档 PASS（run06 V1.1 复跑）**：4×4=846 / 8×16=4250 / 16×16=6881 checks 全 0 err；守恒 started−aborted==done 与 blk_done==12 三档吻合。**TAILW 死锁修复**：掩码 tile 末有效元素的 y_last 单拍脉冲早于 TAILW 进入（FSM 仍在 S_TAIL 跳无效槽），电平等待必错过 → 改 y 拍计数判定 `ycnt >= n_valid_cnt`（对拍序不敏感）。修复前 FAIL 控制台 + dbg/ 最小复现 FSM 追踪留 run06。教训：**跨模块单拍脉冲不得作 FSM 电平等待条件**。
- **run07 OOC 综合评估（16×16）**：A 真配置(2304)@100MHz / B 核视图(K64)@100MHz / C 真配置@150MHz。**终态：A 中止于 RTL Optimization Phase 2（宿主内存临界，Vivado 峰值 15.2GB，后台任务被系统回收+孤儿进程已终止；不自行重跑）**——但 G2 证据已封闭：③ 档功能缓冲异步读 → `W_buf_reg/X_buf_reg with 294912 registers` 各一，590k FF > 106.4k 器件 FF，**物理不可上板，G2（W/X 真 bank）为唯一路径**；B/C 未跑，B 留晨间（用户在场数分钟）。详见 [run07 README](4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run07_syntheval/README.md)。
- **板测计划成文**：[yolo_gemm_board_test_plan_20260919.md](1_docs/yolo_gemm_board_test_plan_20260919.md)——晨验清单=基线回归（186154c5，可选）+ run06/run07 证据评审 + G2 开工决策；G2/G4 缺口如实标注，**本批无任何板上操作、无新生成比特流**。
- **RTL 落位**：`2_fpga/3_yolo_zynq/rtl/GEMM/`（yolo_pe_core / yolo_acc_dual / yolo_mac_cell / yolo_gemm_tail / yolo_gemm_array V1.1 + tb×5，tb_dbg_arr 已删）。
- **Git**：PE/GEMM 线（RTL+TB、两手册+图集+量化审查、run01–07 证据小文件、7_logs/2026-09-19、板测计划、progress/README/HANDOFF）命名文件上传 `codex/full/pipidandan-superman`（commit 见分支历史；main 不动）。
- **下一步**：G2 W/X 真 bank（TDP：A 口装载/B 口计算读 + 同步读地址提前一拍 + ping-pong；cell/tail/FSM 契约不动，run06 阶段矩阵复跑）→ G4 DMA/CSR 接入 → G7 上板。

## 2026-09-18（续）M13 run03 第三冻 → BD 假设否定 → run04 v1.4 Overlay 路线备好待跑

- **入口**：[run03 证据](4_metrics/logs/2026-09-18_yolo7020_m13_board_run03/README.md)（时间线/根因排序/坑清单）· [progress.md](progress.md) H13 已更新。
- **run03**（用户指定：run9c 修正位流 + **原始 pl_m11.py /dev/mem 驱动**重试，检验"BD 错误设计引发冻结"假设）：fpgamgr bin 格式逆向（`swap32(.bit[164:])`，sync `66 55 99 aa` dword 对齐；write_cfgmem SMAPx32 与裸 .bit 均被内核拒）；**假加载事故**=`sudo sh -c '~/…'` 的 `~` 展开到 /root → cp 断链实际未加载，而 `state=operating` 是开机 camera overlay 残留、CSR Bus error 才是真信号（绝对路径重载后身份读 CSR_ID/VER 绿）；fclk0 实测 50MHz（boot 设定，时序安全，嫌疑③排除）；10:35:24 全净窗口 0x08000000（0/3584）启动 → **~1min 同签名硬冻**（ping 100% 丢、COM6 30s 纯静默 0 字节、ssh 3× 失败）→ **BD 错误假设被证据否定**。新背景证据（v1.4 camera.py:111-115 注释）：**本板 PL 交叉开关只暴露低 512MB**——run01 默认 0x30000000 出窗可独立解释，但 run02/03 窗口内亦冻。根因排序：①/dev/mem 13MB RAM 直写（头号）②HP 互连。
- **用户指令：后续所有 overlay 加载一律走 v1.4 PL Reloader 机制**（用户全部成功加载所依赖的路径）。已从 `8_tools/EES331_PL_Reloader_v1.4/payload/action_v1_20260913/camera.py:55-118` 提取完整正典并移植为 **run04 三件套（待上电授权）**：
  - `2_fpga/3_yolo_zynq/pynq/pl_m11_pynq.py`：`Overlay(bit, download=False).download()`（zocl/XRT，**需 XILINX_XRT=/usr**）→ `fpga0/state==operating` → CSR_ID/VER 身份门禁 → **CMA `allocate` 写通道**（cached 写 + 门铃前 `flush()`；窗口核 0x10000000..0x20000000）→ 读回走 `/dev/mem O_RDONLY|O_SYNC` 无缓存别名（device 读直穿 DRAM）→ CSR 用 `MMIO`。程序/协议/判据与 pl_m11.py 逐位一致（同 stim、同黄金 sha、同 PL_M11_PASS 行）。
  - `board_run04.sh`（root、全绝对路径、`systemctl stop ees331-camera` 后 nohup 双进程）+ `watch_run04.sh`（PC 15s 轮询看门狗）。
  - bit+hwh 配对 `pynq/r9c_overlay/yolo_sys_wrapper.{bit,hwh}`（bit d1f08549 / hwh 1e3bc3dd，hwh 取自 run9c `.gen/…/hw_handoff/yolo_sys.hwh` 改名——PYNQ 要求同名配对）。
- 板冻待用户断电重启；run03 板端 `board_run03.log`/`status_poll03.log` 原位可取（/home 不受 drop_caches 影响）。JTAG/Vitis 裸机路线保持备选（工作区 `proj/board_sys/yolo_a2_board/vitis` 已建，P0/P1/P2 规划就绪）。

## 2026-09-17/18 yolo7020 批次交接：A2/B0/M11 run05 收口 → 板级位流 PASS → M13 双冻结 → JTAG 裸机 + run9 BD 修正

- **入口**：[progress.md](progress.md)（总览，H12/H13 已更新）· [会话日志](7_logs/2026-09-17/11_m11_m12_m13_board_batch.md)（§1–§9 全批过程）· [run02 冻结取证](4_metrics/logs/2026-09-18_yolo7020_m13_board_run02/README.md) · [run09 BD 修正](4_metrics/logs/2026-09-18_yolo7020_board_build_run09/README.md)。
- **A2 loader V2 收口**：M10 门复绿 `layers=6 compared=438447` 同基线数；四根因全修（xrowgen done 残留高电平/loader 无反压/acc 使能链 4 级 vs 乘积 wv+3/**层边界 LUT 预载双洞竞态**——S_TWAIT 首拍 NBA 采样 + sh_occ 末拍早清，修复=tail_idle_w 全排空契约）。冻结点 gemm_array **V2.0c**/xrowgen V1.3/dma V1.4/wbuf V3.0/xbuf V3.0。
- **M11 run05 全网双绿承证**：`TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900 head_bytes=149100 ldone=63 adone=1 bfmerr=0/0` + headcheck sha==9ce70525…==run04 冻结；逐层步进表 `conv_step_times_ms.txt`（全帧 sim 855.129ms）=板端对照基准。
- **M12 OOC**：v28@150 FAIL（−8.750，损害全落 X 通路）→ 守"板结果优先"改 **v28b60@60MHz first-light PASS（+0.806）**；板后优化候选（A2b X2/oc-pair、xrowgen 流水化、提频）交用户决策。**板级 BD 构建 PASS（run8 wns+0.954）**：八跑剥洋葱坑（set_property -dict 对 MIO_TREE 二次求值/BANK 电压先设/HP 自动化方向同构 GP0/已分配段 OFFSET 只读/module_ref 接口默认 100M 无时钟关联/两段式 launch_runs）全记录在 board_build_run01 README。
- **M13 板测两跑双冻结（Linux+/dev/mem 路线证死）**：run01(0x30000000)/run02(0x08000000，kpagecount 证据驱动全空窗口 0/3584) 均 2–10 分钟内硬失联（ping/串口死、无 panic）；下载+CSR 身份读两绿。**DDR 段占用假设否定**；修正根因排序：①/dev/mem RAM 别名 mmap 13MB 直写机制（run01 冻点=[stim] 后 [ddr] 前=纯 CPU 写、引擎未启动；A9 Device-memory 非对齐 store UNPREDICTED 可静默挂总线）②HP 互连挂死 ③FCLK0≠60MHz 未证。板环境铁律：fpga_manager 只认 dword 字节交换 .bin；/dev/mem 只有 mmap 路径可用（read/pread 全 EFAULT）。
- **用户决策：JTAG 启动 + Vitis 裸机**。工作区 `proj/board_sys/yolo_a2_board/vitis`（平台 yolo_zynq + app_component empty_application，CMake 式，arm-none-eabi）；三相规划 P0 身份读冒烟/P1 conv0/P2 全网（MMU/caches 关=零一致性顾虑；prog+lut 编 ELF、ddr.bin 走 XSCT dow -data @0x08000000；JTAG 优势=挂死现场 xsct stop 读 PC）。**待用户指令推进**。
- **run9 BD 修正批（09-18，用户 GUI 发现+手工修、授权批处理收口）**：①DDR/FIXED_IO make external（100 条 IOSTANDARD 警告根因）②PS 勾选 IRQ_F2P 直连 engine/irq_o（v1 驱动仍轮询，中断线留作后用）③60MHz=有意 first-light 决策非 bug。批处理侧：XDC 删 create_clock 消 [Constraints 18-1056]；`write_bd_tcl` 导出用户权威 BD 收编为正典 **`proj/board_sys/yolo_sys_bd.tcl`**（build_board.tcl v2 source 它）；**IRQ_F2P 引脚物化机制=ps7 全 533+ 配置一次性 `set_property -dict` 灌入**（事后单独 set PCW_IRQ_F2P_INTR 得 41-721 disabled ignored、引脚永不物化）；module_ref 接口 FREQ_HZ/CLK_DOMAIN 在 GUI 保存后会丢（s_axi 曾被重置回 100M→41-237），重导出前先三连 re-apply。**run9c 收口：BOARD_BITSTREAM_PASS wns+0.623，CRITICAL WARNING 总数=0**（IOSTANDARD 100→0、18-1056 1→0；**41-967 亦归零——"module_ref 不可根除"旧结论作废，其真正触发条件=FREQ_HZ 缺失的半配置接口**，FREQ_HZ×3+CLK_DOMAIN×3 配齐后 Vivado 自行推断时钟关联）。产物：yolo_a2.xsa adc0a7d1d39b1543 / yolo_sys_wrapper.bit d1f08549ef8a2f44。
- **Git**：本批文档（progress/README/HANDOFF/7_logs）+ run09 证据 + yolo_sys_bd.tcl/build_board.tcl v2 上传 `codex/full/pipidandan-superman`。

## 2026-09-16 yolo7020 批次交接：G3 M12 A1 承接批五门全绿

- **入口**：[progress.md](progress.md)（总览）· [G3 基线](1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md)（状态字 `M12A1_ALL_GREEN`）· [当日执行记录](7_logs/2026-09-16/02_execution_plan.md)。
- **A1 五门全绿**（授权"先跑a"，A=纯 RTL+仿真，无 Vivado/板卡）：①M8 run03 ctrl V1.2（rq_rdy 等待态回归，接高≡V1.1）；②M9b run01–03 dma_wr（Y 线性块 AXI4 写主：WLAST/链化两缺陷修复 → V1.2 非对齐起始）；③M10 run03 阵列 V1.2/V1.2a（**Y 观测口→真 AXI4 写主**：行段化器 + dsc_ybase + 排空门控；run02 失败链揪行首准入在途竞态）；④M11 run03 全网回归（七项与 run02 同数 + head sha 复命中）；⑤**CSR/engine run01 首跑过**（`rtl/yolo_csr.v` AXI-Lite 从 @0x43C1_0000 + `rtl/yolo_engine_top.v` u_csr+u_array 组装，PROD 16×16 默认参/SIM 8×8 同 RTL；寄存器图入 `hw_contract/address_map.md` 三处同步）。
- §5 全链重跑义务已履行（RTL 数值路径改动：array/ctrl/dma_wr）。三条新教训入档：验证侧镜像写合并粒度必须与被测写口原子性一致（单 NBA）；寄存器拼接/解包位域必须读回抽检；黄金捷径表达式扩展合同后必须重推导（M9b run03a vecgen sum bug）。
- **下一步**：A2 loader V2 三件套（**已授权"按照1做"**：W 跨 n_tile 持久 oc 外/n 内、X 行段流式宽写 + xrowgen + 第二读 DMA、requant 重叠；预算 ~3.95M 拍 < 5M@150MHz）→ B 段 OOC（非工程批处理、150MHz 纯约束）**待用户确认** → M13 板卡（逐次授权）。
- **Git**：本批 5 个 RTL（含 3 新）+ 6 TB/脚本 + 6 证据目录 + 文档/7_logs 上传 `codex/full/pipidandan-superman`；transcript/head_dump.bin 声明清单入库，激励大数据留本地。

## 2026-09-15 yolo7020 批次交接：G2/PS 板上闭环 + G3 M0–M11 全绿

- **入口**：[progress.md](progress.md)（软件/硬件总览）· [G3 基线](1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md)（状态字为权威）· [当日验证摘要](7_logs/2026-09-15/03_validation_summary.md) · [下次启动指南](7_logs/2026-09-15/04_next_start_guide.md)。
- **软件**：G2 真 RNE 合同 run04 为部署源（valid −0.0092；bias_eff/平局两缺陷已修）；rom_data 部署包哈希核对；PS 运行时离线 128/128 位级；真实 ARM PS 全量自检 head **128/128 位级一致**（56 帧 box 差异全为 ARM/x86 libm ulp 类、conf≤0.01 良性）；45.34s/帧纯 numpy 未优化。板端只新增 `/home/xilinx/yolo_selfcheck/`，SSH 密码走环境变量（凭据文件不入库）。
- **硬件 G3**：架构基线冻结后单日 12 门全绿——M0 通用核（假绿教训：合成激励必须反退化 + 每门真实数据回归）、M1 DSP 双打包（偏置布局，2^24 穷举）、M2–M9 单元门、M10 阵列集成（438,447 格零差异 + 4 个集成缺陷修复与 §5 全链重跑）、**M11 全网**（1 帧 63 conv 3,553,900 格逐位 + head sha==run04 frame0 + 6 张量拆分逐字节；k1×1 首覆盖；门定义修正与理由见基线 §8）。RTL 零改动过 M11。
- **工具链铁律**（10.1c 实测，沿用）：vsim 必须 `-c -novopt`；三目/拼接进有符号运算必须 `$signed()`；黄金服务用连续 assign；哨兵 0xA5 歧义用写双射计数兜底；**大数值 delay 表达式先升 64 位 time**（M11 WDT 32 位溢出假失败实证）。
- **下一步**：M12 OOC（PROD-16×16，150MHz 必过；Y 真 AXI 写主 / X DDR 流式 / PS 微操作硬件化三项决策随批入场）→ M13 板卡整合。**两者均需用户单独授权。**
- **Git**：本批 rtl/sim/证据/文档/progress.md 上传 `codex/full/pipidandan-superman`（main 保护不变，PR 待队友审核）；原始 transcript 与 head_dump.bin 以声明清单方式入库，仿真激励大数据（ddr.hex 等）与 npz 留本地不入库。

## 2026-09-14 1_docs 目录分层整理

`1_docs`按六分类重组：`doc/`（正式交付文档）、`赛题方向/`（赛题原文/评分页/设计方案/平台选型手册）、`datasheets/`（器件手册）、`figures/`、`legacy/`（早期占位文档）、`第三方资料/`（约15G，仅本地不入Git）；根目录仅留PYNQ教程、yolo7020部署计划r3与索引README。重复旧副本已删（`doc/ADV7511KSTZ`、`doc/amd_dual_model`初版、doc与根目录的roadmap/amd_topic2副本），分支14个幽灵文件同步清理。权威迁移对照表：[1_docs/README.md](1_docs/README.md)；历史日志旧路径不回写，按对照表换算。提交93eae1f于`codex/full/pipidandan-superman`。

## 2026-09-13 当前交接：PL重加载v1.4

- 唯一支持的重加载包为`8_tools/EES331_PL_Reloader_v1.4/`；v1.0～v1.3已淘汰，不要从旧聊天附件或旧目录复现。
- v1.4已完成两轮A→C上板成功，第二轮为用户确认断电重启后的成功。五种启用动作Stop/Up/Down/Thumbs Up/Thumbs Down对应LED4/7/1/6/5均由用户确认。
- 复现必须从原`ees331-camera`动态HDMI/UDP基线开始。v1.4执行10秒传感器预等待与30秒首帧门控；只有`ACTION_OVERLAY_READY`才算软件加载通过，系统服务`active`、`FOUND`或文件同步完成都不算。
- 动作识别必须从v1.4内部按钮打开，或显式`--action-control`。直接双击EXE默认显示模式，日志`protocol=null`，会识别但不会输出LED。
- 操作入口：[v1.4上板复现指南](1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md)；证据：[run01](4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run01/REPORT.md)、[断电后run02](4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run02/REPORT.md)、[模型重开诊断](4_metrics/logs/2026-09-13_action_viewer_reopen_diagnosis_run01/REPORT.md)。
- 验收边界：当前只有2/2样本，第二轮断电由用户确认而非boot ID自动证明；不能称为长期稳定、机械臂安全闭环或模型泛化精度PASS。原SD/BOOT和冻结`2_fpga`不变。

## 2026-09-13 AXI复位修复与后续授权

独立AXI-Lite已修复BD辅助复位低有效却接0的错误；官方IP仿真通过，原4份RTL未改，重新构建100MHz时序/DRC通过。修复版1000轮命令、3次重载实机通过，原视频服务恢复后UDP60帧零CRC/丢帧/坏头；HDMI最终人工确认仍待用户答复。新发布包在独立proj/release，旧版保留且禁止加载。

[实机和故障证据](4_metrics/logs/2026-09-13_axilt_reg_board_run02/REPORT.md)；[通用skill](6_skill/zynq-pynq-overlay-workflow/SKILL.md)，已同步安装并校验。

用户新增授权：独立验收后创建skill、集成主FPGA工程、综合/实现/实机视频+蓝牙+控制共存、更新并推送codex/full/pipidandan-superman，全部成功保存且无其他未保存工作后正常可取消延时关机，不强制退出。主工程已确认是2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr；尚未开始修改。BRAM未实现，不混入。此授权不是Git main合并许可。当前未推送、未关机。

## 2026-09-12 AXI_LITE_test 实体工程交付

用户最新要求已完成：实体工程在2_fpga/2_axi_lite_test/proj/AXI_LITE_test.xpr，
BD精确命名AXI_LITE_test。4份.v源码与通过仿真版本一致，
综合/布局布线/bit生成通过，100MHz，WNS/WHS=2.925/0.013ns，DRC错误和黑盒0。
本地proj/release含AXI_LITE_test.bit/.hwh/.xsa及成套哈希；
51项交付审计、28个链接通过。该工程保存位置为用户本轮明确指定。
入口：[BD说明](2_fpga/2_axi_lite_test/doc/bd_design.md)、
[本轮报告](4_metrics/logs/2026-09-12_axilt_local_project_run01/REPORT.md)。
未进行板卡下载/主工程合并；寄存器板测及后续BRAM阶段仍待接续。

## 2026-09-12 PS–PL AXI-Lite 独立工程

用户已授权在2_fpga/2_axi_lite_test独立开发。当前4份自研RTL、寄存器ABI、
PYNQ驱动/ARM MMIO辅助层源码、板测脚本和Vivado重建入口已交付。
26282项RTL检查、1001命令、3随机种子及延迟后端通过；100MHz构建通过，
WNS/WHS=2.925/0.013ns、LUT719/FF1116、DRC错误和黑盒0，BIT/HWH/XSA成套归档。
8项软件离线测试通过；板卡192.168.240.10:22超时，实机尚未验收、ARM helper未板端编译。
按用户计划，寄存器实机验收与视频恢复通过后才进入BRAM阶段。未合并/推送。
入口：[独立工程](2_fpga/2_axi_lite_test/README.md)、
[完整报告](4_metrics/logs/2026-09-12_axilt_handoff_run01/REPORT.md)。

## 2026-09-12 BLE Console v1.1 与手动复现

推荐未配对GATT接入已集成上位机：三次无缓存读取/保持门控、自动通知、断连停止发送。
31项离线/Tk测试、新版后端60.5秒三轮双向及真实EXE按钮双向字节核对通过；
用户另行确认双向通信成功。TX只是发送记录，HEX旁的文本替代字符不是数据损坏，
端到端结果以另一端实际收到的HEX为准。

[操作与验证状态](1_docs/doc/ees331_ble_validation_status_2026-09-12.md) ·
[上位机源码及说明](3_host/ble_console/README.md) ·
[方案v1.2](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md) ·
[本次发布范围](4_metrics/logs/2026-09-12_ble_v11_publish_run01/REPORT.md)。
本地新EXE在8_tools/EES331_BLE_Console_v1.1，旧包保留；本次上传源码、说明、精选证据，
不上传运行依赖树或凭据。冻结FPGA不改；长期/重连/机械臂/AXI-BRAM仍待分阶段执行。

## 2026-09-12 最新蓝牙里程碑

PC与板载MLT-BT05已通过短时双向通信：未配对GATT保持61.703秒，11轮、每方向166字节全部一致，结束主动断开。COM4有线AT正常；不等于长期压力、Windows PIN配对稳定、机械臂互通或正式AXI/BRAM控制通过。复现时直接通过BLE上位机连接并订阅FFE1，COM4=9600/8N1用于另一端收发核对，不需ILA。

入口：[验证状态与复现](1_docs/doc/ees331_ble_validation_status_2026-09-12.md) · [完整开发方案v1.1](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。下方历史阶段状态以本段及最新验证报告为准；当前电平桥不能替代正式字节级UART/FIFO。


## 2026-09-12 当前最高优先级：板载蓝牙验证

执行入口：[完整开发方案](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。用户确认自定义AXI-Lite只做控制/状态、BRAM使用独立控制器、蓝牙使用PL板载模块。首先G0核实基线和供电极性，建立独立PL UART诊断副本，B0查询MLT-BT05，B1以Windows主机作BLE Central验证双向收发。PC通路PASS不代表MLT主机模式或BT24直连PASS。之后按C0/C1实现CSR、4KiB TDP BRAM、LED，再接机械臂。方案中给出地址偏移、所有权/CRC/seq/结果确认、心跳和回退；物理基地址待审计。此轮仅编写和发布方案，2_fpga冻结基线保持只读。

## 2026-09-10 关键证据归档与个人分支交付

- 已完成：内容提交 `ae1384aea6f3390fb17ef78562eabf83f4677039` 已推送且远端 HEAD 一致；[草稿 PR #3](https://github.com/pipidandan-superman/FPGA2026_competition/pull/3) 目标 main，尚未合并。归档文件哈希、18 项启动资产、300 项暂存对象、两版 EXE 自检与项目路径审计通过。后续回执提交只补充文档和 Git 结果。
- 归档入口：[REPORT.md](4_metrics/logs/2026-09-10_session_archive_upload_run01/REPORT.md)，逐文件来源、大小和 SHA-256 见同目录 `selected_manifest.json`；Git 审计、校验与推送回执也保存在该目录。
- 目标分支 `codex/full/pipidandan-superman`，以远程 `main@c60291a` 为基线在独立 worktree 整理；保留已有 UDP/颜色修复记录。本机原工作区的其他未提交改动不纳入本次上传。
- 已选择 SD 故障定位/修复/原始 UART、整卡读回、SD Builder v0.1/v0.2 源码与 EXE、AIPC 模板/报告/解析与排版证据。大 IMG、重复 ZIP、工具链缓存保留本地。参考 XSA 仅从冻结目录只读复制到归档目录。
- 边界：旧基线 SD/Linux Shell 已通过；v0.2 新生成包未板测；9 月 8 日裸机 UDP/PC 色彩修复已通过，Linux 网络/Jupyter/PL 应用另行验收。AIPC 人员与机型等字段待补齐。
- 下次先读 `7_logs/2026-09-10/04_next_start_guide.md` 顶部；从个人分支取回交付文件，按归档索引取得基础 IMG。合入 main 仍需 PR 和另一成员审核，不以分支推送代替硬件验收。

## 2026-09-10 AMD AIPC 借用报告已编写

- 按用户指定模板完成 `1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx`，2页，含当前EES-331架构、AI PC借用用途、计划和两张新框图。模板原件与非编辑DOCX包部件保留。
- 通过MinerU的DOCX→PDF回退解析（短文本review已人工核对）、参考渲染、两页最终视觉检查及包/节/样式审计。原始证据 `4_metrics/logs/2026-09-10_aipc_loan_report_run01/REPORT.md`。
- 人员/学校/联系信息待补充，团队编号与机型待确认，37032G暂拟申请。未发送或提交。当前SD Builder v0.2与冻结硬件状态均不变。

## 2026-09-10 SD Builder v0.2 已交付（当前最新）

- 用户要求保留旧版并生成新版；v0.1源/资产/EXE/ZIP的19项哈希无变化，原 `8_tools/sd_start_tool/` 保留。新版入口 `8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe`，同目录有完整ZIP。
- 新版源码 `3_host/pynq/sd_boot_builder_v02/`。删除原版PYNQ-Z2输入入口，固定已适配EES-331基础IMG；默认XSA+板级模板生成PS设备树，完整DTB覆盖置于高级设置。辅助HWH自动识别，USB角色可选，三种PL模式说明、页面滚动与缺项提示完成。
- 22项测试、真实FSBL/BSP重建+整卡读回、EXE自检/手动/FSBL模式构建、位流载荷验证、发布ZIP/旧版保留核对PASS。最终测试IMG在 `2026-09-10_sd_builder_v02_175423_0bb6c6/output/`。
- 新输出尚未上板；本轮未写SD或改冻结工程。本机旧路径的实际显示XSA未启用SD0而被正确拒绝；高级DTB不能绕过启动引脚约束，未知外部设备/PL内核驱动仍需适配。
- 报告 `4_metrics/logs/2026-09-10_sd_builder_v02_run01/REPORT.md`；下一会话从 `7_logs/2026-09-10/04_next_start_guide.md` v9继续。下方标注“最新”的段落均为当时历史状态。

## 2026-09-10 EES-331 SD Builder GUI 0.1 已交付（历史，已由 v0.2 替代）

- 用户要求应用输入硬件文件导出SD启动包，并明确XSA必须含bitstream。已实现强制XSA的Windows GUI/EXE，支持PS差异检查、必要时新FSBL/BSP、手动/Linux后自动加载/FSBL三种模式、BOOT/FIT/ZIP和完整IMG校验输出。
- 程序：`4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/distribution/EES331SDBootBuilder.exe`；源码与说明：`3_host/pynq/sd_boot_builder/`；验证报告：toolkit_run01/REPORT.md。
- 10项输入/GUI测试通过，真实完整IMG/FSBL重建/FSBL位流载荷校验通过，EXE自检与真实XSA构建通过。新硬件包未板测，本轮未写SD或改冻结工程。
- 第一版限当前EES-331+Vivado/Vitis2025.2+PYNQ3.0.1；影响PS外设的未知变化需要匹配DTB，不自动猜测外部器件和驱动。默认手动加载PL，界面可切换自动加载。
- 下一入口：7_logs/2026-09-10/04_next_start_guide.md v8。使用实际新XSA完成冷启动/PL/DMA/应用验收，再扩展板级profile。

## 2026-09-10 SD/Linux Shell 启动已证实，完整 IMG 可交付（启动基线）

- 用户 `2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt` 证实 FSBL→U-Boot→EES-331 Linux→`xilinx@pynq:~$`，阶段结果 SD_BOOT_TO_LINUX_SHELL_PASS。
- EES-331 最小系统基线已归档为 `9_pynq/sd/01_base_ees331/ees331_pynq_v3.0.1_ps_sd_20260910.img`，7,858,807,808 B，SHA256 `203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`。
- FULL_IMG_PACKAGE_READBACK_PASS：六个启动文件与已部署版本一致，启动分区外所有字节保持原版。新的完整 IMG 尚未复烧上板；不含首次启动后的运行状态。
- 网络/Jupyter/应用 Overlay 待验收，UART 中 U-Boot PHY/default-env、Linux随机MAC和部分 FSBL调试格式问题未因打包而修复。当前已通过的是 SD/Linux Shell 启动。
- PL开发通常更新同版本 `.bit`+同名`.hwh`和应用，需要Linux内核驱动时再处理`.dtbo`/模块；PS启动配置变化需新XSA/FSBL/BOOT及实际使用DTB。当前BOOT不含PL位流；冻结工程不改。
- 完整报告与更新矩阵：`4_metrics/logs/2026-09-10_ees331_img_package_run01/REPORT.md`；下一入口为 `7_logs/2026-09-10/04_next_start_guide.md` v7。下方 NOT_TESTED 为当时历史状态。

## 2026-09-10 SD 修正版已部署（历史里程碑，16:09:58 +08:00）

- 用户“根据查验的问题完整修正”已执行：隔离重编带打印 FSBL，正确 bootloader 头+U-Boot+控制 DTB，FIT 内同步适配 UART1/33.333333MHz/1GiB/PHY0，取消 Z2 base.bit 自动加载。最小 XSA 未启用的 USB/I2C/QSPI 在 DT 中禁用。
- G 盘已替换 BOOT.BIN/image.ub/boot.py、新增 system.dtb，boot.scr/REVISION 保留；全部文件读回哈希一致、卷刷新成功、写后 FAT 只读检查无问题。PC 备份完整，冻结工程/根分区未写。
- `SD_BOOT_CANDIDATE_STATIC_PASS`（240 项）+ `SD_DEPLOY_READBACK_PASS`；`hardware_status=NOT_TESTED`。新 BOOT SHA256 `3ea3eae30dba8646ddb597abf098594a99ed6c0250576bed12a9eca91c3902a0`。
- U-Boot 复用官方镜像中的原始程序载荷，通过实际二进制确认其读取 0x00100000 外部 DTB，未冒称源码重编；内核保留，BOOT/FIT 中的设备树字节一致。
- 当前第一动作：安全移除卡并插回板卡，COM6 115200-8-N-1 无流控先开日志，再冷启动记录 FSBL→U-Boot→Linux。用户已经确认 SD 拨码与供电。网络/Jupyter/自定义 Overlay 待实际板测，不提前标记完整 PYNQ PASS。
- 证据和回退说明：`4_metrics/logs/2026-09-10_sd_boot_fix_run01/REPORT.md`、`candidate_validation.json`、`deploy_result.json`；当前交接 `7_logs/2026-09-10/04_next_start_guide.md` v6。

以下为此前修复前审计和历史板测记录，旧“未写卡/等待修复”不代表当前状态。

## 2026-09-10 G 盘全面检查完成（历史）

- 全卡 15,634,268,160 B 只读读取完成，0 错误；MBR/7.72GB Linux 分区与原版镜像相同，除 BOOT.BIN 外的根目录启动文件也相同；ZIP→IMG 完整性验证通过。没有发现烧录载荷损坏证据。
- 当前 BOOT.BIN 无有效 FSBL 加载头、无 DEBUG 打印且缺 U-Boot；image.ub 内 DTB 另有 UART0/50MHz/512MiB 的 Z2 假设，与 EES-331 UART1/33.333333MHz/1GiB 不符。只改 BIF 不足以启动完整 PYNQ。
- boot.scr 优先使用 FIT 内 DTB；原版 BOOT 内 DTB 与 FIT 内 DTB 相同。只放根目录 system.dtb 不能保证修复生效。
- SD0/CD MIO0 与手册一致；Linux/PYNQ/Jupyter 文件存在，boot.py 会自动加载原版 Z2 base.bit，需要后续适配。整卡无读取错误不是写入型介质验收，未运行 e2fsck 或板测。
- 未写卡、重编或修改冻结工程。下一入口：`4_metrics/logs/2026-09-10_sd_card_full_audit_run01/REPORT.md`、`7_logs/2026-09-10/04_next_start_guide.md` v5。

## 2026-09-10 SD 启动静默：镜像缺陷已定位，板级恢复待验

- 同日 15:30 直接检查 G 盘确认：实际 BOOT.BIN（91,856 B）与 run03 BOOT_MIN.BIN 逐字节一致，FSBL 源偏移/长度仍为零。未写卡。现场证据 `4_metrics/logs/2026-09-10_sd_card_g_audit_run01/REPORT.md`。

- 用户当前确认 SW8 为 SD 启动且上电成功。只读审计发现 run03 `fsbl_only.bif` 缺 `[bootloader]`，实际 BOOT_MIN.BIN 的 FSBL 源偏移、长度、总长度均为 0。
- 同一 FSBL 没有启用 DEBUG，ELF 中不存在预期横幅和错误字符串；旧“最小镜像上电应有横幅”的验收无效。
- 先依次修正 BIF、验证启动头，再启用 DEBUG 重编并确认实际字符串；之后做 SD 冷启动 UART/阶段验证。只有 FSBL 的镜像不能启动完整 PYNQ。
- 未执行源代码修改、重编、写卡、JTAG 或板级恢复。旧 BOOT_MODE=0 是修正拨码前的证据；不能沿用“定案 DDR 训练失败”或据 JTAG 全 1 断言没上电。
- 入口：`4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md`；日志：`7_logs/2026-09-10/03_validation_summary.md` 与 `04_next_start_guide.md`。

## 2026-09-08 FREEZE udp-color-fix-pass-20260908 (UDP camera-frame R/B swap root-caused, fixed PC-side)

- Symptom: UDP camera frames showed red/blue-swapped colors (yellow object -> pale blue, blue-violet -> orange, lavender -> pink); HDMI was always correct. Root cause: VDMA S2MM packs the 24-bit {R,G,B} AXIS word little-endian, so DDR/UDP type=0x01 payload bytes are [B,G,R] per pixel, while the host decoded them as [R,G,B]. OV5640 registers (`0x4300=0x61`, RGB565 sequence 1) are NOT at fault — do NOT change them to "fix" colors (that would swap HDMI).
- **Current receiver: `3_host/udp_video/dist/EES331_UDP_Viewer.exe` — 31,187,867 B, SHA-256 `a4b75ed3423aeb2ca292623b00310ac166be6c09171527ad8397435ca193dd1d` (built from `udp_video_gui.py` V1.2, type-aware decode: type=0x01 -> BGR, type=0x02 -> RGB). Discard older copies (V1.0 31,187,636 B / V1.1 31,188,255 B) — they render camera frames with red/blue swapped.** `udp_video_rx.py` V1.1 carries the same type-aware fix; camera payload is already cv2-native BGR, so model-side frame grabbing needs no channel flip.
- Board side unchanged: the C1.2 frozen pairing below stays valid (BIT `7CB11F7D...` + ELF `3E295D51...` + XSA `30644B31...`); no rebuild or re-programming is needed to get correct colors on the PC.
- Verified: localhost end-to-end injection `ALL_COLOR_SWAP_FIX_TESTS_PASS`; user visual pass on the live board stream (recorded video: natural skin tones, 6.25 fps, ~1% loss/CRC consistent with C1.2). Byte-order erratum in the design contract: `1_docs/doc/OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md` §10.
- Evidence: `4_metrics/logs/2026-09-08_udp_color_swap_fix_run01/` (RUN_REPORT, verification scripts + raw console log, user screenshots + final board-stream video, per-file SHA-256). Tag: `udp-color-fix-pass-20260908`.

## 2026-09-08 FREEZE udp-camera-c12-pass-20260908 (C1.2 quality PASS, 4.77 fps zero-defect)

- Frozen board-proven pairing for the camera-to-PC UDP video stream. Reproduce: program BIT -> load paired ELF -> UDP stream resumes (monitor-independent; if you also want to SEE HDMI, switch the monitor to the board input first and press reset once).
- BIT `display_test_wrapper.bit` SHA-256 `7CB11F7DF165476EB86E3D8C43CC251FB1C454ECDB64B905F0931AD971EC192E7` (4,045,696 B, 12:09).
- ELF `app_component.elf` SHA-256 `6EB0097C17ABEAF2DFDD227F89B3141BCC45B8C7D9C83099B3A97B2FE4F29ED1` (861,424 B, 14:51 build).
- XSA `display_test_wrapper.xsa` SHA-256 `30644B3158D86D0D27C34ED60626179B17046CDA7B3AF51F35431B18652D22D0` (578,739 B, 12:09).
- Binaries live under `2_fpga/0_diaplay_test/vitis/hw_20260908_eth/` (refresh the ELF copy from this freeze).
- Measured quality: 1533+ complete frames @ 4.77 fps, 丢帧=0, CRC 错=0, 重复/坏头=0/0 (GUI screenshots archived). Do NOT mix this pairing with the 09-07 HDMI-only frozen pair.
- FINAL pairing update (post C2 first attempt, PROVEN): 66 ms interval / 600 µs burst pacing -> **6.3 fps measured, 丢帧=8, CRC 错=8 over 854+ frames (~0.9%)**, HDMI camera display normal. ELF refreshed: `app_component.elf` SHA-256 `3E295D51186135E4D9DFBBA4B6C3637F3E7AECE9135F2C124C29CE9FF1D963A9` (861,424 B). C2.1 zero-copy experiment (mass udp_sendto failures at 66 ms) reverted and archived; 15 FPS needs C2.2 diagnostics (err code + lwip220 tuning).
- Quality fixes in this freeze: dual-buffer snapshot (private stable copy, latest-wins), chunked 64 KB copy with interleaved stack service, gentle burst spreading (~25 ms per frame), Global-Timer lwIP scheduling, sticky S2MM error-bit clear.
- Next: C2 rate-up (interval 200->66 ms + pacing tightening) after an optional iperf benchmark; formal 10-minute soak test can be signed off at the next board session.

## 2026-09-08 Stage C1: live camera frames over UDP to PC (BOARD PASS)

- `UDP_CAMERA_C1_PASS`: `udp_video_tx_poll` now takes the latest completed DDR snapshot (`(PARKPTR CURRENT_READ + 2) % 3`, the pre-display slot — complete/stable/no contention) and streams it as type=0x01 frames at ~5 fps runtime / 1 fps monitor; GUI shows the live OV5640 image.
- Fixes en route: black-frame bug (send_one_frame always read the never-filled pattern buffer — now selects external snapshot vs pattern), D-cache invalidate before reading DMA-written DDR, sticky S2MM error bits cleared once after first frames (false CAMERA_STREAM_FAIL eliminated), forward declaration for park_current_read.
- Known items for C1.1: 丢帧/CRC 错 counters nonzero (burst PC-socket drops + suspected snapshot tearing) — plan: dual-pointer slot avoidance, burst pacing, evaluate lwIP UDP checksum; GUI fps field sampling quirk. (The "HDMI vs UDP color difference is expected behaviour" note written here was later disproven — the real cause was the R/B byte-order swap, fixed in FREEZE udp-color-fix-pass-20260908 at the top.)
- Evidence: `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/` (C1 GUI screenshots x3, full serial, per-fix hashes).

## 2026-09-08 Stage B1: board-to-PC UDP video stream PASS (1 fps pattern)

- Result: `UDP_TX_B1_PASS`. `app_component` V3.1.2 streams 640x480 RGB888 synthetic frames (921,600 B = 640 packets x 1,440 B + 32 B header, whole-frame CRC32, SOF/EOF flags) from the board to the PC peer at 1 fps; serial shows `UDP_TX frame=N packets=640 errors=0` (58+ frames, zero TX errors) and the GUI receiver shows the moving color-bar pattern with `完整帧` increasing at ~1 fps, `丢帧=0`, `CRC 错=0`.
- New sources: `2_fpga/0_diaplay_test/vitis/app_component/src/udp_video_tx.c/h` (sender; `UDP_TX_USE_CAMERA=0` gates stage C1), `main.c` rework — lwIP timers now scheduled on the ARM Global Timer (`xiltimer.h`/`XTime_GetTime`, 250/500 ms) because the ScuTimer interrupt path proved dead in this SDT build; `udp_video_tx_yield()` keeps ARP/RX alive mid-burst without recursion.
- PC tools (`3_host/udp_video/`): `mock_sender.py` (protocol-conformant pattern sender), `udp_video_rx.py` (CLI receiver, localhost self-test PASS 178 frames/0 loss/0 CRC), `udp_video_gui.py` → packaged `dist/EES331_UDP_Viewer.exe` (V1.0 31,187,636 B / V1.1 31,188,255 B at this milestone; **superseded 2026-09-08 by the V1.2 BGR-fix build 31,187,867 B, SHA-256 `a4b75ed3...` — see FREEZE udp-color-fix-pass-20260908 at the top**).
- Design contract: `1_docs/doc/OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md` (32 B header table, 640-packet framing, skip-on-loss policy, staged plan; supersedes the old plan's 192.168.1.x addressing with 192.168.240.x).
- Evidence: `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/` (B1 screenshots, full serial log, per-file hashes), `..._udp_host_tools_v1_run01/`, `..._udp_gui_exe_build_run01/`, `..._udp_video_protocol_design_run01/`.
- Known open items: camera S2MM stream error (`SR=0x15810`, SOF-early class) blocks stage C1 — check camera cabling/power first; PS config change verified clock-clean (BD diff: only ENET0/MDIO/GPIO-EMIO entries, FCLK/PLL untouched). GUI fps field reads 0/1.9 on a 1 fps stream (sampling display quirk). `UDP_TX_INIT_OK` prints "ticks" but means ms.
- Next: stage C1 — replace the pattern source with a VDMA completed-slot snapshot (PARKPTR-selected), camera S2MM must pass first; then C2 rate scale 5/15 FPS.

## 2026-09-08 Main project PS Ethernet loopback integrated (V3.1, BOARD PASS)

- Scope: `2_fpga/0_diaplay_test` Zynq PS now has ENET0 enabled (MIO 16..27, MDIO 52..53, PHY reset MIO 47, 1000 Mbps) alongside the proven OV5640 -> VDMA -> DDR -> MM2S -> HDMI path. PS config is item-for-item equivalent to the board-proven `2_fpga/2_eth_onlytest_zynq7020` loopback project (21-item PCW compare, report in the evidence run).
- App `app_component` V3.1: original camera/HDMI/UART firmware preserved; added lwIP RAW bring-up (static `192.168.240.10/24`, gateway `192.168.240.2`, MAC `00:0A:35:00:01:02`) and UDP echo on port 5000; `eth_service_ms()` keeps the stack serviced inside the existing 1 s / 5 s monitor loops. SDT build calls `init_timer()` only and does NOT enable D-cache, preserving the proven V3.0 memory behavior.
- Board result 2026-09-08 12:23: `MAIN_ETH_LOOPBACK_PASS` — NetAssist `192.168.240.2:5000` sent `你好` x3, all echoed (`3/3`, RX 12 B = TX 12 B) while the camera image kept displaying over HDMI.
- New hardware/software pairing (do NOT mix with the 2026-09-07 frozen pair below):
  - BIT `display_test_wrapper.bit` SHA-256 `7CB11F7DF165476EB86E3D8C43CC251FB1C454ECDB64B905F0931AD971EC192E7` (4,045,696 B)
  - ELF `app_component.elf` SHA-256 `52209F6271626A2B390E93E9DDF53DCD7E150EC655F2F2513B8C28F14C2ABA56` (851,088 B)
  - XSA `display_test_wrapper.xsa` SHA-256 `30644B3158D86D0D27C34ED60626179B17046CDA7B3AF51F35431B18652D22D0` (578,739 B)
  - Binaries live under `2_fpga/0_diaplay_test/vitis/hw_20260908_eth/`.
- Evidence: `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/` (integration report, before/after hashes, PASS screenshot SHA-256 `4AA8933B02B449F314D2E336908B41252FC9DE3DB91BF4E6B2742635AFF7CE0E`).
- Still owed: full UART serial capture (ETH heartbeat + HDMI heartbeat lines) for the raw serial record.
- Next: board-to-PC UDP frame sender (synthetic pattern + incrementing frame/packet IDs), then one VDMA frame snapshot; camera transport gates stay per `1_docs/doc/OV5640_PS以太网传输实施计划_2026-09-08.md`.

## 2026-09-07 OV5640 + PS VDMA + HDMI frozen visual PASS

- Result: `BOARD_VISUAL_PASS`. Three archived board photos show live OV5640 data through S2MM -> DDR -> MM2S -> HDMI. This is **not** `FULL_UART_ACCEPTANCE_PASS`; the final run has no complete UART capture.
- Frozen source: tag `camera-hdmi-visual-pass-20260907`; report: `4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/CAMERA_DISPLAY_SUCCESS_FREEZE_REPORT.md`.
- BIT SHA-256: `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624`.
- XSA SHA-256: `7374BD4EE2D30C726FC0135E1960BA2BE19BD22C3B9D75B0AB0BBEE1CE64A6E1`.
- ELF SHA-256: `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990`.
- Final PL facts: S2MM line buffer `1024`; dynamic Genlock; restored `~vio_hsync` / `~vio_vsync`; route `11060/11060`, 0 errors; WNS `9.510 ns`, TNS 0, all constraints met.
- Required recovery sequence: program the frozen BIT, load the frozen ELF, manually reset the camera capture once, then inspect the live image. The camera image becomes normal after this reset. Do not mix this pair with a rebuilt BIT/ELF. See `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md`.
- Next acceptance action: zero-change full-UART rerun with the same BIT/ELF; archive from startup through at least 60 seconds. Only then upgrade the label to `FULL_UART_ACCEPTANCE_PASS` if the UART is clean.
- Forbidden immediate actions: editing frozen source/artifacts, rebuilding the platform, changing VDMA controls/sync polarity/line-buffer depth/XDC/color format, or calling the photos a formal full acceptance PASS.

## 2026-09-05 晚间板级定位（优先于下方历史结论）

本次用户重新授权继续解决 HDMI。已撤销与原理图相反的物理字节交换，并用 JTAG/ILA 取得真实板级证据。

原 SDA 推挽驱动的实测为 `raw=1F1F0FFF011F, match=1A, done=0, error=1`，并非此前声称的 BD 回读成功。
开漏 SDA 诊断版本进一步捕获到地址72的NACK，发送连续高位时实际SDA随SCL改变。网表管脚与IOBUF连接已核对；下一步必须检查上拉VADJ及外部电气连接，不能把它直接定性为某个硬件短路，也不能靠放宽读回掩码继续推进。

完整结论、边界和实物检查点：`4_metrics/logs/2026-09-05_hdmi_root_cause_run02/DIAGNOSIS.md`。
当前板上是 run02 的临时诊断位流（初始化尚未通过），不是验收通过的发布版。原工程 bitstream 未覆盖，未写 Flash。
工程日志统一更新在 `2_log/2026-09-05/`；下方历史“配置已验证”或“字节已证实反接”等表述不适用于本次实测。

## 状态

- 日期：2026-09-04
- 2026-09-04 板级链路进度：正常 Vitis Run 的 UART PASS；DDR pattern/保持测试 PASS；VDMA MM2S 单帧和连续读协议 PASS。PS/DDR/VDMA 链路驱动的 HDMI 首轮板测无显示，后续发现一次测试加载了旧 bit，因此该轮不能作为有效结论。
- 2026-09-04 纯 PL HDMI 隔离测试：实际使用 `2_fpga/1_zynqtest_2025/project_1/project_1.xpr`，顶层已确认为 `hdmi_colorbar_vtc_top`。链路为 100 MHz → `clk_wiz_0` 25 MHz → 自研 1-PPC 480p VTC → 5 条竖彩条 → `hdmi_out_adv7511`。显示器已点亮，说明时序、HDMI 时钟、DE 和 I2C 配置链路基本可用；颜色仍不正确。
- 2026-09-04 颜色根因修正：原 ADV7511 初始化表把外部 YCbCr422 总线误配置为 RGB/YCbCr444，且 AVI Infoframe 错写为 YCbCr444/VIC4。已将 `0x16` 改为 `0xB9`（YCbCr422 Style 1），AVI PB1 `0x55` 改为 `0x29`，VIC `0x57` 改为 `0x01`，checksum `0x54` 同步改为 `0xAB`。修改位于 `2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv`。
- 2026-09-04 复测纪律：`1_zynqtest_2025/project_1` 中曾出现综合 DCP 时间早于源码修改、bit 略晚生成的情况。颜色修正后必须对 `synth_1` 和 `impl_1` 执行 Reset Runs，再综合/实现/生成 bit；只有确认新 bit 晚于全部源码后，板测才有效。
- 2026-09-04 纯 PL 彩条定义：640×480@60，5 条竖彩条，每条 128 像素；预期从左到右为白、黄、青、绿、品红，亮度递减。XDC 只保留 EES-331 引脚和 LVCMOS33 电平，不做时序约束。ADV7511 当前表中的 `0x55~0x5E` 是 AVI Infoframe，不是内部测试彩条。
- 2026-09-04 辅助工程脚本：新增 `2_fpga/0_diaplay_test/rtl/hdmi_new/build_hdmi_colorbar_vtc.tcl`，可创建独立 Vivado 工程并生成 25 MHz Clocking Wizard；但实际板测复测也可继续使用 `2_fpga/1_zynqtest_2025/project_1`。
- 2026-09-04 XSCT fallback：普通 Vitis Run 再现无串口输出时，使用 `4_metrics/logs/2026-09-04_vitis_uart_bypass_run33/run_uart_bypass.tcl` 手动初始化 PS、直写 UART1 FIFO、下载并运行 ELF。先看 `XSCT OK` 是否出现，以区分串口路径和应用运行问题。
- 2026-09-04 正常启动链修正：`app_component/_ide/launch.json` 原指向旧 `.bit` 和旧 `ps7_init.tcl`，已改为当前 XSA 的 `hw/sdt` 产物。进一步发现 FSBL 虽然重编但实际源 `zynq_fsbl/ps7_init.c` 仍是旧 DDR 配置；已同步为当前 XSA 生成版本并重建，`export/.../boot/fsbl.elf` 已同步。普通 Vitis Run/Debug 复测仍待用户执行。
- 2026-09-04 UART 自初始化：正常 Run 仍无输出后，`main.c` 已在入口第一行自初始化 UART1 时钟、MIO48/49、115200-8-N1 和 RX/TX，不再依赖 launch/PS7 是否成功完成 UART 配置。应用构建 PASS；下一步只用 Vitis 正常 Run/Debug 验收。
- 状态：HDMI TOP MODEL SIM PASS / CAM PCLK PLAN A IMPLEMENT PASS / BITSTREAM GENERATED / OOC ERRORS NONBLOCKING / BD CONNECTION CHECK PASS / RAW UART TX BOARD PASS
- GitHub：关键 RTL、集中后的测试台/仿真脚本、文档和最终证据已发布到 `main@d9dd5b4`
- 最新顶层归档：`main@12d31e1`，活跃顶层已改为 `hdmi_out_adv7511.v`
- 最新 XDC 归档：`main@c52e72b`，EES-331 HDMI/ADV7511 引脚约束已补齐
- 最新 BD 核对：run28，OV5640+HDMI 关键连线清单完成
- 分辨率：480p / 640x480@60
- 像素时钟：25.175 MHz
- 颜色空间：BT.709，RGB888 转 YCbCr422
- 目标路径：`E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new`

## 当前模块

| 模块 | 状态 | 说明 |
|---|---|---|
| `rgb2ycbcr422` | 实现完成，视频检查通过 | BT.709 定点转换与 Cb/Cr 奇偶打包 |
| `adv7511_init_table_pkg` | 实现完成，板级待验 | 480p 首版寄存器配置表 |
| `adv7511_controller` | 配置仿真 PASS | 上电延时、启动、完成/错误控制 |
| `adv7511_iic_data_xfer` | 配置仿真 PASS | 配置表读取、寄存器地址/数据传输握手 |
| `iic_protocal` | 直接复用用户源码，配置仿真 PASS | 底层 IIC 协议，ADV7511 地址 7'h39，分频 252 |
| `adv7511_cfg_top` | 配置仿真 PASS | 配置模块顶层，集成控制、传输和 IIC 协议 |
| `hdmi_out_adv7511` | Verilog 顶层整体 ModelSim PASS | `.v` 顶层集成、输出寄存与 ODDR 时钟转发，供 BD Module Reference 直接引用 |
| `iic_multi_byte` | 非活跃资产 | 保留用于后续连续寄存器突发扩展 |

当前可复现仿真入口：`E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`；测试台位于 `E:\competition\2_fpga\0_diaplay_test\sim`。Verilog 顶层最终复现证据见 `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22`。

BD 集成限制已关闭：原 `.sv` 顶层被 Vivado 2020.2 Module Reference 拒绝，错误码 `filemgmt 56-195`；当前已改为等价 `hdmi_out_adv7511.v` 顶层，独立工程确认可创建 BD RTL cell。旧 `.sv` 顶层已删除。

## 顶层接口冻结

`PIX_CLK`、`RST_N`、`RGB888[23:0]`、`DE`、`H_SYNC`、`V_SYNC`、`HDMI_INT`；`HDMI_SDA`；`HDMI_DATA[15:0]`、`HDMI_CLK`、`HDMI_HSYNC`、`HDMI_VSYNC`、`HDMI_DE`、`HDMI_SCL`。BD wrapper 实际导出端口均带 `_0` 后缀。

## 下一步

XDC 已按 EES-331 手册补齐 HDMI/ADV7511 引脚，并通过端口、重复引脚和电平标准检查。下一步在 Vivado 中重新加载约束，执行 BD 校验、综合、实现和时序检查。Verilog 顶层仿真证据见 `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22`；BD Module Reference 接受证据见 `4_metrics/logs/2026-09-03_hdmi_bd_verilog_ref_check_run23`；XDC 检查证据见 `4_metrics/logs/2026-09-03_hdmi_xdc_constraint_check_run24`。

最新实现失败原因已分析完成：`cam_pclk_0/AA22` 是普通 IO，但被用作相机采样时钟并插入 BUFG，触发 `Place 30-574 / Place 30-99`。尚未修改设计，等待用户在“降级 CLOCK_DEDICATED_ROUTE”与“重构相机 PCLK 采样架构”之间确认。分析证据见 `4_metrics/logs/2026-09-03_hdmi_impl_place_failure_analysis_run25`。

## 归档记录

- 已更新 `README.md` 的 HDMI 架构、验证状态和未验证边界。
- 已新增 `.gitignore`，排除 Vivado/ModelSim 缓存、库文件、波形和构建产物。
- 已选择性提交活跃 RTL、testbench、关键 Markdown、最终 ModelSim 命令与原始 transcript；未提交工程目录、旧架构和非活跃突发 IIC 资产。
- 已将三个测试台和 `run_modelsim.do` 集中到 `2_fpga/0_diaplay_test/sim`，迁移后整体 ModelSim 回归 PASS，提交为 `main@d9dd5b4`。
- 已将活跃顶层从 `hdmi_out_adv7511.sv` 改为等价 `hdmi_out_adv7511.v`，ModelSim 回归 PASS，Vivado 2020.2 BD Module Reference 检查 PASS，提交为 `main@12d31e1`。
- 已将 EES-331 手册中的 23 个 HDMI/ADV7511 引脚补入工程 XDC，并保存 `XDC_VALIDATION_PASS` 证据，提交为 `main@c52e72b`。
- 已分析综合后 `place_design` 失败原因，保留 Vivado 日志、DRC 报告和 AA22 引脚能力查询；尚无修复动作，提交为 `main@92a9bdc`。

## 固定流程

每次关键动作后必须同步更新 `E:\competition\7_logs\YYYY-MM-DD\` 四个日志文件和 `E:\competition\HANDOFF.md`；验证原始日志必须保存到 `4_metrics`。
## 2026-09-03 方案 A 实现结果

用户已确认采用方案 A，并根据 Clocking Wizard 实际频率将相机返回的 `cam_pclk_0` 约束为 41.600 ns（24.03846 MHz）；外层主时钟 `clk_in1_0` 不添加重复 `create_clock`，`cam_pclk_0_IBUF` 已设置 `CLOCK_DEDICATED_ROUTE FALSE`。静态证据见 `4_metrics/logs/2026-09-03_hdmi_cam_pclk_plan_a_apply_run26`。Vivado 2025.2 实现已通过，全局 WNS/TNS 为 `10.551/0.000 ns`，WHS/THS 为 `0.023/0.000 ns`，`cam_pclk` 域 WNS/WHS 为 `35.138/0.070 ns`，route error 为 0，`display_test_wrapper.bit` 已生成。OOC 子 run 中的 `Failed to create directory C` 为非阻塞错误，详细判定见 `4_metrics/logs/2026-09-03_hdmi_ooc_synthesis_error_analysis_run27`。下一动作是板级 HDMI 显示验证；是否清理 OOC error 由用户确认。
## 2026-09-03 BD 连线核对

已对照 2020 `cam_vdma_hdmi_true` 工程生成清单：`2_fpga/0_diaplay_test/doc/bd_ov5640_hdmi_connection_checklist.md`。OV5640 采集、Video In、VDMA S2MM/MM2S、HP0/HP1、Video Out、VTC、`pix_frame_display` 到新 HDMI 前端的关键连线一致。当前控制面使用 SmartConnect，参考工程使用 AXI Interconnect；Zynq 7010/7020、50/100 MHz 外部时钟、PS FCLK0 频率和 HDMI 输出架构差异均记录为工程基线差异。VDMA S2MM line buffer 当前为 512、参考为 1024；当前 `rom_data` 接常量 0，参考接 ROM。二者需理解但不阻断当前板测。证据见 `4_metrics/logs/2026-09-03_bd_connection_check_run28`。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
UART delay and print headers now declared locally and rebuild pass.
GUI build and run log check pass; serial retry with COM6 open before Run.
XSCT target check complete after direct UART attempt; board power cycle required before next Run.
## 2026-09-03 UART 无输出根因更新

用户确认 Zynq DDR 型号/配置未按 EES-331 板卡正确选择，并已完成修改。该根因可解释 FSBL/应用进入 DDR 后跑飞、debug session 提前断开、自动 COM6 终端关闭且 UART 无输出。当前仍是根因记录，不是 UART 板级 PASS；必须重新生成/导出 XSA，更新 Vitis platform/BSP/FSBL，重建应用，重新上电后在唯一 COM6 `115200-8-N1` 终端验证 header、heartbeat 和 RX echo。证据见 `4_metrics/logs/2026-09-03_vitis_uart_ddr_root_cause_run31/ddr_root_cause.md`。
## 2026-09-03 最小 UART Raw TX 测试

用户已完成 DDR 修正、XSA 更新、platform/BSP 更新和重新编译，但 UART 仍无输出。`app_component/src/main.c` 已简化为直接写 PS UART1 TX FIFO（`0xE0001030`），仅检查 TX FULL（`0xE000102C` bit3），并持续输出 `UART OK\r\n`；不再依赖 `xil_printf`、BSP API、heartbeat 或 RX echo。SOURCE UPDATE COMPLETE / BUILD PASS / BOARD TEST PENDING；ELF text/data/bss 为 `25600/1420/22952`。复测需唯一 COM6 `115200-8-N1` 终端；若无输出，排查 UART1 MIO、时钟/波特率、初始化、COM 端口映射和硬件路径。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/minimal_raw_tx.md`。
## 2026-09-03 XSCT 直接 UART 分流结果

Vitis Run 日志缺少完整下载/运行流程，调试器反汇编出现无效内容，不能证明应用执行。改用 XSCT 直接执行新 XSA 的 `ps7_init.tcl` 后，寄存器回读确认 `MIO48_CTRL=0x12E0`、`MIO49_CTRL=0x12E1`、`UART_BAUDGEN=0x7C`、`UART_BAUDDIV=6`；已直写 `XSCT OK\r\n`，并下载运行最小 `app_component.elf`。当前等待 COM6 确认是否出现 `XSCT OK` 和重复 `UART OK`。若两者都出现，UART 硬件路径正常，问题收敛为 Vitis Run 流程；若都没有，继续排查 COM6 与板卡 UART 的硬件映射。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/direct_xsct_uart_result.md`。
## 2026-09-03 UART TXFULL 位修正

用户确认 COM6 只出现 XSCT 直写的 `XSCT OK`，证明 COM6/UART1 硬件路径可用。XSCT 停机确认应用卡在 `main.c:9` 的错误等待循环：原掩码使用 `0x08`，但 Zynq UART 状态寄存器 `0x08` 是 `TXEMPTY`，BSP 定义的 `TXFULL` 是 `0x10`。已改为 `UART1_STATUS_TX_FULL=(1UL << 4)` 并重建 ELF（text/data/bss `25600/1420/22952`），随后通过 XSCT 下载运行。当前 UART BOARD TX 为 FIX APPLIED / COM6 REPEAT CONFIRMATION PENDING。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/txfull_bitfix_result.md`。
## 2026-09-03 UART Raw TX Board PASS

修正 Zynq UART1 `TXFULL` 位后，COM6 已连续输出 `UART OK`，`app_component.elf` 经 XSCT 加载到 `0x00100000` 并运行；调试反汇编也显示有效 `_start/main/uart_puts/uart_putc/exception` 代码。结合 DDR 修正，最小 UART 应用的板级执行链路已通过。当前结论为 `RAW UART TX BOARD PASS`；UART RX echo 和 HDMI 显示仍待验证。当前 `main.c` 仍是最小 TX 固件。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/uart_board_tx_pass.md`。


## 2026-09-05 HDMI A5 板级签名与暂停边界（历史状态）

- 用户重新生成并下载后观察到 `LED0..LED7 = 8'b1010_0101`，与固定构建签名
  `8'hA5` 完全一致，证明 `hdmi_colorbar_vtc_top` 的纯 PL bitstream 已被正确加载。
- A5 版本只改变 LED 调试输出，没有改变 HDMI 视频数据，因此画面没有变化是该版本的
  预期结果，不能据此判断颜色修正或寄存器回读是否生效。
- 已加载 bitstream 时间为 `2026-09-05 13:11:49.160`；当前顶层与重写后的
  `iic_protocal.v` 均在约 `13:41` 才修改。因此该板测不包含、也不验证当前 I2C 重写。
- 该段记录的是当时的暂停状态；后续已恢复协议修改，并完成协议与 SW0 版本的联合 RTL 回归。

## 2026-09-05 SW0 RGB/YCbCr 模式切换实现

- 纯 PL 顶层 `hdmi_colorbar_vtc_top` 新增 `SW0` 输入，约束为 `AB6`；S2 仍保持为 PS
  专用复位键，不接入 PL。
- `SW0=0` 为 RGB888 经 FPGA 转换，`SW0=1` 为直接 BT.709 limited-range YCbCr422。
- 模式先两级同步，再在帧起点锁存；直出数据和控制信号保持与 RGB 转换路径相同的三拍
  延迟，避免半帧切换。
- LED7 显示当前直出模式，LED6:LED0 保留低七位回读调试信息；复位继续显示 A5。
- ModelSim 通过：`4_metrics/logs/2026-09-05_hdmi_mode_switch_run01/mode_result.txt`
  报告 `MODE_SWITCH_PASS`，并保留非空 WLF。尚未生成新的 bitstream。

## 2026-09-05 协议与 SW0 版本合并验证（历史，已被后文原始协议恢复替代）

- 当时用户恢复协议修改要求；当时活动版本继续使用重写后的
  `2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v`，未恢复旧版协议。
- `iic_protocal.v` 已按板级接口改为 FPGA 单向输出 SCL、SDA 保持双向开漏，支持单寄存器写、
  随机读/重复 START、ACK/NACK、单字节读后的主机 NACK、合法 STOP/错误 STOP，并导出
  `iic_error` 和 `iic_rd_data_valid`。
- `adv7511_iic_data_xfer.sv` 完成 34 次写入后读取 6 个关键寄存器，保存全部原始回读值，
  并在读回不匹配时给出位图而不提前终止。
- 独立 Vivado 建工程脚本 `build_hdmi_colorbar_vtc.tcl` 已补入
  `../iic/iic_protocal.v`，避免新工程遗漏底层协议源文件。
- 当前源码回归证据：
  `4_metrics/logs/2026-09-05_hdmi_protocol_sw0_run01`。
  底层协议 PASS；配置成功回读 `bitmap=111111/raw=101208bd0110`；故意失配
  `bitmap=111011/raw=101208bc0110`；NACK 快速错误 PASS。
- 协议和 SW0 均只完成 RTL/ModelSim 验证，尚未由本轮生成或下载 bitstream；板级结论仍待
  用户重新综合、实现、生成并下载当前源码。

## 2026-09-05 HDMI 黑屏修正

- 用户反馈协议版本下载后 HDMI 完全无显示。优先收敛到 ADV7511 初始化条件，而不是改变
  已通过仿真的 RGB/YCbCr 视频路径。
- 按 ADV7511 Hardware User's Guide 的上电要求，将配置启动延时从 120 ms 改为 200 ms。
- 重写协议使用开漏 SCL/SDA；为避免板上外部上拉缺失或未装导致总线浮空，在
  `hdmi_colorbar_vtc_top.xdc` 对 `HDMI_SCL/HDMI_SDA` 增加 FPGA 弱上拉。
- SW0 模式切换仿真在该修正后仍为 `MODE_SWITCH_PASS`。尚未生成 bitstream，下一步由用户
  重新综合、实现并下载验证：复位时 LED 应为 A5，释放复位后检查 LED 和 HDMI 是否恢复。

## 2026-09-05 原始 I2C 协议恢复（当前状态）

- 用户明确要求停止使用重写协议并恢复原协议；当前活动源已恢复
  `2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v` 的原始状态机和端口。
- `adv7511_iic_data_xfer.sv` 已移除重写版 `iic_error` 连接，改为沿用原协议的
  `iic_done` 加上外层超时判断；SCL 仍是 FPGA 输出，SDA 仍为双向开漏。
- 现有 SW0 RGB888/YCbCr422 帧边界切换、五色彩条、LED/约束修改均保留。
- 原始协议配置级回归通过：
  `4_metrics/logs/2026-09-05_adv7511_i2c_original_run01/cfg_success_result.txt`
  为 `bitmap=111111/raw=101208bd0110`；故意失配结果为
  `bitmap=111011/raw=101208bc0110`。
- 当前仍未生成或下载新的 bitstream；用户下一步可直接在 Vivado 中重新综合、实现、生成
  bitstream 并观察 HDMI 与 LED。

## 2026-09-05 板级竖条与物理字节交换（当前待上板）

- 用户反馈两个 SW0 输入模式都能显示但颜色错误，图像呈现白色偏绿、黑色偏红、红/蓝区域
  逐像素竖条，绿色区域基本正常。
- 该现象对应 ADV7511 将当前逻辑 `{Y,Cb/Cr}` 按 `{Cb/Cr,Y}` 解释；不是 RGB 转换公式
  的主要问题。
- 保留 `R0x16=0xBD` Style 3 和逻辑 `{Y,Cb/Cr}`，在
  `hdmi_colorbar_vtc_top.v` 与 `hdmi_out_adv7511.v` 的物理输出边界加入
  `{data[7:0],data[15:8]}` 字节交换。
- RTL 自检通过：16/16 像素无 YCbCr mismatch；证据见
  `4_metrics/logs/2026-09-05_hdmi_physical_byte_swap_run01`。
- 当前没有生成 bitstream；下一步重新综合下载后检查五色顺序及 `R0x16` 回读值。

## 2026-09-05 最新板级结果归档（暂停修改）

- 用户上传的最新板级照片已保存至
  `4_metrics/logs/2026-09-05_hdmi_board_result_run01/board_result_2026-09-05_run02.jpg`，
  详细说明见同目录 `board_result.md`。
- 现象：HDMI 能够稳定显示，但五色图像仍与预期不匹配，画面存在明显密集竖状条纹；本结果不能作为颜色或寄存器回读正确的验收结论。
- 本次只做证据归档和日志更新；没有修改 RTL、I²C、ADV7511 寄存器表、物理字节交换、XDC 或仿真文件，也没有生成/下载新的 bitstream。
- 图片 SHA-256：`E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E`。
- 当前工作边界：等待用户明确重新启动调试；在此之前不继续尝试颜色修正或协议修改。
(current tail continued)

## 2026-09-06 ADV7511 final board PASS

- Final 480p solution is frozen: logical `{Y,Cb/Cr}`, ADI BT.601 limited-range
  CSC table V1.3, `R0x15=01`, `R0x16=38`, `R0x48=08`, and an EES-331 port
  byte swap at `physical_data`.
- Board result: White / Black / Red / Blue / Green solid bars, no stripes.
  Raw photo:
  `4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/board_pass_white_black_red_blue_green.jpg`.
- ModelSim physical-swap regression PASS marker:
  `MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch`.
  Stable result file: `mode_result.txt` in the same run folder.
- Do not restore `physical_data = selected_data`; the unswapped build produced
  chroma stripes in the red/blue/green bars.

## 2026-09-06/07 开发机迁移 + 2_fpga 验证版合入 + AI 侧手势通路

- 开发机迁移：项目根目录现为 `E:\Work\Projects\AMD_proj\FPGA_competition_2026`（本仓库完整克隆），Vivado 2025.2 ML Standard 已装（仅 Zynq-7000 家族）。旧开始菜单快捷方式指向失效路径，桌面快捷方式已修复。
- 2_fpga 更新：以队友交付的验证版 zip 整体合入——`0_diaplay_test`（hdmi_new V1.8：`adv7511_init_table.sv` 含 CSC 与读回校验，新增 rtl/HDMI TMDS 直出、data_pre、fr_display、ov5640_data_cap；proj display_test 工程；sim 新增 4 个测试台）、`1_zynqtest_2025`（本地恢复，含 ILA，按约定不入库）。合入前旧版已备份至本地 0_assets（不入库）。
- ADV7511 颜色根因分析（文档级，未板测）：4:2:2 输入映射受 R0x48[4:3] 对齐与 R0x16[3:2] Style 双控制，且寄存器 Style 值与手册编号不对应（Linux 驱动注释佐证）；EES-331 仅接 D[15:0]，Style 2/3 使芯片读 D[23:16] 悬空脚。队友 CSC 直出 RGB 方案已板测通过，维持不动；分析留作 422 直通备援路线资料。证据：`7_logs/2026-09-07/`（HWUG Table 7、EES-331 手册页截图）。
- AI 侧（3_host）：手势模型 v1 训练完成（YOLOv8n + Roboflow hand-gesture v6，7 类，test mAP50 0.730；Stop/Thumbs up/Up/Down 优秀，Left/Right/Thumbs Down 为弱项）；PC 全链路（摄像头→JPEG→UDP→ONNX CPU→JSON 回传）实测通过，P50 62ms；UDP 协议 v1 定稿于 `1_docs/legacy/interface.md`（分片/心跳/异常处理）。
- 待办：①2025.2 环境基线 bit 复现（Reset Runs→板测彩条）②PS 显示验证 ③lwIP 发帧端（协议见 1_docs/legacy/interface.md）④AI 侧自采 Left/Right/Thumbs Down 数据重训 v2 ⑤舵机臂下单 ⑥中期报告 10-09。
- 详细记录：`7_logs/2026-09-07/` 四件套。

## 2026-09-11 SD/PYNQ 摄像头双路输出

- 指定目录 `2_fpga/0_diaplay_test/pynq` 已完成 PYNQ 3.0.1/Linux 控制层：加载配对 Overlay、用 `pynq.allocate` 管理三帧 VDMA 缓冲、HDMI 连续显示，并以 OV56 协议向 PC 发送 UDP 视频。
- 板卡固定业务地址为 `192.168.240.10/24`，PC 有线网卡为 `192.168.240.2/24`，UDP 端口 5000，默认发送 5 fps。PC 使用 `3_host/udp_video/dist/EES331_UDP_Viewer.exe`。
- 当前已部署且未重刷的 SD 卡保持 SW8 为 SD 启动，上电后由 `ees331-camera.service` 自动加载 PL 并启动业务；无需 Vitis、JTAG、Jupyter 或手工执行 Python。通常等待约 60 至 90 秒。
- 验证结果：`PYNQ_CAMERA_HDMI_UDP_PASS`、`SD_REBOOT_AUTOSTART_PASS`。120 秒运行发送 600 帧/384000 包且 VDMA 无运行错误；用户确认 HDMI 与 PC 均为随动作变化的实时画面。最终软件重启后 PC 接收 604 帧，CRC/丢帧/坏头均为 0。
- 验证边界：软件重启自动恢复已经通过，物理断电冷启动尚未单独验收。若重刷当前基础 IMG，业务文件、CMA 参数、网络配置和 systemd 服务会丢失，需要重新部署。
- 原 XSA、`main.c`、`BOOT.BIN`、`IMAGE.UB`、`BOOT.SCR` 未修改。完整证据见 `4_metrics/logs/2026-09-11_pynq_camera_run01/REPORT.md`。
- 后续顺序已冻结：先将当前成果上传至 `codex/full/pipidandan-superman`；确认远端提交后，再为 SD Builder v0.2 增加完整 IMG 的 PYNQ 应用注入，并在 `1_docs` 编写零基础开发教程。

## 2026-09-11 SD Builder v0.2.1 整合完成

- Gate 1 已上传并核对远端提交 `927548961e5cc3d13d5de67cc613071aa5df63a5`，随后才开始 Builder 和教程工作。
- `3_host/pynq/sd_boot_builder_v02` 已增加完整 IMG 的 PYNQ rootfs 注入，写入摄像头应用、配对 Overlay、`cma=128M@0x10000000`、固定网络和 `ees331-camera.service`。
- 整合模式固定要求当前已板测 XSA 哈希、完整 IMG 和 `manual` PL 模式。这里由 systemd 在 Linux 启动后自动调用 Overlay，日常上电无需人工运行 Python。
- Cygwin `debugfs/e2fsck` 1.44.5 的模块测试、逐文件读回和文件系统检查通过。MSYS2 e2fsprogs 获取失败作为历史失败保留，不是最终依赖路径。
- 冻结 EXE 首次完整构建在 `2026-09-11_sd_builder_v02_220613_158787` 因 PyInstaller Tcl/DLL 污染 XSCT 而失败；修复 `SetDllDirectoryW(None)` 和 Tcl 环境变量清理后重打包。
- 最终 `EES331SDBootBuilder_v0.2.1.exe` 大小 22,520,487 字节，SHA256 `c2966e6fa52bfb8786c0232221e4eb540b96b383406be1e38d581bf3a070f49a`，GUI 自检通过。
- 最终 EXE 完整构建目录：`4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce`；结果 `SD_PACKAGE_STATIC_PASS`，应用注入、启动文件、完整读回均 PASS。
- 输出 IMG 大小 7,858,807,808 字节，SHA256 `8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`。完整 IMG 不上传 Git。
- 写卡使用 `8_tools/win32diskimager-1.0.0-install.exe`。该新 IMG 尚未写卡；下一步是备用 SD 卡物理断电冷启动、UART、HDMI 和 UDP/PC 联合验收。
- 零基础教程：`1_docs/PYNQ零基础开发与EES331摄像头工程实战.md`。
- 整合报告：`4_metrics/logs/2026-09-11_sd_builder_pynq_integration_run01/REPORT.md`。
- Git 功能提交 `87ce6f3` 已与最新 main 合并，第一轮远端核对提交为 `6f76d67dfa597cb56281a9242256f889d1e3205c`；上传回执见同一整合证据目录的 `upload_result.json`。

## 2026-09-11 SD Builder v0.2.2

增加自定义部署包输出目录（GUI、CLI --output-dir、JSON output_dir）。独立子目录避免覆盖，逐文件 SHA256 验证后发布；留空兼容旧版。5 项测试、冻结 EXE 自检和真实完整 IMG/自定义复制读回通过。发布入口 `8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.2.exe`；报告 `4_metrics/logs/2026-09-11_sd_builder_output_dir_run01/REPORT.md`。新 IMG 未写卡冷启动。保留 v0.2.1。

## 2026-09-11 集成 IMG 板测与归档入口

- 用户实际写卡并验证成功的镜像来自 `4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce/output/ees331_pynq_sd.img`，不是后续仅完成离线构建的 224206 镜像。
- 本机正式归档副本为 `9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`，大小 7,858,807,808 字节，SHA256 `8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`。
- 板测结果：SD 启动正常，OV5640 配置完成 LED 点亮，HDMI 和 PC UDP 上位机都显示随动作变化的实时画面。最初 PC 零帧是网线未连接，插好网线后恢复正常。
- EES-331 最小系统基线、当前集成镜像和配套启动分区分别归档于 `9_pynq/sd/01_base_ees331`、`02_integrated_camera_hdmi_udp`、`03_boot_partition`；通用 PYNQ-Z2 镜像已退出项目基线，清单见 `9_pynq/sd/manifests/images.json`。
- 后续写卡、复现和排障从 `9_pynq/sd/README.md` 开始；不要把 224206 镜像描述为已板测版本。

## 2026-09-12 PL 板载蓝牙 UART 诊断工程

- 新入口：`2_fpga/1_ble_test/README.md`；Vivado 2025.2 工程位于
  `2_fpga/1_ble_test/proj/ble_test_vivado_2025_2`。
- UART TX、UART RX 和 AT 控制器均已改为严格三段式 FSM：时序状态寄存、组合
  次态、时序输出/数据通路；三个复位状态均为 `STATE_IDLE`。
- XSim 重跑已覆盖 `AT\r\n -> OK` PASS 和无响应 timeout FAIL，标记
  `BLE_RTL_SIM_PASS`。
- 强制重置综合后重新完成实现和 bitstream：WNS `+2.148 ns`、WHS `+0.083 ns`；
  当前 bitstream SHA-256 为
  `B00770EDC2EE381ED195DD2068CE058088F6A5CEF95CDDD6295AC40C897029F8`。
- 初版 hash `E96E995D...` 因不符合 FSM 编写规范已作废，不得上板。
- 上板同时使用 `impl_1/ble_test_top.bit` 与 `impl_1/ble_test_top.ltx`。ILA 已含
  TX/RX、字节、握手、状态、电源和复位信号；LED0/1/2/3 分别为 PASS、timeout、
  response seen、frame error。
- 用户已完成上板门禁：LED0--LED7=`10100110` 解码为 PASS=1、timeout=0、
  response_seen=1、frame_error=0、state=`0110`（`STATE_PASS`）；ILA 以
  `rx_done==1` 触发并捕获 `rx_data=4F`。AT/UART 有序 `OK` 返回判定为
  `BLE_PL_UART_AT_RESPONSE_BOARD_PASS`。
- 当前证明范围是 PL UART 与板载 MLT-BT05 的 AT 响应链路；尚未证明 PC 或机械臂
  BLE 无线连接、角色、UUID与双向透明传输。下一步保持现有 bitstream，先做 PC
  扫描和连接验证。完整报告：
  `4_metrics/logs/2026-09-12_ble_board_at_response_run01/REPORT.md`。
