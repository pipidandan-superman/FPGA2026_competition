# 2026-09-20 验证总结（run26 收官）

## 开始前已验证事实（承袭 2026-09-19）

- 桥 RTL V1.2（R1-R5）+ TB 三处修复后 xsim S1-S7 全绿：
  `build_log6.txt` EES_SUMMARY checks=1664 rb_checks=1152 sc_checks=1280
  errors=0 PASS、零 collision WARNING、12×pop_tlast；
- R5 tlast 缺陷链：build_log3 守恒错暴露 → build_log4 EES_TL 取证
  （13×tile_done 全部 ≥2 拍后、0×pop_tlast）→ 三路合并修复 → build_log5/6
  全绿。

## 本日新验证（run26 收口三件）

### 1. canonical packer（B3_CONV0_PACKER PASS）

- 脚本：`2_fpga/3_yolo_zynq/pynq/b3_conv0_packer.py`（env python 运行，
  运行证 `packer_run.txt`）；
- **mirror** `b3_conv0_mirror.bin` 2,486,272B：
  SHA-256 `be4d56f067b91d0227312d164edb6ee802ebc212ad7b27d83d58aa540e63832f`；
- **golden_y** `b3_conv0_golden_y.bin` 409,600B：
  SHA-256 `eeb15bf9b53950816cde51d063336aa79fb5ad41e9bf1f3b01b6357f442f6bbe`，
  **与 G2 golden `int8_model.0` 逐位一致（golden_y_vs_g0=OK）**——独立路径
  复算，packer 数学最强证明；
- 自检 `b3_conv0_selfcheck.json`：四边界块 SHA（b0=775d1d12…）、W/X 三拍
  27/27/27、全块 648B、SAR 步进 648、SAR/DST 8B 对齐、y 区+guard 0xA5、
  **pad=5754=打包=独立复审=闭式（顶 2880+左 2880−角 6）**；
- meta `b3_conv0_meta.json`：PCTL per (g,r) b_eff/M/shift（16 组）、常量
  （MM2S 2,073,600B / S2MM 409,600B / accepted beats 259,200 / LUT sha
  a28c3499…）。

### 2. 静态 CSR/地址检查 PASS

`4_metrics/logs/2026-09-19_yolo_gemm_b3_run26_bridge_contract/csr_static_check.md`：
§9 全 23 行逐项（ID/STATUS/LDSTAT/BRGSTAT 位序逐位、P_BIAS/P_M signed）；
复位三分规则；§5 常量互证。三条注记：PCTL bit8 宽松侧等价；**LDLEN 0x40
桥模式只读镜像（run29 驱动不得写）**；RO/未映射写→SLVERR。

### 3. run26 门判定

**run26 = PASS**（合同 §14：合同符合性 + packer + 桥 RTL + 静态 CSR 检查）。
证据：`4_metrics/logs/2026-09-19_yolo_gemm_b3_run26_bridge_contract/README.md`。

## 通过标准对照

| 合同 §14 run26 要求 | 证据 | 判定 |
|---|---|---|
| S1-S7 全绿（含负向四变体+§11 恢复） | build_log6 errors=0 | PASS |
| canonical packer + §6 自检 | packer_run.txt + selfcheck.json | PASS |
| 静态 CSR/地址检查 | csr_static_check.md | PASS |
| 失败证据不覆盖 | build_log3/4 保留 | PASS |

## 尚未验证

- run27 G4（全量 3200 块+随机反压+4KiB+双跑 SHA）——进行中；
- run28 BD/XCI/bit/HWH/静态端口检索、WNS/WHS、资源口径——待做；
- 一切板级验证——等用户"已上电"确认。
