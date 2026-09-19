# 06 — G3 卷积引擎逐模块门 M0–M11（2026-09-15 续，全绿收批）

## 摘要

G3 PL 卷积引擎单日完成 **12 个门全部通过**：conv0 标量核 → M0 参数化通用核 →
M1 DSP 双打包 → M2–M9 单元门 → M10 阵列集成 → **M11 全网端到端**（1 帧全 63
conv 3,553,900 格逐位零误差 + head sha256 == run04 frame0）。RTL 12 件全
Verilog-2001；每门独立 run 目录四件套。执行授权链：M0–M9（"开始运行"）→
M10（"开始M10集成"）→ M11（"ok，先做M11"）；M12/M13 未动。

## 时间线（详见各 run 目录 README 失败链）

| 时段 | 节点 | 关键事件 |
|---|---|---|
| 上午 | G3 基线冻结 | `1_docs/doc/yolo7020_gemm_pe_architecture_2026-09-15.md`：三实例（SIM-8×8/BASE-8×16/PROD-16×16）、M0–M13 门、证据四件套规则 |
| 08:0x | conv0 门 | 2 处符号性 bug（拼接/三目毒化）→ 409600/409600×2；确立 `-novopt` 铁律 |
| 09–11 | M0 | run1 **假绿**（退化合成参数掩盖 RTL K 分解 bug，仅真实回归暴露）→ 生成器 v2 反退化三原则 + RTL V1.1；11/11 |
| 11–12 | M1 | §3.2 字面布局 2^24 穷举 74.6% 败 → **偏置布局 0 败**，§3.2 按证据修正 |
| 12–14 | M2–M7 | 六单元门（M3 黄金侧 2 bug：键空间分离/未写地址不可读，预焙进 M4 首跑绿） |
| 14–15 | M8 | run1 全红 = 黄金**先 step 后发射**惯例成文；23 层 15K 档+5N 档全集 |
| 15–16 | M9 | run3 真 RTL bug：串化器挂 FSM 分支重复交付 → 独立数据进程规矩成文 |
| 16–19 | M10 | 集成 6 层流 438,447 格零差异；揪出 4 个 RTL 缺陷（conv_core V1.2 越界部分选择最重）→ §5 全链重跑义务：M0 run02 回归同数 PASS |
| 19–21 | M11 | 三重生成期护栏 vecgen + TB 扮 PS 解释器；run01 = TB WDT 32 位溢出**假失败**（教训成文）→ run02 门 PASS + M11_HEADCHK_PASS |

## 结论数字

- `TB_CONV0_PASS` 409600/409600 ×2；`TB_CONVGEN_PASS` 11/11（V1.2 后 run02 同数）
- `TB_PE_PACK_PASS` 10216/10216 + 2^24 穷举 0 败；M2–M7 六门全零失配
- `TB_CTRL_PASS` 695092 周期 ×15 输出；`TB_DMA_PASS` 210904 字节/1666 AR
- `TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447`
- `TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900 head_bytes=149100`
  + `M11_HEADCHK_PASS sha256=9ce70525...`（== run04 frame0，6 张量拆分逐字节全对）
- **k1×1 几何 M0–M10 从未覆盖，M11 首次上场即逐位通过**

## 备注

- hw_contract（`2_fpga/3_yolo_zynq/hw_contract/address_map.md`，提交 de46cd5）
  为文档型交付（从 0_diaplay_test HWH 只读提取，来源已注明），无 PASS 门故无
  run 目录；其消费始于 M12。
- conv0 run 目录原始 transcript 于当晚补录（19 件，见该目录 README 补记）。
- 教训清单与 TB 惯例：03_validation_summary 本日段 + 04_next_start_guide 第 3/4 条；
  工具链坑全量在 memory（yolo7020-deployment-state）。
