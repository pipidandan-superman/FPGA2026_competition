# M10 GEMM 阵列集成门 run13 —— A2 loader V2 批收口取证（V2.0c，2026-09-17）

## 判定

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
                  ldone=6 adone=1 snap=6883 occ2=1607157 ost_w=2 ost_x=2
```

- DUT：`rtl/yolo_gemm_array.v` **V2.0c**（A2 loader V2 三件套 + Fix #9–#12）
  ① W 跨 n_tile 持久（wbuf V3.0）② X 行段流式（yolo_dma V1.4 +
  yolo_xrowgen V1.3 + xbuf V3.0）③ requant 尾 2-slot 重叠。
- TB：`sim/tb_yolo_gemm_array.v` **探针全退役版**（原始首差比对 + 朴素
  心跳复原；488 行调试探针移存 `sim/tb_yolo_gemm_array_dbg24_probes.v`）；
  编译不带 `-d D22_CAP -d D22_ANA`。
- 激励：冻结 `sim/stim/m10/`（清单见下），六层 438447 输出字节逐位对
  金模型（4 静态 conv_core 金核 + R1/R4 预生成 yexp1/yexp2）。
- 复现命令（cwd `sim/xsim`）：
  ```
  F:\vivado2025\2025.2\Vivado\bin\xvlog.bat -log m10_run13_xvlog.log ..\tb_yolo_gemm_array.v ..\..\rtl\yolo_gemm_array.v
  F:\vivado2025\2025.2\Vivado\bin\xelab.bat -debug typical tb_yolo_gemm_array glbl -s m10run13 -L blk_mem_gen_v8_4_12 -L unisim -L unisims_ver -timescale 1ns/1ps -log m10_run13_xelab.log
  F:\vivado2025\2025.2\Vivado\bin\xsim.bat m10run13 -R -log m10_run13_xsim.log
  ```

## 全排空契约的机制签名（Fix #12 生效实证）

| 层 | done 时刻 (ps) | vs 竞态版 (dbg25) | 后移拍数 |
|---|---|---|---|
| L0 | 21606000 | 不变 | 0（末瓦 snap 时段化器仍忙，ywr_idle 本就门住两版）|
| L1 | 16183116000 | 不变 | 0（同上，L1 段化器滞后）|
| L2 | 16585206000 | +140000 | 14 拍 |
| L3 | 16745106000 | +192000 | 19 拍 |
| **L4** | **31195516000** | **+8840000** | **884 拍 = 整条 64 拍末瓦尾排空** |
| L5 | 31928266000 | +1333000 | 133 拍 |

层边界代价 ≈ 末瓦尾排空（L4 最长 ~2.6µs，<0.03% 层时长），换来 PS 侧
LUT 重载的安全序。A2③ 层内双槽重叠不受影响（occ2=1607157 > 0 为 PASS
必要条件）。

## 失败链（本门收口所修的全部根因；详见 7_logs/2026-09-17/06–10）

| 修复 | 症状 | 根因 |
|---|---|---|
| #7 | M10 V2.0 首跑 X loader S_XRUN 挂死 | start 快照只清 pt_vld，未用槽位 X 比对 part 命令解码 |
| #7b | #7 修后 part_cmd_w 全 x | **xsim 常量折叠连续赋值中字面量实参的函数调用**（t=0 求值一次）；内联 wire 表达式 |
| #8/#8b | run8 起 t65 30B 错（幻影命令 421 条）| 末组末单元派发后游标不冻结环绕重派发 + start 快照漏复位 iq_cnt |
| #9 | R1 全层死锁（Y=0 occ=0 ctrl 卡 S_TILE）| xrowgen done_o 残留高电平：P_IDLE 期间不清 em_done_d/p_r → 背靠背 start 采到残留 done |
| #10 | 同上（与 #9 叠加）| loader 无反压：need 按值变化 + beat_en 门 → 覆写 ctrl 未消费的值窗口；修为 presence 判据 + 值跟踪 bank + tag 许可窗 |
| #11 | err 275910（数值大回归）| acc 使能链 4 级 vs V2.0 撤 wrow staging 后乘积 wv+3 到达：en#j 加 p_{j+1}、末拍重复 p26 恰抵消丢的 p26 → 每瓦丢 p0 |
| #12 | err 23（L4 末瓦尾 24 格）| **层边界 LUT 预载竞态（双洞）**：洞 1 = S_TWAIT 首拍采到 snap 前 sh_occ==0（NBA 未落地）首拍即放行；洞 2 = sh_occ 在末拍发射即清而 LUT 读 ~9 拍后才落地 → TB/PS 预载下一层激活表覆写未读条目 |

#12 铁证（dbg24/25/26 三轮）：
- acc-at-drain == acc-at-snap **0/64**（影子槽内容精确，引擎全洗清）；
- 64 拍末瓦尾**全部在 layer_done 之后发射**（首拍 +19ns = 2 拍）；
- 离线提取 lut4/lut5（ddr.hex 基 0x75718/0x80088）：20/23 错格满足
  ∃idx: lut4[idx]==ref ∧ lut5[idx]==dut（同 idx）；余 3"异常格"经
  Δ-型交叉匹配定案为**跨行 y_pre 撞同 idx 的同型交换**（oc61 行
  l5−l4 差值序列与 oc63 行 dut−ref 序列 7/8 逐格相同）——23/23 单一根因；
- 修复后（dbg26/run13）L4 errors=0，三异常格一并愈合。

## 遗留（已定性良性 / 容灾项，不阻门）

- 层边界 BMG collision ×5（READ_FIRST 旧值语义，涉及层数值全对）——
  Fix #10 许可窗外同拍同址，后续批审计窗口内写活动。
- L5 尾冲 `Address 900 (0x900) outside range for B Read` ×8：xren_flush_q
  在 k=2304 下一拍补读越界 1，冲刷拍数据无人消费——整容项（冲刷地址钳位）。
- xsim TB 级 `Delay Control negative` 警告（wdt_ms 溢出 32 位、以二补码
  运行）：ModelSim 侧无此问题；若 xsim 长跑需改 64 位 time 变量。

## 版本与哈希清单

RTL（SHA256 前 16 位）：
```
yolo_gemm_array.v   24DC59F4CFD0CEF9  78975 B   V2.0c（Fix #9–#12 全量）
yolo_xrowgen.v      5AA9487BFB09F2BA  34648 B   V1.3（Fix #8b/#9）
yolo_dma.v          5F99FFD89B0B5EC7  22545 B   V1.4
yolo_wbuf.v         99B545B4E7543810  12799 B   V3.0
yolo_xbuf.v         2A745DB790F8351D  10216 B   V3.0
yolo_ctrl.v         430F3C64D86CB817  23146 B   V2.0
yolo_silu_lut.v     30423C61A4909F41   3229 B   V1.0
tb_yolo_gemm_array.v AFE4B8B27CDEAA8E  68108 B  探针退役版
```
激励 `sim/stim/m10/`（2026-09-17 14:33:44 再生成集；stim_manifest.json
随档）：ddr.hex 5CFD01F872786979（65621 词）/ layers.hex 475D7AF44A24AF03 /
yexp1.hex 75DFEB2CD888729F / yexp2.hex 30C3D606EEC54E79 / gw*.hex+g[bs]*.hex
（金核参数）14 文件。注：stim_sha256_preview.txt 时间戳 2026-09-15 为
陈旧预览，以本清单为准。

## 关联

- 探针版 TB（dbg22–24 全部捕获/分析代码）：`sim/tb_yolo_gemm_array_dbg24_probes.v`
- M7 xrowgen V1.3 回归（同日）：`../2026-09-17_yolo7020_m7_xrowgen_run02/`
  `TB_XROWGEN_PASS tiles=66 bytes=29342 cmds=1887 ars=1889 peak_ost=2`
  ——与 run9 判定行逐字段一致。
- 会话日志：`7_logs/2026-09-17/10_a2_m10_r1_stall_fix9_10.md`
- 数值合同：与 run12（v27/V1.10 基线）同冻结 stim 全对——A2 重构
  数值字节不变义务履行。
