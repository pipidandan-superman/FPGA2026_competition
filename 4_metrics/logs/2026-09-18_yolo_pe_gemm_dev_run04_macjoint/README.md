# run04 — 级 2 PE+acc 联合 MAC 仿真（GATE PASS）

> 2026-09-18 迁移记录：RTL 自 rtl_pe/ 迁至 rtl/GEMM/（用户指定目录，后续 GEMM 相关代码统一放此）。tcl 路径已同步，迁移后三个门仿真重跑全 PASS 且 checks 数逐字节一致。

日期：2026-09-18。PE 手册 §1 MAC 定义 = 双乘积 PE + 两路独立 INT32 累加器。
用户确认验证流的第 2 级：②独立仿真（[run03](../2026-09-18_yolo_pe_gemm_dev_run03_accdual/)）
→ **本级联仿真** → ③④ 阵列/尾/规模。

## 结果

```
EES_SUMMARY checks=164044 errors=0 lat_err=0
EES_VIVADO_RESULT PASS
EES_MAC_INFO tiles started=240 done=237 aborted=3   （240-3=237 守恒 ✓）
EES_MAC_INFO M9 manual s8 bound pinned (real DSP path): 37748736
```

- **lat_err=0**：每个 done 脉冲都带 issue 周期标签，issue D → acc/done 可见 D+4
  契约逐笔成立（①的 D→D+3 产品契约 + 累加器 E3 采样沿 + 1）。
- **M0 金值交叉**：TB 独立乘与 run01 golden_pe.hex 76 向量逐拍零失配——级 2
  链条回溯到软件 oracle 成立。
- **M9 域界**：−128×−128 ×2304 = +37,748,736 经真实 DSP48E1 路径字面钉死
  （PE 手册 §8 界）；127×(−128) 负极值 −37,453,824 与交替号对消亦过 INT64 对拍。

## 逐相 tally（终值精确；相间 tally 的 done 落后 1–2 属显示伪差——末拍 done 在
D+4 才落，tally 在 gapn 后即打印，欠账滚入下一相，最终守恒精确闭合）

| phase | 内容 | 增量（started/done/aborted） |
|---|---|---|
| M0_GOLDEN_CONT | golden 76 向量单 tile + 金值交叉校验 | +1/+1/0 |
| M1_K_SWEEP | K=1/27/32/576/2304 随机 int8 | +5/+5/0 |
| M2_BACKTOBACK | 6 tile 零间隙（fk 紧跟上一 tile 的 lk） | +6/+6/0 |
| M3_RESUME | [576,1152,576] 与 [1,1,27,1,34] 分块续累 | +2/+2/0 |
| M4_MASK | 掩码 01/10/11、背靠背再激活、K=1 掩 lane | +7/+7/0 |
| M5_STALL | 25% 空闲拍 + valid=0 裸 last_k（无 done） | +1/+1/0 |
| M6_RESET_MID | K=1000 中途 rst 击杀在飞产品 + 末拍沿 rst 击杀 + 新 tile | +4/+2/+2 |
| M7_CLEAR_RESTART | 排空后 clr 中途击杀 + done 后空闲 clr + clr 后紧接 K=1 | +3/+2/+1 |
| M8_K1_CORNER | 8 组 int8 角点 K=1（fk=lk 同拍经流水） | +8/+8/0 |
| M9_EXTREME_SUM | ±37748736 域界/负极值/交替号 | +3/+3/0 |
| M10_RANDOM_TILES | 200 随机 tile（K/掩码/gap/空闲/角点注入） | +200/+200/0 |

## DUT（rtl/GEMM/yolo_mac_cell.sv）

纯组合已验证单元，唯一新增逻辑 = **first_k/last_k 三级边带流水**（与 PE 自带
in_valid/lane_mask 流水同沿，纯延迟线不 gate valid——acc 侧自行过滤）：

```
issue(E0 域): w,x0,x1,mask,fk,lk,val ──┐
  yolo_pe_core (①, 真 DSP48E1) ────────┤ D+3 呈现 p0/p1/v/mask
  fk/lk 三级流水（本级新增） ───────────┘
  yolo_acc_dual (②) 在 E3 沿采样 ──> acc 更新/done 脉冲呈现于 D+4
```

阵列契约继承：clr 排空（≥4 空拍）后才可置位；rst 单沿击杀全线在飞。
延迟契约：issue D → acc/done 可见 **D+4**（K=1 同拍 fk=lk 也在 D+4 出 done）。

## TB 架构（rtl/GEMM/tb/tb_yolo_mac_cell.sv）

- **端到端独立 oracle**：乘积 = TB 符号乘（永不取 DSP/打包公式），累加 = TB
  INT64 加（GEMM 手册 §14）；过门要求 acc ≡ sext64(oracle) 逐位相等。
- **4 级镜像延迟计分板**：①的 3 级产品/边带镜像 + E3 采样沿第 4 级（oracle 在
  第 4 沿提交）；issue 周期标签逐级移位，done 呈现拍硬查 `cyc−tag==4`。
- 每拍不变量、守恒记账（含 K=1 同拍 start/done 修复逻辑）、gapn 驱动纪律、
  $random 无符号模习惯用法、beat8 X 绊线——全部自 ② 继承。

## 调试记录（2 处，均 TB 自伤，DUT 零缺陷）

1. **编译错**：M8 `beat8` 少传第 3 操作数（7 参给 6）。
2. **M9 钉值打错 tile**：`m9_pin_pend=1` 设在 M8 尚有两个在飞 done（D+4 延迟）
   未排空时，钉子落在 M8 的 k=6 tile——报错值 `acc0=-64` 与 64×(−1) 精确吻合
   即确诊。修复：M8 后加 `gapn(4)` 排空再设标志。教训：**流水化设计里，
   "阶段边界" 必须按 D+4 排空判定，不能按最后一拍判定。**

## 环境/复现

- 真 DSP48E1 路径：`xvlog ref(yolo_pe_pack.v) + -sv core acc mac tb + glbl.v`
  → `xelab -L unisims_ver -L unisim` → `xsim -testplusarg GOLDEN=<golden_pe.hex>`。
- 运行：`cmd //c "F:\vivado2025\2025.2\Vivado\bin\vivado.bat -mode batch -source sim_mac_cell.tcl -notrace -nojournal" > mac_console.log 2>&1`。
- 证据：`mac_console.log`（PASS 完整原始输出）、`sim_mac_cell.tcl`。

## 文件

- `E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_mac_cell.sv` — 级 2 DUT（新文件）
- `E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_mac_cell.sv` — 级 2 门 TB

## 下一步

③ 小阵列 + 共享尾（golden_tail.hex）→ ④ 8×16/16×16 参数化 → 综合/时序/板测
（系统级验收，勿以理论下界替代）。上板策略：与用户确认 **等 GEMM 整体上板**，
单 MAC 不单独上板（理由见当日汇报）。
