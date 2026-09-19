# 2026-09-15 yolo7020 M10 GEMM 阵列集成门（run01）

## 目标（架构基线 M10）

`rtl/yolo_gemm_array.v`：把 M1–M9 已过门模块（ctrl V1.1 / dma / addrgen /
wbuf / xbuf / acc / requant / silu_lut）集成为 SIM 8×8 阵列顶层，首次以
**全链数据通路**（DDR→DMA→bank→PE 阵列→requant→LUT→Y 写回）跑 6 层流，
对 M0 零差异 + 真实数据回归，PASS token `TB_GEMM_ARRAY_PASS`。

## 结果

**TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247
ldone=6 adone=1**（sim_gate_run1.log，剥探针干净门首跑即绿，47.76 ms 仿真）。

层计划（S=合成/R=真实；总输出 438447 全比对）：

| 层 | 源 | oc | n | K | act/first | 黄金 | 结果 |
|---|---|---|---|---|---|---|---|
| L0 | S1 | 7 | 49 | 27 | 1/0 | M0 核实例 | 全对 |
| L1 | R1 model.0 | 16 | 25600 | 27 | 1/1 | run04 npz | 全对 |
| L2 | S2 | 16 | 25 | 576 | 1/0 | M0 核实例 | 全对 |
| L3 | S3 | 9 | 256 | 64 | **0**/0 | M0 核实例 | 全对 |
| L4 | R2 model.16 | 64 | 400 | 576 | 1/0 | run04 npz | 全对 |
| L5 | S4 | 8 | 25 | 2304 | 1/**1+last** | M0 核实例 | 全对 |

层间间隙 gaps=[4,0,3,0,6,2]（含 0 与非 0）；oc 尾 {7,1}、n 尾 1 覆盖；
K ∈ {27,64,576,2304}；真实回归 R1 409600 + R2 25600 格零失配。

## 集成中发现并修复的缺陷（门冻结前，全部留证）

### RTL：yolo_gemm_array.v ×3
1. **addrgen 端口位宽**（装配致命）：`cfg_k_r`（12 位）/`load_n_tail_w`
   （TILE_AW 位）直连 16 位端口 `[15:0]` 越界 → 参数化零扩展
   `{{(16-K_AW){1'b0}}, cfg_k_r}`。
2. **loader 层边界挂死**：末 tile 后停在 S_LCHK，`!loaded_all_q` 永假，
   下一层 ctrl 在 S_TILE 等 tile_rdy 永久挂起（dbg1：状态冻结 260 ms+ 证据）。
   修复：`if (loaded_all_q) ldr_state_r <= S_LDESC;`（dsc_accept 复位游走）。
3. **oc_loc 解码循环方向**（降序覆盖）：`for (oi=OC_EDGE-1; oi>=1; ...)` 的
   最后赋值恒为 oi=1 → 尾 tile 与整行 ≥1 的输出地址全部塌缩 → 328608 双写 +
   328608 漏写（dbg2）。修复：升序循环（最后赋值 = 最大满足 oi）。

### RTL：yolo_conv_core.v V1.2（触发 M0 门重跑 run02）
4. **越界部分选择**：`oc[P_AW-1:0]` 在 P_AW > OC_CW 时高位读 X → 黄金核
   bias/m/shift 服务全 X → 整层输出 X（dbg3/dbg4：bd/md/sd=x 且数组普查全净；
   dbg5：assign 与 always@(*) 逐位相同，排除服务冻结理论 → 矛盾唯一解在端口
   表达式）。判据 OC_CW < P_AW 与逐层好坏完美吻合（L0/L2/L5 坏、L3 好——
   "act=1 才坏"是巧合）。M0 门全部旧用例 P_AW == OC_CW 从未触发。
   修复：`oc_ext` 零扩展后切片；**M0 门 run02 回归 11/11 同数 PASS（零行为
   变化）**，见 `../2026-09-15_yolo7020_m0_conv_core_run02/`。

### TB：tb_yolo_gemm_array.v
5. **黄金服务改连续 assign**（M0 TB 同款）：替换 always@(*) reg 服务
   （dbg4/dbg5 证明两者行为一致后保留 assign 款——消除一类求值疑点）。
6. **哨兵歧义规则**：0xA5 是合法输出值（L3 有 4 格 DUT 与黄金同为 0xA5=165，
   dbg5 [dbg-a5w] 证实恰为 4 个哨兵格）。比对改为：dut 侧 SENT 且参考值 ≠0xA5
   才计 unwritten；完备性由 dut_wr==total_out && dbl==0（写双射）与
   gold_wr==oc*n && gdbl==0（黄金全覆盖）机器检查保证。

## 环境与命令

- ModelSim SE-64 10.1c（win64），`vsim -c -novopt`；
  MGLS_LICENSE_FILE=D:/work/modelsim/win64/LICENSE.TXT。
- 激励：`python m10_vecgen.py`（seed 1010；单 DDR 字节镜像 65621×64b LE 字
  + 28 令牌层描述 + yexp1/2 + gw/gb/gm/gs×4；W 行 KPAD 填充满足 DMA 8B 对齐）。
- 编译：`vlog -quiet ../../rtl/yolo_gemm_array.v ../tb_yolo_gemm_array.v`
  （conv_core V1.2 随依赖库刷新）。
- 运行：`vsim -c -novopt +STIM=../stim/m10 +WDT_MS=900000
  -do "run -all; quit -f" -l <本目录>/sim_gate_run1.log
  work.tb_yolo_gemm_array`。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS token 摘录）
3. sim_gate_run1.log（干净门原始 transcript，未编辑）
4. stim_manifest.json + stim_sha256.txt（23 个激励文件哈希）
5. 失效-定位链原始 transcript（bug 证据，未编辑）：
   - sim_m10_run1_l1hang.log（S_LCHK 挂死首证，含 L0 双写）
   - sim_m10_dbg1.log（挂死态冻结转储 24 帧）
   - sim_m10_dbg2.log（解码环方向：err=328879/dbl=328608 首写散布）
   - sim_m10_dbg3.log（解码修复验证：dbl=0，err=947；gold=x 浮现）
   - sim_m10_dbg4.log（X 普查全净 + 首写通道 bd/md/sd=x）
   - sim_m10_dbg5.log（assign 服务逐位相同 → 排除冻结理论；a5w=4 哨兵格证实）
   - sim_m10_dbg6.log（conv_core V1.2 + 哨兵规则后首 PASS，含探针）
6. M0 门重跑（conv_core V1.2 回归）：`../2026-09-15_yolo7020_m0_conv_core_run02/`

## 结论

M10 阵列集成门通过。M1–M9 数值链在全阵列拓扑下对 M0 零差异；真实层
（model.0 / model.16，run04 权威链）逐位一致；层序列/尾 tile/间隙/首末层
pad 与 act 旁路全覆盖。§5 全链重跑义务履行（conv_core 改动 → M0 门
run02 回归零差异）。
