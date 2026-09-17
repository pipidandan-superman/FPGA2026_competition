# M7 xrowgen 回归 run03（V1.3a，2026-09-17）

OOC v28 首跑综合拦下 `iq_cnt_r` 双 always 驱动（Synth 8-6859 ×8，
xrowgen.v:220/706 两处 start 快照复位同条件同值）后的综合合法性修复回归。

## 判定

```
TB_XROWGEN_PASS tiles=66 bytes=29342 cmds=1887 ars=1889 peak_ost=2 (real xbuf, xram BFM, set-equal readback)
```

与 run01/run02/run9（V1.3）判定行**逐字段一致** —— V1.3a（删除快照块
冗余赋值，唯一写者 = 占用率块）仿真逐位等价实证。

## 修复说明

- 两个 always 块在同一 `start_i && P_IDLE` 边沿各赋 `iq_cnt_r <= 4'd0`
  （#8b 加在主时序块、占用率块自带同款复位）。NBA 同拍同值 → 仿真
  终值恒同、逐位等价；综合则报多驱动。删除主时序块副本即合法。
- M11 run05 全网跑不受影响（work_a2 库内编译的仍是 V1.3，且本修复
  仿真等价）；M11 证据哈希表已注明 V1.3，本次为 V1.3a（见下）。

## 复现（cwd `sim/xsim`）

```
F:\vivado2025\2025.2\Vivado\bin\xvlog.bat -log m7r3_xvlog.log ..\tb_yolo_xrowgen.v ..\..\rtl\yolo_xrowgen.v
F:\vivado2025\2025.2\Vivado\bin\xelab.bat -debug typical tb_yolo_xrowgen glbl -s m7r3 -L blk_mem_gen_v8_4_12 -L unisim -L unisims_ver -timescale 1ns/1ps -log m7r3_xelab.log
F:\vivado2025\2025.2\Vivado\bin\xsim.bat m7r3 -R -log m7_run11.log
```

DUT 哈希：yolo_xrowgen.v 0f14247fece6fb4d（V1.3a）；
TB 哈希：tb_yolo_xrowgen.v 63610314ca3ad081。
关联：`../2026-09-17_yolo7020_m7_xrowgen_run02/`（V1.3 基线）。
