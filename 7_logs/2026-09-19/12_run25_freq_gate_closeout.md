# 12 · run25 频率门收官 BOARD_FREQ100_PASS（FCLK0 50→100 MHz）

**结论**：唯一变量 = FCLK0 频率（用户 GUI 改 PS7 + 重生成比特流 + 上板）。attempt-3 一跑全绿
`BOARD_FREQ100_PASS`：CK_F 真 100.000 MHz（raw 0xF8000170=0x00200500 = IO_PLL 1000÷5÷2），且
S1/S2/S3、DB1-DB7 全部 gate 值与 run23/24 **逐位相同**（y_count 128/32/128、幻影槽 0x25、
STATUS 0x28/0x38、DMASR 0x1002、wop=3462/rb_ok=416/db_ok=9 双零错）——无频率耦合缺陷。
证据：`4_metrics/logs/2026-09-19_yolo_gemm_freq_run25_fclk100/`（README 含全过程）。

**过程要点（三次尝试 + 一次自我修正，全部留档）**：
- attempt-1：CK_F v1 用凭记忆的错误布局解码 + 信 pynq 150 报告 → 假 FAIL（时钟本来就是真 100）。
- 调查：probe_clk2.py（raw /dev/mem）钉死板卡常数：晶振 **33.3333 MHz**、IO PLL FBDIV=30→1000 MHz。
  此间误判 pynq `ZYNQ_CLK_FIELDS` 为 bug → attempt-2 写"修复"0x205 → **硬件拒写 bits[3:0]**
  （wrote=0x205 readback=0x200）→ 裁定反转：**pynq 布局=硬件真值**（DIV0[13:8]/DIV1[25:20]/
  SRCSEL[5:4]，bits[3:0] 保留写忽略）；副作用寄存器被留在 div1=0，restore_clk.py 恢复 0x00200500。
- attempt-3：驱动 v3（verify-only 判据 + 修正 docstring）全绿。

**pynq 3.0.1 唯一真缺陷**：参考时钟模型 50 vs 实际 33.333 晶振 ⇒ 所有 MHz 报告 1.5× 高
（150 报=100 真、75 报=50 真）；fclk0_mhz 分频积 0 时抛 ZeroDivisionError。门控一律用
raw SLCR + PLL FBDIV 推真值，pynq 报告只记录。该板卡事实已入 ees331 板卡画像（不进 skill，
按四层归位原则）。

**勘误入档**：run23/24 下载后寄存器值曾误写为 0x00140500（分析文本算术错误，非观测）；
正确值 = 0x00400500 = IO÷5÷4 = 真 50.00 MHz（干净 RMW 模型 + attempt-1 实测类比证实）。
**B1/B2 回溯完整性成立，依据修正。**

**下一步**：B3 DMA+GEMM 大 KC（桥接设计立项 + 授权决策点 4 项待用户）；板上现挂 100 MHz
三从机基线。
