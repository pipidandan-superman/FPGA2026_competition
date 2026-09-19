# M7 xrowgen 回归 run02（V1.3，2026-09-17）

A2 loader V2 批 M10 收口（gemm_array V2.0c Fix #12）后的 xrowgen 回归。

## 判定

```
TB_XROWGEN_PASS tiles=66 bytes=29342 cmds=1887 ars=1889 peak_ost=2
```

与 run01/run9 判定行**逐字段一致**（同 stim、同 RTL V1.3）——无回归。

## 复现命令（cwd `sim/xsim`）

```
F:\vivado2025\2025.2\Vivado\bin\xvlog.bat -log m7x20_xvlog.log ..\tb_yolo_xrowgen.v ..\..\rtl\yolo_xrowgen.v
F:\vivado2025\2025.2\Vivado\bin\xelab.bat -debug typical tb_yolo_xrowgen glbl -s m7x20 -L blk_mem_gen_v8_4_12 -L unisim -L unisims_ver -timescale 1ns/1ps -log m7x20_xelab.log
F:\vivado2025\2025.2\Vivado\bin\xsim.bat m7x20 -R -log m7_run10.log
```

DUT 哈希：yolo_xrowgen.v 5AA9487BFB09F2BA（34648 B，V1.3）。
关联：`../2026-09-17_yolo7020_m10_gemm_array_run13/README.md`。
