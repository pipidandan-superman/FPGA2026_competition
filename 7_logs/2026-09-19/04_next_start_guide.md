# 2026-09-19 下次启动指南（run25 深夜批后当前态）

## 第一步（会话开始时）

1. 读 [HANDOFF.md](../../../HANDOFF.md) 顶部两节（深夜 run25 + 晚 B1/B2）；
2. 读 `4_metrics/logs/2026-09-19_yolo_gemm_freq_run25_fclk100/README.md`
   （频率门全叙事 + pynq 时钟模型裁定 + 寄存器史定稿）；
3. 核对 git：用户分支 `codex/full/pipidandan-superman` 应至 `cd81d41`（run25 证据
   `c7e74cd` + 100MHz 工程态 `cd81d41`）。

## 主线状态（勿重做）

- **B1+B2+频率门三收官**：run23 BOARD_B1_PASS（288/288）/ run24 BOARD_B2_PASS
  （DMA 回环全绿）/ **run25 BOARD_FREQ100_PASS**（FCLK0 真 100.000 MHz，全部
  gate 值与 50MHz 版逐位相同——无频率耦合缺陷）。
- **板上现挂**：100 MHz 版 GEMM+CSR+DMA 三从机基线（FPGA0_CLK_CTRL=0x00200500）。
- 已闭环勿重做：run01–run20（oracle/单元/阵列/IP 重做/WNS 收敛）、run21–22b
  （顶层+BD+比特流）、run23–25（三板级门）。PPU 线七门全绿已迁移（fa26666）。
- **pynq 时钟模型裁定（ees331 画像已录）**：ZYNQ_CLK_FIELDS=硬件真值
  （DIV0[13:8]/DIV1[25:20]/SRCSEL[5:4]，bits[3:0] 写忽略）；唯一缺陷=参考时钟
  50 vs 晶振 33.3333 ⇒ 所有 MHz 报告 1.5× 高。门控用 raw SLCR+PLL FBDIV。

## 回退/复现锚（全在用户分支，自包含）

- **100 MHz 复现**：`display_test_wrapper.bit`（sha `0e0ae185…`）+ 同名 HWH +
  `pl_freq100_run25.py`（三份均在 `4_metrics/logs/2026-09-19_yolo_gemm_freq_run25_fclk100/`）
  → 七步正典上板应复现 `BOARD_FREQ100_PASS` 全 gate 值（期望值逐条列在该 README）。
- **工程重建**：`2_fpga/3_yolo_zynq/proj/axi_gemm_test/`（.xpr/BD/17 XCI/impl 报告，
  `cd81d41`）+ `rtl/GEMM/`（$PPRDIR 相对引用）→ Vivado 2025.2 打开即可重跑实现。
- **50 MHz 回退**：run24 证据目录 bit（sha `6d91f2b5…`）+ `pl_b2_loopback.py`。

## 下一步最应优先执行的动作

**B3 DMA+GEMM 大 KC——唯一挂起项（等用户授权）**。四个决策点已呈用户：
① 桥接合同（MM2S 流→GEMM 装载口握手协议设计）；② B2 回环保留/移除；
③ y 回写 B3 vs B4（我方建议 B4）；④ 频率门（已闭，100 MHz 基线就位）。
授权前不动 B3 任何设计。

## 刚开始时不要做的事情

- 不要凭记忆写 SLCR/XCI 寄存器模型（run25 教训：凭记忆的布局被板上拒写实验证伪
  ——一律从权威源转录）；
- 不要用 pynq 报告的 MHz 做门控判据（本板一律 1.5× 高）；
- 不要"修复" download() 的 FCLK 写入（落位正确；只在 raw 值异常时核查）；
- 不要动冻结工程/已验收 RTL；不要推 main；git 只走命名文件 + add -f 申报。

## 成功标准（下一会话）

- B3 授权落定并立项（桥接合同文档 + 门控计划），或用户另行指定方向；
- 任何新 run 证据齐套（run 目录 + 7_logs 收口 + 三件套同步 + git 推送）。

## 阻塞

仅 B3 授权决策挂起（用户）；无技术阻塞。
