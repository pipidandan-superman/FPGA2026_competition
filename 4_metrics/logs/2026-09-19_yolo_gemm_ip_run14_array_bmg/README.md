# run14 — 阵列门 ×3 · BMG IP 重做第四门

**日期**：2026-09-19 · **性质**：IP 硬指标重做链 run11–run16 第四门（用户序④）
**判定**：**三档 PASS（一跑通过），与 run06/run08 逐数对齐 ✅**

| 档 | checks | errors | proto_err | tiles started/done/aborted | blocks_fed/blk_done | y |
|---|---|---|---|---|---|---|
| 4×4   | 846  | 0 | 0 | 62/60/2 | 72/12 | 846  |
| 8×16  | 4250 | 0 | 0 | 37/35/2 | 47/12 | 4250 |
| 16×16 | 6881 | 0 | 0 | 30/28/2 | 40/12 | 6881 |

与 run08（846/4250/6881，同 tile 清单同随机流）**全字段逐数一致**——
同一 golden、同一覆盖，尾换真 BMG IP（D+4）+ 坐标镜像加深后零语义漂移。
（证据：`arr_bmg_console.log`，`EES_VIVADO_RESULT PASS` ×3）

## 本门发现并修复的真 Bug（DUT V2.0 → V2.1）

- **失配链**：尾 V2.0（BMG IP LUT）流水 D+3→D+4，但阵列 y 坐标镜像
  仍是三级（yr1→yr2→yr3，run10a 时代产物——已核实 run10a 无 IP
  wrapper/无 blk_mem_gen 库，跑的是 D+3 旧尾）→ `y_row_o/y_col_o`
  比 `y_valid_o/y_o` **提前一拍**。下游若按坐标写回累加将写错地址。
- **修复**（`yolo_gemm_array.sv` V2.1，唯一改动）：镜像加深为四级
  （yr4/yn4），`y_row_o=yr4 / y_col_o=yn4`。
- **修复证据**：TB 检查器逐拍严格对拍坐标（`coord (%0d,%0d) want…`），
  846/4250/6881 全绿即对齐成立；G1-G9（含掩码尾、抖动、rst 击杀、
  背靠背、大 bias、随机）零漂移。
- 其余延迟敏感点核查：TAILW 出口按 ycnt 计数（非电平等待）、
  tile_done/blk_done 由计数派生、fc/ti 喂侧自洽——均延迟无关，
  除坐标镜像外无第二个失配点。

## DUT / TB / 流程

- DUT：`yolo_gemm_array` **V2.1**（内嵌 `yolo_gemm_tail` V2.0 =
  真 `gemm_bm_lut` IP，SDP 8×256 读延迟 1）+ `yolo_mac_cell` 网格
  （DSP48E1 primitive，用户裁定①合规线，未动）
- TB：`tb/tb_yolo_gemm_array_bmg.sv`（run08 TB 复制 + 仅改名/头部；
  刺激/golden/判据零改动——G1-G9 全延迟无关；diff 核验）
- 档位说明：阵列本体无宽度 IP（尾 LUT R=1 恒定），P_TO×P_TN 参数化
  例化合法，故保留 4×4/8×16/16×16 三档原样与 run06/run08 对齐；
  4×4 退休决策仅适用于宽度被 IP 冻结的 bank 线（run12）。
- 流程：`sim_gemm_array_bmg.tcl`（pe_pack + gemm_bm_lut wrapper +
  -sv 五件 + glbl；xelab ×3 带 `-L blk_mem_gen_v8_4_12
  -L unisims_ver -L unisim`；xsim ×3）
- 旧件保留：run08 的 `tb_yolo_gemm_array.sv` 未动（历史证据）。

## 结论

- 阵列 × 真尾（BMG IP）在完整 G1-G9 矩阵下三档全绿，且与
  IP 化前的 run06/run08 逐数一致——**IP 化零语义漂移**在此线闭环。
- 下一门：run15（合并门 8×16：bank+feeder+array+tail 四体真 IP 全链）。
