# M13 板端驱动 PC 自测 run01（2026-09-17）

## 判定

```
PL_M11_PASS convs=63 psops=65 compared=3553900 nerr=0
            head_bytes=149100 head_sha256=9ce70525fc1732cd...
```

驱动 pynq/pl_m11.py（/dev/mem 固定地址 0x43C1_0000 CSR + DDR
carve-out + prog.hex/lut_all.hex/ddr.hex 执行器）在 PC 上以
FakePL（黄金 im2col GEMM，stim 自带 W/X/bias/M/S/LUT 重算）全流程
跑通：解释器步进（FLDS=28）、DESC 打包、LUT 窗口预载、PS 五算子
（intarith 原语逐位 = TB t_*）、DDR↔镜像同步合同、heads 转储、
sha256 终判 —— 与 ModelSim 同一判据链闭环。**板端剩余未知仅：
比特流加载、GP0/HP0/HP1 实流、DDR 一致性。**

## 自测中发现并钉死的合同事实（防再踩）

- **prog.hex conv 行 = 28 token（FLDS=28）**，写 29 会步进错位后撞
  0 词静默提前 END（engine TB 的 layers.hex 才是 29 字段，walk@28
  —— 两格式不同源，勿混）。
- **W 行距 = ceil(K/8)×8**（m11_vecgen `kpad`），且 W/b/M/S 区均按
  oc_tiles×8 行/条目分配（oc=7 → 8 行，oc 后是 PRNG 垫料/零，从不
  读）。conv0 区距 512=16×32 曾误导出"32B 对齐"假规则，实为 16 行
  ×kpad32；数据扫描 63 层 + 源码核对后钉死。
- tok22 = conv_ord（同时是 LUT 段索引，两者天然一致）。
- bias 字 = bias_eff（first 层 z_sum_w 已并入，m11_vecgen 证实），
  板端直接加，勿再补 z 项。

## 复现（cwd pynq）

```
python pl_m11.py --mkbin --stim ../sim/stim/m11    # 产 .bin 三件
python pl_m11_selftest.py --stim ../sim/stim/m11   # 本判定
```

## 哈希（sha256 前 16）

```
f67f0c5efafdd8f5  pynq/pl_m11.py
05eebb18064e5e91  pynq/pl_m11_selftest.py
3e29738cd56b6550  sim/stim/m11/ddr.bin     (13,320,008 B)
ccb9662b22133471  sim/stim/m11/lut_all.bin (16,128 B)
88e9f6105110b5db  sim/stim/m11/prog.bin    (8,712 B = 2178 词)
```

关联：M11 run05（同一程序的仿真侧）、deploy_m13.md（上板手册）。
