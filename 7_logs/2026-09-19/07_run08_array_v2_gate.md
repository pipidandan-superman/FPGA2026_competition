# 2026-09-19 白班工作日志 07：P1.1 run08 阵列宽字口改造单验（G2 第一步）

状态：**PASS ×3，P1.1 门闭**。完整档案见
`4_metrics/logs/2026-09-19_yolo_pe_gemm_dev_run08_array_v2/README.md`。

## 结果（第三跑 arr_console_v3.log，三档 EES_VIVADO_RESULT PASS）

| 档位 | checks | errors | proto_err | started/done/aborted | blocks/blk_done | y |
|---|---|---|---|---|---|---|
| 4×4 | 846 | 0 | 0 | 62/60/2 | 72/12 | 846 |
| 8×16 | 4250 | 0 | 0 | 37/35/2 | 47/12 | 4250 |
| 16×16 | 6881 | 0 | 0 | 30/28/2 | 40/12 | 6881 |

与 run06 基线逐数一致（同随机流、同 tile 清单、同 golden）——宽字口
改造零语义漂移，判据（errors=0+守恒+blk_done 对齐+proto_err=0）全满足。

## RTL 变更（rtl/GEMM/yolo_gemm_array.sv V2.0）

删功能缓冲/装载写口/P_KMAX/stall_i/k_base/k_cnt；增宽字口
（w_word[8*P_TO] 行广播 / x_word[8*P_TN] 列广播 + valid/first/last/ready
握手）；ISSUE 在**收到的 word_last 拍**离开（k 时序移交供数方）；影子
wcnt 对账 → 粘滞 proto_err_o（只报警不门控）。cell/tail/FSM/尾读出零改动。

## 三跑史（两轮 FAIL 全在 TB，DUT 零嫌疑）

1. 首跑：多块 tile 错（4×4=5/8×16=36/16×16=62）——do_block 每块从
   k=0 重发，**块基址 k0 没随数据流移交**（V1 内部 k_base → V2 供数方
   职责）。加 k0 参数+run_tile 累加修复。
2. 二跑：G6 击杀 1 次≠run06 的 2 次、G9 y 漂移——修 1 时内层循环变量
   用了外层 t（clobber）+ 首跑暴露的循环上限 $random 每迭代求值漂移
   随机流。独立变量 q + 上限预计算修复。
3. 三跑：全绿，逐数对齐。

## 教训（P1.2 直接输入）

- **契约移交必须显式继承**：V2 供数方（TB→今后 feeder）独占绝对 k
  序列（块基址 k0 + 块内偏移）；feeder 的"唯一 k 计数器"设计由此定档。
- TB 随机纪律：循环上限内 $random 每迭代求值会漂移流；内层循环禁用
  外层变量。两条均已注释入 tb 源码。

## 下一步

P1.2（run09）：yolo_gemm_bank.sv + yolo_gemm_feeder.sv 单验——双组
宽字 TDP BRAM + 流式写口；feeder 唯一 k 计数器（含 k0）、组 MUX
（独立 w_sel/x_sel）、地址提前两拍（同步读 1 拍+保持 1 拍）、
换组拍=新块接受拍；TB 覆盖组交换×块首中尾×装载早/恰好/晚到×
off-by-one 逐拍对账×TDP 无冲突。
