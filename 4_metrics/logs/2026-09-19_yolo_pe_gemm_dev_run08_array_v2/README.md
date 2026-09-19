# run08：P1.1【V1】阵列宽字口改造单验（G2 第一步）

日期：2026-09-19（白班，用户批准 P1-P3 计划后按序执行）
判据：run06 阶段矩阵全量复跑 errors=0 + 守恒/blk_done 对齐 + proto_err=0

## 终态：三档 PASS（第三跑），与 run06 逐数对齐 ✅

| 档位 | checks | errors | proto_err | tiles started/done/aborted | blocks_fed/blk_done | y |
|---|---|---|---|---|---|---|
| 4×4   | 846  | 0 | 0 | 62/60/2 | 72/12 | 846  |
| 8×16  | 4250 | 0 | 0 | 37/35/2 | 47/12 | 4250 |
| 16×16 | 6881 | 0 | 0 | 30/28/2 | 40/12 | 6881 |

与 run06（846/4250/6881，同 tile 清单同随机流）完全一致——
**同一 golden、同一覆盖、宽字口改造零语义漂移**。
控制台：`arr_console_v3.log`（`EES_VIVADO_RESULT PASS` ×3）。

## DUT 改动（rtl/GEMM/yolo_gemm_array.sv V1.1 → V2.0）

- 删：③档功能缓冲 W_buf/X_buf 及 8 个装载写口、P_KMAX 参数、
  stall_i、k_base、k_cnt（时序角色）；
- 增：宽字口 `w_word_i[8*P_TO]`（行广播）/`x_word_i[8*P_TN]`（列广播）
  + `word_valid/word_first/word_last` 入 + `word_ready` 出；
- 阵列纯消费者：`word_ready=(state==S_ISSUE)`，ISSUE 离开判据
  =**收到的 word_last 拍**（k 时序移交外部供数方）；
- cell 门控改旁带派生：first_k=accept·word_first·blk_first，
  last_k=accept·word_last·blk_last；
- 影子 wcnt 对账（word_first 位置/word_last 位置/字数 vs blk_len）
  → 粘滞 `proto_err_o`，只报警不进数据通路（板上可挂 CSR）；
- cell/tail/FSM/尾读出/TAILW(ycnt) 语义零改动（契约冻结）。

## TB 改动（tb/tb_yolo_gemm_array.sv V1.0 → V2.0）

- fill_wx 只填 TB 镜像（DUT 无写口），随机流不变；
- do_block：块头 1 拍 + 字流握手（每拍打包 k 切片成宽字）+
  生产者 valid 抖动（G5：随机空 1-2 拍）；
- G6 改流中击杀（发 20-59 字后 rst）；
- proto_err 上升沿计入 errors；golden（INT64 oracle+独立 requant）不变。

## 过程档案：两轮 FAIL（均 TB 侧，DUT 零嫌疑）

1. **首跑 FAIL**（`arr_console.log`：4×4=5 错/8×16=36/16×16=62，
   proto_err 全 0）：`do_block` 每块从 pack_word(0) 重发——
   **块基址（k0）没随数据流移交**。V1 时代绝对 k 寻址是阵列内部
   k_base 做的；V2 供数方负责，do_block 加 k0 参数、run_tile 累加
   kbase 修复。错误全部集中在大分块多块 tile（G2/G8），单块全绿、
   G3（K=64 小块）侥幸被 requant 压平——与理论预测吻合。
   **教训入档：V2 契约下"块基址"是供数方（TB 今日/feeder 明日）的
   职责，P1.2 feeder 唯一 k 计数器必须管绝对 k。**
2. **二跑 PASS 但矩阵不齐**（`arr_console_v2.log`：846→799 等）：
   修 1 时把 G6 内层循环变量写成了外层的 t——击杀 2 次→1 次、
   rs1 少抽一次致 G9 漂移。换独立变量 q 修复。
   附带修正：循环上限内 `$random` 每迭代求值会漂移随机流
   （首跑发现的第二问题），上限预计算一次。

## 环境

- 工具链：F:/vivado2025/2025.2/Vivado（统一安装版，本 shell 无
  XILINX_VIVADO 环境变量——tcl 已改为显式路径直调）；
- 脚本：`sim_gemm_array_v2.tcl`（xvlog→xelab→xsim 三档，
  unisim+glbl，与 run06 同构）；
- 中间产物：xsim.dir/（证据保留，git 不传）。

## 结论

**P1.1【V1】门 PASS**——阵列宽字口契约冻结（供 P1.2 bank+feeder
对接）：块头 blk_valid/blk_len/blk_first/blk_last（IDLE/WAIT 接受）
+ w_word/x_word 每拍一个 k 切片 + word_valid/first/last 与 word_ready
握手 + ISSUE 内每拍可收 + word_last 拍离开 + proto_err 对账。
下一步：P1.2【V2】run09（yolo_gemm_bank + yolo_gemm_feeder 单验）。
