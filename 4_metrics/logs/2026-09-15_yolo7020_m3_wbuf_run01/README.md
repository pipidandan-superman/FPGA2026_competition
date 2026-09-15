# M3 wbuf 门 run01 — yolo_wbuf（2026-09-15）

## 结果：TB_WBUF_PASS（CLOSED，3 跑过门）

98239/98239 op 逐拍比对四元组（dout_o / dout_vld_o / pdata_o /
pdata_vld_o），含保持语义（黄金输出影子）。**RTL V1.0 三跑全程零
改动**——run1/run2 两处失败均为激励/黄金侧缺陷。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_wbuf.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_wbuf.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/wbuf_vecgen.py`（seed 303） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/wbuf/`（op/bank/row/kaddr/sel/wdata/rbank/rkaddr/edout/evld/epdata/epvld/n_ops + manifest，13 hex） |
| 本目录 | console_extract.txt / sim_wbuf.log（过门原始日志）/ sim_wbuf_run1_goldenbug.log（run1 失败原始日志）/ stim_manifest.json / stim_sha256.txt |

## 合同（基线 §3.3）

- N_ROWS=16 行 × K_MAX=2304 深字节存储器 × 双 bank；数据读 1 拍同步，
  16 行字节按 k 地址广播（dout_o 128b）；en=0 输出保持；
- 写口 1 拍 1 项，wr_sel：0=data 字节（wdata[7:0]→mem[wrow][waddr]）/
  1=bias_eff / 2=m / 3=shift（参数与 tile 同装，32b/8b）；
- 参数口 pren/(psel,prow) → 1 拍延迟 32b（shift 高位补 0）；
- 双缓冲：写 wr_bank 与读 rd_bank 可同时激活、互不干扰（WRRD
  同拍写 A 读 B 为隔离证据）；
- 未写地址 RTL 为 x、黄金定义为 0 → **激励不得读未写地址**。

## 激励设计（r0 真实 + r1..r7 合成，bank = r%2）

| 轮 | K 深 | 内容 |
|---|---|---|
| r0 | 27 | **真实 golden00 W tile**（16×27 字节 + 真实 bias/m/shift）→ bank0，全量读校验 + 参数扫 |
| r1..r7 | 576/64/2304/2304/256/48 | 参数装载 → 交错相（写 tile_r 至 bank r%2 同时逐拍读校验 tile_{r−1}，每 4 写 1 写与读同拍并发）→ 切换 → tile_r 全量校验 + 参数扫 + 保持拍 |

K 档覆盖两 bank 各一次 2304 全深度。覆盖统计：98239 op
（数据读 7752 / 参数读 384 = 3 字段×128 / 同拍写读 3412 / 保持拍 23），
生成器内部断言：读≥5000、每参数字段≥100、同拍并发≥200、两 bank
2304 全深校验、**黄金值全部 <2^128**（run1 教训固化为断言）。

## 过程记录（run1 → run2 → run3）

- **run1 全红（黄金键空间冲突）**：Model 把参数存 `banks[(row, sel)]`，
  sel∈{1,2,3} 与数据键 `(row, k)` 的 k=1/2/3 同空间——r0 参数写覆盖
  数据字节，rd() 把 32b 参数按 `<<8r` 拼进黄金值 → edout_i128.hex
  出现 36/38 位十六进制（144/151 bit），vsim `vsim-PLI-3406 Too many
  digits`，$readmemh 跳行后 mem_ed 为 x，`TB_WBUF_FAIL errors=96724
  first_op=481`。修复：参数独立 `pars` 字典 + 生成期断言
  `0 ≤ ed < 2^128`。原始失败日志：sim_wbuf_run1_goldenbug.log。
- **run2 首错后移 op=1264（激励读越界）**：`dout=x(exp 0)`——r1 交错
  相读侧循环条件误用**当前轮** klen=576，读到 tile_r0（27 深）未写
  地址（RTL x vs 黄金 0）。修复：读侧深度钳位到前轮 klen
  （rd_len=prev['klen']）。run2 原始日志被 run3 同路径覆盖，失败行
  存于 console_extract.txt；RTL/TB 均无改动。
- **run3 全绿**：TB_WBUF_PASS（原始日志 sim_wbuf.log）。
- 另：run1 前有两次 vsim 启动瞬断（GUIMAIN fatal），重跑自愈——
  10.1c 已知瞬态，以 M2 已绿设计复跑确认非库损坏。

## 环境与复现

- ModelSim SE-64 10.1c（vsim 必须 `-c -novopt`；MGLS_LICENSE_FILE=
  D:/work/modelsim/win64/LICENSE.TXT）；
- 复现：`python wbuf_vecgen.py` → `vlog -work work ../../rtl/yolo_wbuf.v
  ../tb_yolo_wbuf.v` → `vsim -c -novopt +STIM=../stim/wbuf +WDT_MS=1000
  -do "run -all; quit -f" work.tb_yolo_wbuf`（sim/msim 下）。

## 结论

M3 门通过。M10 集成注意：DMA 写 wbuf 须在 tile 边界前完成参数四件
（data/bias/m/shift）装载；ctrl 切换 wr_bank/rd_bank 时机 = tile
边界（本门以交错相 + 同拍写读证明两 bank 互不干扰）。
