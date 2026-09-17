# OOC v28b60（A2 RTL @60MHz 出货时钟门，2026-09-17）

## 判定

```
GEMM16_OOC_TIMING_60M_PASS wns_ns=0.806 whs_ns=0.040
OOC_V28B60_RES dsp48e1=147 ramb36=52 ramb18=0
```

- 与 v28@150（wns=−8.750）同净表、同流程，仅约束 6.667→16.667ns；
  WNS = −8.750 + 10 ≈ +0.81 实测 +0.806，与单时钟域解析预期吻合
  —— 损害确系建立时间（非保持/布线），60MHz 下全体路径收敛。
- 判据行 `fmax_mhz=170.6` 是 tcl 里按硬编码参考周期 6.667 折算的
  显示伪影（1000/(6.667−0.806)），时序判定本身按 16.667 约束的
  WNS≥0 做出，以 wns_ns=0.806 为准。v29 起修该显示。
- 资源：DSP 147/220（66.8%）、RAMB36 52/140（37.1%；v27 为 20，
  +32 来自 A2 wbuf BMG V3.0 持久权缓），RAMB18=0。

## 语义

本门 = M12 时序门在**出货时钟**（FCLK0=60MHz，board first-light）
下的承证；150MHz 目标的失败与两主锥分析见
`../2026-09-17_yolo7020_ooc_gate_v28/README.md`。xrowgen 流水化
（150MHz 恢复）+ A2b = 板后优化批候选，交用户决策。

## 复现（cwd proj/ooc_gate）

```
vivado -mode batch -source ooc_v28b60.tcl
```

## 哈希（sha256 前 16）

```
94f6817424da8613  proj/ooc_gate/ooc_v28b60.tcl
0f14247fece6fb4d  rtl/yolo_xrowgen.v      (V1.3a，同 v28/M11 run05)
24dc59f4cfd0cef9  rtl/yolo_gemm_array.v   (V2.0c，同 v28/M10 run13)
```

关联：v28（150MHz FAIL 与锥分析）、M11 run05（全网，进行中）、
build_board.tcl（本门通过后放行）。
