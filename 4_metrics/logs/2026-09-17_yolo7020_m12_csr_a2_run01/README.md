# M12 CSR/engine 门 run01（A2 批首次，2026-09-17）

OOC v28 首跑拦下 xrowgen 双驱动（→V1.3a，M7 run03 回归过）后，
CSR/engine 集成门的 A2 化首跑。TB = tb_yolo_engine_top V1.1。

## 判定

```
TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
                   ldone=6 adone=1 csr=0 xbfmerr=0 xost=2
```

- 前七字段与 B0/v27 csr 门（v24 系）**逐字段一致**（黄金全复用）；
  新增 `xbfmerr=0`（X AXI 读主协议/OOB 干净）、`xost=2`（X 突发队列
  峰值在途 2）。
- A2 化承证内容：① engine_top V1.1 组合 X 口退役 → x_m_axi_* 第二读主；
  ② CSR V1.2 DESC1[19] walk 影子位（写+读回打包，驱动 L0/2/4/5=walk1、
  L1/3=walk0 与 stim/m10 29 字段行一致）；③ VER=0x0002_0000；
  ④ FLDS 28→29。
- AXI-Lite 路径 csr=0（12 影子读写回 + DESC0/DESC1 解码 spot check +
  B resp 全 OKAY）。

## 复现（cwd `sim/msim_a2`）

```
bash run_csr_a2.sh     # vlib work_csr + vlog + vsim -c -novopt +STIM=../stim/m10 +WDT_MS=900000
```

## 哈希（sha256 前 16）

```
6c41c0af77071b11  sim/tb_yolo_engine_top.v  (V1.1)
0b809501e6a1f0d5  rtl/yolo_engine_top.v     (V1.1)
3db91794d48f0a11  rtl/yolo_csr.v            (V1.2)
24dc59f4cfd0cef9  rtl/yolo_gemm_array.v     (V2.0c, 同 M10 run13/M11 run05)
0f14247fece6fb4d  rtl/yolo_xrowgen.v        (V1.3a, M7 run03 回归过)
```

关联：M11 run05（全网，进行中）、OOC v28（P&R，进行中）、
M7 run03（xrowgen V1.3a 回归）。
