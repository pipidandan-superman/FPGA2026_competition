# M4 xbuf 门 run01 — yolo_xbuf（2026-09-15）

## 结果：TB_XBUF_PASS（CLOSED，首跑过门）

97464/97464 op 逐拍比对二元组（dout_o / dout_vld_o），含保持语义
（黄金输出影子）。RTL V1.0、TB V1.0、生成器一次定稿。**M3 两教训
（黄金 <2^128 断言、交错相读侧深度钳位到前轮 klen）前置固化，
本门首跑即绿。**

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_xbuf.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_xbuf.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/xbuf_vecgen.py`（seed 404） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/xbuf/`（op/bank/col/kaddr/wdata/rbank/rkaddr/edout/evld/n_ops + manifest，10 hex） |
| 本目录 | console_extract.txt / sim_xbuf.log / stim_manifest.json / stim_sha256.txt |

## 合同（基线 §3.3，与 wbuf 行组织对称）

- N_COLS=16 列 × K_MAX=2304 深字节存储器 × 双 bank；读 1 拍同步，
  16 列字节按共享 k 地址广播（dout_o 128b，阵列 X 列广播，与 W 行
  广播配对进乘法墙）；en=0 输出保持；
- 写口 1 拍 1 字节（wcol/waddr/wdata[7:0]），无参数随载（requant
  参数只随 W 行）；
- 双缓冲：写 wr_bank 与读 rd_bank 可同时激活、互不干扰（WRRD 同拍
  写 A 读 B 为隔离证据）；
- 未写地址 RTL 为 x、黄金定义为 0 → 激励不读未写地址。

## 激励设计（r0 真实 + r1..r7 合成，bank = r%2）

| 轮 | K 深 | 内容 |
|---|---|---|
| r0 | 27 | **真实 golden00 im2col X tile**（conv0 几何 3x3/S2/P1，n_start=0 即 ox=0 左缘，pad−128 富集；16 列×27 字节）→ bank0 全量读校验 |
| r1..r7 | 27/576/64/2304/2304/256/48 | 交错相（写 tile_r 至 bank r%2 同时逐拍读校验 tile_{r−1}，每 4 写 1 写与读同拍并发，读深钳位前轮 klen）→ 切换 → tile_r 全量校验 + 保持拍 |

**真实数据双路闭合**：黄金提取用地址算术路径（im2col_byte，K 序
ic·9+kh·3+kw、ih=oy·2+kh−1）；生成器内以 np.pad+窗口切片第二路径
逐字节断言一致（pad 值 −128）——非单实现自证。

覆盖统计：97464 op（数据读 7752 / 同拍写读 3412 / 保持拍 16），
生成器内部断言：读≥5000、同拍并发≥200、两 bank 2304 全深校验、
黄金值全部 <2^128、真实双路闭合。

## 环境与复现

- ModelSim SE-64 10.1c（vsim 必须 `-c -novopt`；MGLS_LICENSE_FILE=
  D:/work/modelsim/win64/LICENSE.TXT）；
- 复现：`python xbuf_vecgen.py` → `vlog -work work ../../rtl/yolo_xbuf.v
  ../tb_yolo_xbuf.v` → `vsim -c -novopt +STIM=../stim/xbuf +WDT_MS=1000
  -do "run -all; quit -f" work.tb_yolo_xbuf`（sim/msim 下）。

## 结论

M4 门通过。M10 集成注意：X tile 装载字节序 = im2col（列 n_local、
行 k），与 M7 addrgen 地址流一致——M9 X-DMA 按 addrgen beat 顺序回填
本缓冲（pad beat 由 pad_val_o 旁路供给，不读 DDR）；ctrl 在 tile 边界
切换 wr_bank/rd_bank（与 wbuf 同拍切换）。
