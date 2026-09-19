# M7 xrowgen 门 run01（V1.2，2026-09-17）

## 判决

**TB_XROWGEN_PASS tiles=66 bytes=29342 cmds=1887 ars=1889 peak_ost=2**
（真实 xbuf + xram BFM + set-equal 读回比对；66/66 tile 位级一致）

- DUT：`rtl/yolo_xrowgen.v` **V1.2**（N_COLS=16, SEG_W=6, P_MAX=4, XAW=12）
- TB：`sim/tb_yolo_xrowgen.v`（含 run3 期定界探针：[cmd] 首 24 条、
  [beat] 首 40 拍、m7_cmd_trace.txt 全量命令表——有界，属门格式）
- 激励：`sim/stim/xrowgen/`（stim_manifest.json 随档）；
  66 tile = 52 真实几何（320²/30²/20²/…）+ 14 角case（t53–t65：
  多段/尾段/1×1/越界/kh1kw3/kh3kw1 等）

## 本门收口的失败链（详 7_logs/2026-09-17/06 与 09）

| 修复 | 症状 | 根因 |
|---|---|---|
| #7 | M10 V2.0 首跑 X loader S_XRUN 挂死 | start 快照只清 pt_vld，未用槽位 X 毒化 part 命令解码 |
| #7b | #7 后 part_cmd_w 仍 xxxx | **xsim 常量折叠连续赋值中字面量实参的函数调用**（t=0 求值一次）；内联为 wire 表达式 |
| #8 | run8 仅 t65 30B 错（k3 行含 k2 黄金字节） | 末组末段派发后游标不冻结 → 段环回绕、幻影重派发至 IQ 满 |
| #8b | 同上（跨 tile 触发） | start 快照未清 iq_cnt → 下一 tile 弹陈旧表项（提前置 grp_ready / 覆写 slot_mem） |

单 tile 复现 stim：`sim/stim/xr65/`（t65 独立跑 PASS，23→16 条命令证明幻影消除）。

## 命令表核对

t65 手工推导 16 条合法命令（平面基址 = xbase；kh2 的 P2 行 6≥ih 零 DMA）
与 trace 前 16 条逐条一致；run9 全量 1887 条 = 各 tile 合法命令总和
（run8 的 2308 含 421 条幻影）。

## 复现命令

```
cd E:\competition\2_fpga\3_yolo_zynq\sim\xsim
F:\vivado2025\2025.2\Vivado\bin\xvlog.bat ..\rtl\yolo_xrowgen.v ..\sim\tb_yolo_xrowgen.v -log m7x19_xvlog.log
F:\vivado2025\2025.2\Vivado\bin\xelab.bat -debug typical tb_yolo_xrowgen glbl -s m7x19 -L blk_mem_gen_v8_4_12 -L unisim -L unisims_ver -timescale 1ns/1ps -log m7x19_xelab.log
F:\vivado2025\2025.2\Vivado\bin\xsim.bat m7x19 -R -log m7_run9.log
```
