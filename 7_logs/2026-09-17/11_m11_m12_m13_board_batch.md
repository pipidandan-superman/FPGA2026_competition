# M11→M12→M13 授权批（A2 上板冲刺，2026-09-17 夜）

用户授权："先M11，然后12，13. 上板看过结果后再决定是否继续优化。
我现在希望能够尽快上板验证" —— 三门一批，A2b 缓议。

## 1. M11 run05（A2 全网承证，进行中）

- TB tb_yolo_fullnet V1.2：dsc_walk（prog token16，e=8 逐层最优
  38 oc外/25 n外）+ 第二条 X AXI 读主 inline 4 深突发队列 BFM（活镜像
  服务）+ W 读 BFM 同款升级（bfmerr 判据）。
- 激励：m11_vecgen 挂 a2_budget_calc walk 规则再生成；ddr/lut/n_* 与
  v27 冻结集逐字节同（sha 承证），prog.hex 仅 38 词 token16 0→1
  （备份 prog_hex_v27_walk0_backup.hex）。
- SMOKE（MAXCONV=3）PASS：
  `TB_FULLNET_SMOKE convs=3 psops=2 compared=819200 dut_wr=819200
  head_bytes=0 ldone=3 adone=1 bfmerr=0/0 wost=2 xost=2`；
  conv0 16.161ms walk=1（v27 23.273，−31%）、conv1 42.681ms walk=1
  （v27 64.876，−34%）、conv2 52.130ms walk=0 —— 双 walk 序均实证。
- FULL 63 conv 后台跑中（msim_a2/run_m11_a2.sh，work_a2 库）。
- 证据目录 4_metrics/logs/2026-09-17_yolo7020_m11_fullnet_run05/（哈希
  清单与 smoke 段已写）。

## 2. xrowgen V1.3a（OOC v28 首跑拦下的综合非法）

- OOC v28 首跑：Synth 8-6859 多驱动 ×8 = iq_cnt_r[3:0] 被 start 快照块
  （#8b 加的复位）与占用率块（同条件同值复位）双 always 驱动——仿真
  同拍同值逐位等价、综合非法的经典陷阱。xrowgen 首次过综合才暴露。
- 修复 V1.3a：删快照块副本，唯一写者=占用率块。
- M7 run03 回归：`TB_XROWGEN_PASS tiles=66 bytes=29342 cmds=1887
  ars=1889 peak_ost=2` —— 与 run01/run02/run9 判定行逐字段一致。
- OOC v28 重跑中。

## 3. M12 双门

- CSR/engine 门 run01 **PASS**：
  `TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
  ldone=6 adone=1 csr=0 xbfmerr=0 xost=2`。
- RTL A2 化三件（均不在 M11 编译集，不影响在跑仿真）：
  - yolo_csr V1.2：DESC1[19] walk 影子位 + VER 0x0002_0000
  - yolo_engine_top V1.1：组合 X 口退役 → x_m_axi_* 顶层引出 +
    dsc_walk 接线（独立 work_chk 库过编译）
  - tb_yolo_engine_top V1.1：FLDS 29（walk@28）+ X BFM（M11 同款）+
    DESC1 walk 打包/读回 + VER 期望
- 地址合同 address_map.md 三处同步（DESC1 walk 位 + VER + V1.1 落款）。
- OOC v28（重跑）= M12 时序门，进行中。

## 4. M13 备料

- proj/board_sys/：ps7_ees331.props（旧 display_test.bd 提取 533 项
  EES-331 板级配置：DDR MT41K256M16 RE-15E 1GB、UART1 MIO48-49、
  ENET0 MIO16-27、SD0 MIO40-45、晶振 33.333）→ ps7_ees331.tcl
  （+A2 覆盖：FCLK0=150MHz、HP0/1 on、GP0 on）。
- build_board.tcl：块设计 yolo_sys = ps7 + engine(PROD-16x16 默认参) +
  proc_sys_reset(dcm_locked 恒 1) + GP0→CSR@0x43C1_0000 +
  engine m_axi(W读+Y写合并推断)→HP0 + x_m_axi→HP1；无 PL 外部引脚、
  无 IRQ（v1 轮询）。gate = BOARD_BITSTREAM_PASS + yolo_a2.xsa。
- 板端软件路径：pynq/（yolo_runtime 黄金解释器 + board_pack 128 帧
  G2 黄金）+ M11 stim 即完整板程序（ddr.hex/prog.hex/lut_all.hex），
  /dev/mem 固定地址驱动待写。

## 4. OOC v28：FAIL@150 → 60MHz first-light 承证路线

- 判定 `GEMM16_OOC_TIMING_FAIL wns=-8.750 fmax=64.86/150`（24305
  端点），但 300 条最差路径全部落 X 通路（xrowgen×582 + dma_x×18），
  GEMM 核/重量化/W 路未回归 —— xrowgen 首次过综合时序暴露。
- 两主锥：①`(pt_m−1)*sw` 行跨度比较链 → 发射队列 CE（15.1ns、
  DSP+CARRY×3、12 级）；②`oy0 → ×sh → ×iw 双乘级联 → pt_row0`
  单周期两 DSP 串联。结构性欠流水，同 B0 addrgen 除法坑家族。
- 处置（守"板后决策优化"）：**不动已承证 RTL**，FCLK0 降 60MHz
  （数据路径 15.128ns < 16.667−setup，预期 WNS≈+0.8），出货时钟
  重跑门 ooc_v28b60.tcl（进行中）；xrowgen 流水化与 A2b 同为板后
  候选。板构建三件已同步 60MHz（ps7_ees331.tcl 三频率项 +
  yolo_sys.xdc 16.667 + build_board.tcl 头注）。
- 存证：4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v28/（含
  v28_p300.rpt 模块归属分解）。

## 5. M13 板端驱动（PC 自测全绿）

- pynq/pl_m11.py：/dev/mem CSR@0x43C1_0000 + DDR carve-out
  （默认 0x30000000）+ prog.hex 执行器（解释器 = TB 逐位镜像）；
  LUT 窗口预载 → DESC0..5/BASE 六件（+DDR_BASE）→ START 门铃 →
  STATUS ldone 轮询 → DDR 读回 y 区 → g_base 黄金逐字节比对
  （板端复刻 per-conv check）→ heads 转储 sha256 终判。
  --mkbin 产 prog.bin/lut_all.bin/ddr.bin（板端免解析 30MB hex）。
- pynq/pl_m11_selftest.py：FakePL 黄金 conv（stim 自带参数重算），
  PC 全流程 `PL_M11_PASS convs=63 psops=65 compared=3553900 nerr=0
  head_sha256=9ce70525fc1732cd...` —— 板端剩余未知仅比特流/HP 实流/
  DDR 一致性。
- 自测钉死三个合同事实：prog 行 FLDS=28（29 会静默早 END）；
  W 行距 ceil(K/8)*8 且区按 oc_tiles×8 分配（oc 后是垫料）；
  bias 字= bias_eff（z_sum 已并入）。
- deploy_m13.md：部署手册（scp+fpgautil、drop_caches、判据行、
  oops 退化路径、逐层 ms 采集对比表）。
- 存证：4_metrics/logs/2026-09-17_yolo7020_m13_driver_selftest_run01/。

## 6. OOC v28b60 PASS + 板级构建三跑三拦

- **v28b60 判定**：`GEMM16_OOC_TIMING_60M_PASS wns=0.806 whs=0.040`，
  DSP 147/220、RAMB36 52/140（+32=wbuf BMG）。与 v28 单时钟域解析
  预期（−8.750+10≈+0.81）吻合；判定行 fmax=170.6 为 tcl 硬编码
  参考周期折算显示伪影，以 wns 为准（v29 修显示）。存证
  4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v28b60/。
- **功耗承证**（回应用户"开一晚会不会烧"）：v28b60 routed DCP
  report_power@25°C 环温 → PL 0.722W、结温 33.3°C、最高允许环温
  76.7°C（<85°C 上限）；PS 空闲 ~1.5-2W，整夜空闲安全，60MHz
  负载也远在包络内。v28b60_power.rpt 已入存证。
- **build_board.tcl 三跑三拦（逐层剥洋葱）**：
  1. `set_property -dict $ps7_cfg` 二次求值 → MIO_TREE 值里的
     `['SD…` 被当命令执行（invalid command name "'SD"）；
  2. 改逐对 foreach 后 → 属性顺序校验：MIO16 LVCMOS 1.8V 需
     BANK1 电压先设（两遍法：PCW_PRESET_BANK?_VOLTAGE 先行）；
  3. 仍炸 → 根因：display_test.bd 的参数值是 {"value": …} 包装，
     MIO_TREE_PERIPHERALS 的 value 是**二元字符串列表**，首版抽取
     用 Python repr 写成 `['..','..']` 非法 TCL。重新生成
     ps7_ees331.tcl：str→`{v}`、list→`{{e0} {e1}}`，533 项含
     A2 覆盖（FCLK0=60 三项 + HP0/1 + GP0）。
- **五至八跑（继续剥洋葱，每跑前进一层）**：
  4. HP 自动化方向反了：config Slave+引脚=m_axi 时规则反查从侧
     （"No valid slave interface"）→ 与 GP0 段同构：config
     Master=/engine/m_axi + 目标引脚 ps7/S_AXI_HP0，HP0/HP1 双过；
  5. GP0 自动化已把从段自动分配为 **engine/s_axi/reg0**
     @0x4000_0000/1G（段名 reg0 非 CTRL）；已分配段的 OFFSET 是
     只读属性 [Common 17-107] → `delete_bd_objs` 删自动映射后
     `assign_bd_address -offset 0x43C10000 -range 0x10000` 重指；
  6. module_ref 推断的 AXI 接口默认 **FREQ_HZ=100MHz 且无时钟关联**
     （validate 实拦 BD 41-237/41-967）→ 建 cell 后自动化之前显式
     `CONFIG.FREQ_HZ 60000000` ×3 接口 + `CONFIG.ASSOCIATED_BUSIF
     {s_axi:m_axi:x_m_axi}` 挂 clk_i → **BD 校验通过**；
  7. `launch_runs synth_1 impl_1 -to_step write_bitstream` 被
     [Vivado 12-1015] 拒（write_bitstream 对 synth_1 非法步）→
     两段式：synth 单发 + impl -to_step。
  八跑进行中（BD 已过 → synth/impl/bitstream，预计 ~1h）。

## 7. M13 首上板（run01，深夜，失败保留现场 → 晨间重试）

- 板环境钉死：PYNQ 3.0.1/PetaLinux 2022.1、无 fpgautil、sudo 需 stdin 喂、
  devmem 不存在、PYNQ venv Bitstream "No Devices Found" 不可走。
- **格式关**：fpga_manager 只认逐 32 位字字节交换 .bin（内核 has_sync 要
  dword 对齐 66 55 99 aa）；.bit 与 write_cfgmem SMAPx32 均被拒；Python
  `>u4→<u4` 手工转换 `yolo_a2_fpgamgr.bin`（sha 51a1927adcd4df18）通过。
- 分段验证：传送哈希 9 件全对 → 下载 OK STATE=operating → **身份读
  CSR_ID=0x594F4C31 / CSR_VER=0x00020000（PL 活、GP0 正常）** →
  全程序 stim 装载后 conv0 启动 → ~10 分钟后板失联（ping 0/3、
  COM6 静默无 panic = 疑似内核整体冻结）。
- 首要嫌疑：DDR carve-out 0x30000000 踩内核/CMA；既定退化路径
  --ddr-base 0x38000000 重试一次，等用户晨间断电重启后执行。
- 存证：4_metrics/logs/2026-09-18_yolo7020_m13_board_run01/
  （README 含完整时间线、分析排序、晨间重试清单）。
- 同晚：zynq-pynq-overlay-workflow skill 内容有效（ees331 板档案直接
  指导了分段验证/静默纪律），但 Skill 工具注册需会话根在 E:\competition。

## 8. M13 run02（晨间唯一一次重试，2026-09-18 02:0x——再冻，停手保留现场）

- 用户断电重启后执行。**证据驱动的偏离**：先做只读占用扫描
  （/proc/kpagecount/kpageflags，sudo）再选段，**否决了文档退化段 0x38000000**
  （1803/3254 页在用 55%，比 run01 的 0x30000000 的 564/3254 更糟）；
  全址扫描 48 个全空 14MB 窗口，取 **0x08000000**（远离内核 <16MB 与
  CMA@0x10000000；分配器自高向低填页，低址最不易被蚕食）。
- 发射链（单条 ssh）：drop_caches → T-0 复扫 0/3584 全空 → 断电后重载
  PL（state=operating）→ 身份读 CSR_ID/VER 绿（mmap 路径；**本板 /dev/mem
  的 lseek+read/pread 均 EFAULT，只有 mmap 能用**）→ WORD_CLEAN_CHECK 0 →
  nohup 驱动（--ddr-base 0x08000000，绕开硬编码 0x30000000 的
  board_run_m13.sh）+ nohup STATUS 轮询器（2s/ldone，poll_status02.py）双发。
- **结果：发射后 ~2-4 分钟三连 ssh 失败（02:06:06/34/02:07:02）→
  ping 100% 丢失 → COM6 30 秒静默无 panic——与 run01 同一死法**。
  板端两份日志在冻结页缓存里，硬断电后大概率丢失（未 fsync）。
- **决定性结论：DDR 段占用假设死亡**（564 在用 vs 0 在用 → 同样冻结）。
  修正根因排序：①/dev/mem RAM 别名 mmap 的 13MB 写机制本身（run01 冻点
  证据=纯 CPU 写 RAM 阶段、引擎未启动；Device-memory 非对齐 store 在
  A9 UNPREDICTED 可静默挂总线）②HP 互连协议挂死（run02 冻点未证）③
  FCLK0 频率≠60MHz。候选路径（待授权未动）：**A=pynq xlnk/CMA 分配缓冲
  根除 /dev/mem 写 RAM**（推荐）；B=对齐写诊断版；C=JTAG 挂死现场读 PC；
  前置零成本=下次上电查 clk_summary fclk0 + 日志幸存性。
- 存证：4_metrics/logs/2026-09-18_yolo7020_m13_board_run02/
  （README 全时间线+假设修正+现场保留清单、com6/wacher/ping_ssh 三件）。
  规则 3 触发：重试额度用尽，现场保留，未做任何二次操作。

## 待办

1. ~~OOC v28b60 判定（60MHz 出货门）~~ ✅ PASS wns=0.806，已存证
2. ~~M11 FULL 判定 + headcheck~~ ✅（2026-09-18 01:15）
   `TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
   head_bytes=149100 ldone=63 adone=1 bfmerr=0/0 wost=2 xost=2`；
   headcheck sha==9ce70525fc1732cd…aad6 逐字节同冻结；逐层步进表已归档
   （conv_step_times_ms.txt，全帧 sim 855.129ms）
3. ~~build_board.tcl → BOARD_BITSTREAM_PASS + yolo_a2.xsa~~ ✅
   run8 `BOARD_BITSTREAM_PASS wns_ns=0.954`（八跑剥洋葱全记录在
   4_metrics/logs/2026-09-18_yolo7020_board_build_run01/README.md）；
   yolo_a2.bit cde1a4a077bf7830 / xsa 1c75b4ab773c789e 已解出
4. ~~SSH 上板按 deploy_m13.md 部署 + 首帧验证~~ ❌ 两次硬冻结
   （run01 0x30000000 / run02 0x08000000 全空窗口）——占用假设否定，
   剩余待用户决策：A 路 CMA 缓冲改驱动 / B 对齐写诊断 / C JTAG 现场，
   详见 run02 README
5. 批收口：会话日志终稿 + 记忆更新（含 60MHz 决策与板后候选清单）✅ 本节


## 9. run9 批：BD 修正 + 警告消除（2026-09-18 02:2x–，用户 GUI 发现+手工修+授权批处理收口）

用户在 GUI 检查 run8 BD 发现三处问题并手工修正保存：
① DDR/FIXED_IO 未 make external（→ run8 implementation 100 条
"Cannot set property IOSTANDARD" 的根因）② PS 未勾选中断接口（已补
IRQ_F2P 直连 engine/irq_o）③ 质疑 PS→PL 时钟只有 60MHz（=有意
first-light 决策：OOC v28@150 WNS −8.750，v28b60 承证；板后优化另议）。
授权范围：**只修 BD + 消警告 → 更新全部文档（handoff/readme/progress）
→ 关键成果推 git 个人分支**。用户关闭 GUI 后全程批处理。

### 警告三类处治
- **[Constraints 18-1056]**：run8 XDC 手工 create_clock 叠 PS7 自动时钟
  → 删 create_clock（preset 自动生成约束），消。
- **100× IOSTANDARD**：DDR/FIXED_IO 接出后 MIO/DDR 约束有处落地，
  用户 GUI 已修，脚本侧复刻。
- **[BD 41-967]×3**：接口级 CLK_DOMAIN=yolo_sys_ps7_0_FCLK_CLK0 ×3 +
  FREQ_HZ 60M ×3（错误域串 /ps7/FCLK_CLK0 会触发 41-237——自动化
  互连的域才是正串）。run9c 实测 **归零**——"module_ref 不可根除"
  旧结论作废，真因 = FREQ_HZ 缺失的半配置接口（配齐后 Vivado 自行
  推断时钟关联）。

### 失败链与关键突破（详见 4_metrics/.../board_build_run09/README.md）
- run9：按 run8 脚本直跑后用户报告 GUI 修正 → 状态过时，主动 kill。
- run9b：脚本复刻用户修正，`connect_bd_net engine/irq_o ps7/IRQ_F2P`
  报 [BD 41-701]——`get_bd_pins ps7/IRQ_F2P` 恒空（虚引脚不物化）；
  单独 set PCW_IRQ_F2P_INTR=1 得 [BD 41-721] disabled ignored。
- **突破**：write_bd_tcl 导出用户权威 BD（/tmp 相对路径坑→Windows 绝对
  路径）发现官方写法与 run9b 相同，差别在 **ps7 全 533+ 配置（含
  PCW_IRQ_F2P_INTR {1}）在 create_bd_cell 后一次性 set_property -dict
  灌入**（大括号保护 MIO_TREE 值不被二次求值）→ 参数同批激活、引脚
  物化。ps7_ees331.tcl 两遍 foreach 手工路线废弃；导出收编正典
  `board_sys/yolo_sys_bd.tcl`（尾注生成方法+教训），build_board.tcl v2
  改 source 它。
- run9c 首跑：IRQ 坑关闭，但 s_axi FREQ_HZ 被用户 GUI 保存重置回 100M
  （m_axi/x_m_axi 存活）→ 41-237 vs auto_pc 60M。批处理打开用户权威
  工程三连 re-apply FREQ_HZ + validate/save + 重导出 v2 → 重跑。
  **教训：module_ref 接口的 FREQ_HZ/CLK_DOMAIN 在 GUI 任何改动保存后
  都可能丢——每次 GUI 改完 BD，重导出前先三连 re-apply。**

### run9c 第二次（正式，PASS 收口）
```
BOARD_TIMING wns_ns=0.623
BOARD_BITSTREAM_PASS wns_ns=0.623 xsa=.../yolo_a2.xsa
```
**ERROR=0、CRITICAL WARNING 总数=0**——三类警告全清零：
IOSTANDARD 100→0、18-1056 1→0、41-967 3→0。
产物：yolo_a2.xsa adc0a7d1d39b1543 / yolo_sys_wrapper.bit d1f08549ef8a2f44
（与 run8 不同：+DDR/FIXED_IO external、+IRQ_F2P 线、FREQ_HZ 修正；
板上下次加载需重新做 fpga_manager dword 字节交换 .bin）。

### 待办（本批）
1. run9c 完成后：警告计数核对（IOSTANDARD 归零？18-1056 归零？41-967
   存续=已证明良性）+ 时序判决 + 新 yolo_a2.xsa/bit 哈希
2. 文档四件套更新（progress/README/HANDOFF/本日志）✅ 已同步
3. git 推送个人分支（已授权）
