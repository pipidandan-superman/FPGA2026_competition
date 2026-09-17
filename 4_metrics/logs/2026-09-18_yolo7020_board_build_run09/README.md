# run09 批：BD 修正 + 警告消除（2026-09-18）

用户 GUI 检查发现 run8 BD 三处问题（DDR/FIXED_IO 未 make external、PS 未勾选 IRQ_F2P、
对 60MHz 提出疑问）并手工修正保存；随后授权本批：**只修 BD + 消警告，更新全部文档，
关键成果推 git 个人分支**。用户关闭 Vivado GUI 后全程批处理。

## 警告分类与处治（三类）

| 警告 | 数量(run8) | 根因 | 处治 | 结果 |
|---|---|---|---|---|
| [BD 41-967] AXI interface not associated to any clock pin | 3 | **真因=FREQ_HZ 缺失的半配置接口**（旧结论"module_ref 不可根除/ASSOCIATED_BUSIF 不存在"作废——配齐 FREQ_HZ×3 后 Vivado 自行推断时钟关联） | 三连 re-apply FREQ_HZ=60M ×3 + CLK_DOMAIN=yolo_sys_ps7_0_FCLK_CLK0 ×3 → 重导出 v2 | **0（归零）** |
| [Constraints 18-1056] FCLK0 completely overrides ps7/FCLK_CLK0 | 1 | 手工 create_clock 叠在 PS7 自动时钟上 | `yolo_sys.xdc` 删除 create_clock（PS7 preset 自动生成约束） | 消除 |
| Netlist "Cannot set property IOSTANDARD on pin" | 100 | DDR/FIXED_IO 未接出 → MIO/DDR 约束无处落地砸 cell pin | 用户 GUI make external + 脚本显式 `create_bd_intf_port` 复刻 | **0（归零）** |

## 失败链

### run9（中止，run9_vivado.log）
按 run8 脚本 + 后缀工程直跑；用户随即报告 GUI 修正（IRQ/external），脚本状态已过时 →
主动 kill，保留 log 供对照。

### run9b（失败，run9b_vivado.log）
在脚本中复刻用户修正：DDR/FIXED_IO 显式接出 + `PCW_IRQ_F2P_INTR=1` +
`connect_bd_net engine/irq_o ps7/IRQ_F2P`。
**失败**：`[BD 41-701] connect_bd_net requires at least two pins` ——
`get_bd_pins ps7/IRQ_F2P` 为空。事后单独 set `PCW_IRQ_F2P_INTR=1` 得
`[BD 41-721] disabled parameter ignored`（即便全量 preset + validate 后引脚也不物化）。

### 关键突破：write_bd_tcl 导出用户权威 BD（yolo_sys_export.tcl / _v2.tcl）
官方语法与 run9b 相同的 `connect_bd_net ... [get_bd_pins ps7/IRQ_F2P]`，差别在
**ps7 全部 533+ 配置（含 `PCW_IRQ_F2P_INTR {1}`）在 `create_bd_cell` 后一次性
`set_property -dict` 灌入**——大括号保护的值天然避免 MIO_TREE 二次求值坑，参数同批
激活后 IRQ_F2P 引脚物化。结论：ps7_ees331.tcl 两遍 foreach 手工拼装路线废弃，
导出脚本收编为正典 `proj/board_sys/yolo_sys_bd.tcl`（尾部有生成方法与教训说明），
`build_board.tcl` v2 改为 source 它。

### run9c 第一次（失败，被 run9c_vivado.log 覆盖前的事实记录于此）
IRQ 坑关闭（无 41-701/41-721），但暴露回归：`[BD 41-237] FREQ_HZ mismatch
/engine/s_axi(100000000) vs auto_pc/M_AXI(60000000)` —— 导出脚本里 s_axi 只带
CLK_DOMAIN 不带 FREQ_HZ，即**用户 GUI 保存把 s_axi 的 FREQ_HZ 重置回默认 100M**
（m_axi/x_m_axi 存活）。教训：module_ref 接口的 FREQ_HZ/CLK_DOMAIN 在 GUI 任何
改动保存后都可能丢。
修复：批处理打开用户权威工程三连 re-apply FREQ_HZ=60M（fix_bd.tcl，validate+save
无错误）→ 重新导出 v2（三接口 FREQ_HZ 齐全）→ 重跑。

### run9c 第二次（正式，run9c_vivado.log）
BD 段全绿（validate 无错、IRQ 线接通、FREQ_HZ×3 齐全）→ synth/impl/bitstream 全程
**ERROR=0、CRITICAL WARNING=0**（三类警告全清零）：

```
BOARD_TIMING wns_ns=0.623
BOARD_BITSTREAM_PASS wns_ns=0.623 xsa=E:/competition/2_fpga/3_yolo_zynq/proj/board_sys/yolo_a2.xsa
```

警告计数核对（run8 → run9c）：IOSTANDARD 100→**0**；18-1056 1→**0**；
41-967 3→**0**；41-237/41-701/41-721 全程 0。

## 交付物

| 文件 | sha256（前16位） | 说明 |
|---|---|---|
| `proj/board_sys/yolo_a2.xsa` | adc0a7d1d39b1543 | 含 bit + .hwh（替代 run8 的 1c75b4ab…） |
| `yolo_a2_board_9c/.../yolo_sys_wrapper.bit` | d1f08549ef8a2f44 | run9c 位流 |
| `proj/board_sys/yolo_sys_bd.tcl` | — | **正典 BD 重建脚本**（write_bd_tcl v2 导出 + 尾注生成方法/教训） |
| `proj/board_sys/build_board.tcl` | — | v2：source yolo_sys_bd.tcl（手工拼装退役） |
| `proj/board_sys/yolo_sys.xdc` | — | 无 create_clock（PS7 preset 自动约束） |
| `proj/board_sys/yolo_a2_board/yolo_sys.bd` | — | 用户 GUI 权威 BD（FREQ_HZ 已批处理 re-apply） |

注意：位流/XSA 与 run8 哈希不同（BD 变更：+DDR/FIXED_IO external、+IRQ_F2P 线、
FREQ_HZ 修正）；**板上下次加载需用新 .bin 转换**（fpga_manager dword 字节交换，
mk_bin_m13.tcl / yolo_a2_fpgamgr.bin 流程不变）。

## 关键结论

1. **IRQ_F2P 物化机制**：ps7 全配置一次性 `set_property -dict` 灌入（含
   PCW_IRQ_F2P_INTR {1}）→ 引脚物化；事后单独 set = 41-721 disabled ignored。
2. **GUI 保存丢 module_ref 接口属性**：s_axi FREQ_HZ 被重置回 100M → 41-237；
   规矩=GUI 改完 BD 重导出前先三连 re-apply。
3. **41-967 真因**：FREQ_HZ 缺失半配置接口，非 module_ref 工具限制——配齐即归零。
4. **write_bd_tcl 的 /tmp 路径**在 Windows 被当相对路径（相对 Vivado cwd），
   必须 Windows 绝对路径。

