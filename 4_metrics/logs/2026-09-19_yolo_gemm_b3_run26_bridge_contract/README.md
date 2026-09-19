# run26 证据 README —— B3 桥合同仿真门 + canonical packer + 静态 CSR 检查（收官）

run：`2026-09-19_yolo_gemm_b3_run26_bridge_contract`　收官：2026-09-20 凌晨
基点合同：`1_docs/yolo_b3_dma_gemm_contract_20260919.md` v1.1（SHA-256
`b27a4a64527a692b03a065648533161bee4ed2cb8ed7039d533357abdf696234`）
对象 RTL：`rtl/GEMM/yolo_gemm_top.v` **V1.2**（五项修复 R1-R5）
TB：`rtl/GEMM/tb/tb_yolo_gemm_b3_bridge.sv`（S1-S7 + 四变体负向 + §11 恢复）

## 判定

**run26 = PASS**（合同 §14 run26 门：合同符合性 + packer + 桥 RTL + 静态 CSR
检查全闭环）：

- 仿真终证 `build_log6.txt`：
  `EES_SUMMARY checks=1664 rb_checks=1152 sc_checks=1280 errors=0 PASS`，
  零 collision WARNING，12×`pop_tlast`；
- packer 终证 `packer_run.txt`：`B3_CONV0_PACKER PASS`，golden y 与 G0
  软件金张量逐位一致；
- 静态 CSR/地址检查 `csr_static_check.md`：§9 全 23 行 PASS + §5 常量互证。

## 一、桥 RTL 五项修复（V1.1→V1.2，逐项仿真闭环）

| # | 修复 | 位置 | 验证 |
|---|---|---|---|
| R1 | y-cap 调试读口 TDP 同址冲突结构规避：YADDR 写后开 2 拍读窗（enb 不再常开） | top.v 795-806 | build_log6 零 collision WARNING |
| R2 | 流窗内 WCTL 写：丢弃 + `src_conflict`(BRGSTAT b3) + `ld_pend_err`(STATUS b8) 双位置位（D4） | top.v 516-520 | S5b 正控制+err_clr |
| R3 | TLAST watchdog：accepted beat 计满 3072（K=1024 上限×3 拍交错）无 tlast → `tlast_err`；短流缺失由 BFM/BTT 判（硬件不可检，合同 §12.2 裁定） | 桥计数块 | S6d 置位且块不闭口 |
| R4 | 外部 rst 清全部配置寄存器（§9 实现要求） | top.v 387-400 | 静态证明 + S5a/§11 |
| R5 | **y 流 tlast 真实缺陷修复**（详见下节） | top.v 呈现逻辑+FIFO 块 | build_log5/6，12×pop_tlast |

### R5 tlast 缺陷：发现-定位-修复全链（run26 最重要发现）

- **暴露**：build_log3 终局守恒错 `stream ends mid-tile 128B`（S1-S7 各段绿
  但终局 sc_bytes_tile=128）。S1-S6 的 tlast 检查空真——128B 检查只在
  `if (m_axis_y_tlast)` 内跑，tlast 从不弹出 ⟹ 检查体从不执行。
- **定位**：加 `EES_TL` 诊断监视器（build_log4）：13 个 tile 的
  `core_tile_done` 全部落在末 y 拍后 ≥2 拍、`wv_d=wv_r=wtl_r=0、ypk_cnt=0`
  ——V1.1 的两个并入窗（同拍 `ypk_wtl_r` / 晚一拍 `yfifo_pushtl` 第二项）
  **结构性漏标**，全 sim 零 tlast。
- **修复=三路合并**：①原两路保留；②呈现拍恰逢脉冲 `core_tile_done_w &&
  yfifo_cnt==1` 组合并入（无 NBA 竞态）；③位置捕获 `tl_late_pos` 回补
  （迟到标记落位；覆盖前旧标记回写 `yfifo_tl[tl_late_pos]`——v 未清 ⟹
  旧标记字必仍在队内，连续多 tile 迟到标记全部落位，单寄存器不再丢标）。
- **验证**：build_log5 全绿 11×pop_tlast；迁移加固后 build_log6 全绿
  12×pop_tlast（多 1 次=排水段迁移标记）。

## 二、S1-S7 场景与四变体（build_log6 终证）

S1 槽回归 128 checks；S2 流单块（ld_done/LDLEN 对账）；S3 双组重叠
STALLCNT delta==0；S4 同组重载 STALLCNT=62+读清回 0；S5a/S5b 双源冲突
（R2 双位+err_clr）；S6a TLAST 提前 / S6b 延后 / S6c 缺失（短流，BFM 判）
/ S6d 超长 R3 watchdog；S7 y 溢出 + §11 七步正典恢复（排空→对账清零→
err_clr→soft_rst→LDSTAT 正控制 loaded==00→重装载+LDSTAT 确认→重启复核）。

**§11 恢复正典（驱动合同级）**：soft_rst 清 bank w_loaded/x_loaded
（bank.sv:155 经 core_rst）→ 恢复必须**重装载 W/X 并由 LDSTAT 确认**后才能
再递交 job，否则 feeder 死等、STATUS 全 0 静默。

## 三、canonical packer（`pynq/b3_conv0_packer.py`，B-① 纪律）

数据链全权威源：weights/bias/lut 按 quant.json 偏移（b_off 为**字节**偏移
→int32 元素 `//4`）、M/shift=schedule.json task0 `req`、z_sum_w 加 b_q、
canvas=G2 run04 golden_index frame0 `canvas_u8`（HWC→CHW u−128）、数学=
gemm_golden_replay.py 逐行（im2col k=ic*9+kh*3+kw、b_q+z_sum_w、
sat_i8(rne_shift((acc+b_q)·M,s))、lut[out+128]）。

产物（本目录）：

| 文件 | 内容 | SHA-256 |
|---|---|---|
| `b3_conv0_mirror.bin` | 0x25F000=2,486,272B 物理镜像（LUT 256B + 3200×648B 三拍交错 + y 区 0xA5 + guard 0xA5） | `be4d56f067b91d0227312d164edb6ee802ebc212ad7b27d83d58aa540e63832f` |
| `b3_conv0_golden_y.bin` | [16][160][160] int8 G0 路径金张量 | `eeb15bf9b53950816cde51d063336aa79fb5ad41e9bf1f3b01b6357f442f6bbe` |
| `b3_conv0_meta.json` | PCTL 参数（per g,r: b_eff/M/shift）+ 常量（MM2S 2,073,600B / S2MM 409,600B / accepted beats 259,200） | — |
| `b3_conv0_selfcheck.json` | 机器可读自检报告（§6 全项） | — |
| `b3_conv0_block0.hex` | 首块 648B 十六进制转储（审计） | — |

自检（§6）：四边界块 SHA、W/X 三拍计数 27/27/27、全块 648B、SAR 步进 648、
SAR/DST 全 8B 对齐、§4.3 边界审计（**pad 字节 5754=打包计数=独立复审=闭式
推导** 顶 2880+左 2880−角 6）、y 区/guard 0xA5、golden y **与 G0
`int8_model.0` 逐位一致**（独立路径复算 = packer 数学最强证明）。
抽检：tile0 X lo 全 0x80（顶行 pad）、tile1590_g0 X lo 恰 c=0 为 0x80（左列
pad）、W beat 同 tile 跨 g 不同 / X 跨 g 相同、b_eff 全落 32b 有符号域。

## 四、静态 CSR/地址检查（`csr_static_check.md`）

§9 全 23 行逐项 PASS（含 ID/STATUS/LDSTAT/BRGSTAT 位序逐位对照、P_BIAS/P_M
signed 声明）；复位三分规则（rst 全清 387-400 / soft 只清运行态 / err_clr
只清五错误位）；§5 常量与 packer 互证。三条注记（B-①②③）：PCTL bit8 实现
宽松侧等价；**LDLEN 0x40 桥模式只读镜像（run29 驱动不得写）**；未映射/RO
写 → SLVERR（457 行注释失准，行为 fail-closed 保留）。

## 五、日志轮次

- `build_log.txt/2`：早期轮（S1-S4 绿、S7 恢复超时→探针定位 soft_rst 清
  loaded 语义）；
- `build_log3`：V1.2 前加固轮——终局守恒错暴露 tlast 空真；
- `build_log4`：诊断轮（EES_TL 监视器，13×tile_done 时序取证，0×pop_tlast）；
- `build_log5`：R5 后全绿（11×pop_tlast）；
- `build_log6`：迁移加固终版（**判定依据**，errors=0 PASS）；
- `packer_run.txt`：packer 终证。

失败证据均未覆盖（build_log3/4 保留）。

## 六、后续

run27 G4（全量 3200 块 golden 逐字节 + 随机反压 + 4KiB crossing + 双跑
SHA）→ run28 BD 重连+bitstream/HWH+静态端口检索 → **run28 收口即停**；
任何板卡动作等用户"已上电"确认。
