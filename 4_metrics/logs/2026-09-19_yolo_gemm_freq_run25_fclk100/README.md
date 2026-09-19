# run25 频率门收官 BOARD_FREQ100_PASS（2026-09-19 深夜）

FCLK0 50 → 100 MHz 重新验证：同一 BD、同一驱动种子，唯一变量 = PS 提供给 PL 的时钟频率。
用户在 Vivado GUI 改 PS7 FCLK0 为 100 MHz 并重新生成比特流、上板通电；验证按 overlay skill
七步重载正典执行。**attempt-3 一跑全绿：`BOARD_FREQ100_PASS`，所有 gate 值与 run23/24 逐位
相同 ⇒ 无频率耦合缺陷。**

- 驱动：`pl_freq100_run25.py`（sha256 `f151e4898c0fd0a2a5a4293915e4a185f93e1aec4f9472b6c9346eba357d990b`，
  attempt-3 终版；板上 sha 核对一致）
- 比特流：`display_test_wrapper.bit` sha256 `0e0ae18571394cf017fcd145115b87f01966865d18d12686b1cfc032a7020ba0`
  （4,045,696 B）；`.hwh` sha256 `8016ac63ecbe544d82277ebccebad203868101a854b3b55f4a0c5d500c28019f`（325,143 B）
- 预检（下载前文件级全绿，与 run24 变量隔离成立）：时序 **WNS +0.405 / TNS 0 / WHS +0.027 @10ns(100MHz)**、
  DRC 0、DSP=68、BRAM=24；HWH FCLK0 = IO PLL / div0=5 / div1=2；地址 GEMM 0x43C00000 / CSR 0x43C10000 / DMA 0x40400000

## 终态日志（board_run25.log，attempt-3）

```
CK1b gemm=0x43c00000 csr=0x43c10000 dma=0x40400000 -> PASS
CK_Fa fclk0_pre=150.0 MHz (boot state, before download)      ← pynq 报告（1.5× 高，见下）
CK4 lock_delta=1 -> PASS
CK_F0 raw FPGA0_CLK_CTRL=00200500 (exp 0x00200500; download programs it, no repair write this attempt)
CK_Fb io_pll FBDIV=30 -> 1000.00 MHz src=0 div0=5 div1=2 true=100.000 MHz pynq_report=150.0 -> PASS
CK5 GEMM_ID=0x20260919 CSR_ID=0x594F4C32 CSR_VER=0x00000300 -> PASS
CK6e S1 rb=128 bad=0 y_count=128 STATUS=00000028 PASS
CK7c S2 rb+=32 bad+=0 stale@0 got=25 y_count=32 PASS
CK8d S3 rb+=128 bad+=0 y_count=128 STATUS=00000038 PASS
CK9 soft_rst STATUS=00000000 y_count=0 -> PASS
DB1..DB7 全 PASS（4096/137/1/1000/8192 全对拍、连发×3、软复位 DMACR 回 0x10002、交叉存活性）
DB7b S1_rerun(0x7E11) rb=416 bad=0 y_count=128 PASS
CKz totals wop=3462 rop=863 rb_ok=416 rb_bad=0 db_ok=9 db_bad=0
CKz BOARD_FREQ100_PASS
```

期望纪律逐值命中：S1/S2/S3 的 y_count（128/32/128）、幻影槽保旧值（0x25）、STATUS（0x28/0x38）、
DMASR IOC+Idle 模式（0x1002）、总账（wop=3462、rb_ok=416、db_ok=9）全部与 run23/run24 相同——
GEMM 算术与 DMA 搬数在 100 MHz 真时钟下位级不变。

## CK_F 三次尝试与自我修正（本 run 的真实过程，全部证据在案）

1. **attempt-1（board_run25_attempt1.log，板上 10:22）**：CK_F v1 判据用了错误的寄存器布局
   （凭记忆的"UG585 布局" DIV0[4:0]/DIV1[13:8]/SRCSEL[25:20]）解码 raw=0x00200500，并采信
   pynq `fclk0_mhz=150.0` 报告 → FAIL。实际上 raw 0x00200500 本来就是真 100 MHz。
2. **调查**：`probe_clk.py`（pynq MMIO 无 zocl 设备 → "No Devices Found"）→ `probe_clk2.py`
   （raw /dev/mem + sudo，只读）钉死板卡时钟常数：**晶振 33.3333 MHz**、IO PLL FBDIV=30 →
   1000.00 MHz、ARM 1333.33 / DDR 1066.67、FPGA1-3 boot 残留 0x00100F00（IO÷15=66.67 MHz）。
   此间我**误判** pynq 3.0.1 `ZYNQ_CLK_FIELDS` 是"+8 位移位 bug"，把修复写写进驱动 → attempt-2。
3. **attempt-2（board_run25_attempt2.log，板上 10:40）**：`wrote=0x00000205 readback=0x00000200`——
   硬件拒绝 bits[3:0] 写入。这一拒写实验**证伪我的布局、证实 pynq 布局=硬件真值**。副作用：
   寄存器被留在 0x00000200（div1=0，未定义 fabric 时钟）。
4. **恢复**：`restore_clk.py` 原始输出（`restore_clk_output.txt` 转写在案）：`before=0x00000200 →
   readback=0x00200500`，RESTORED_100MHZ_OK——回到 download() 本应留下的正确状态。
5. **attempt-3（board_run25.log）**：驱动 v3 = CK_F verify-only（零 SLCR 写）+ 裁定布局解码 +
   docstring 纠正 → 全绿收官。

## pynq 3.0.1 时钟模型最终裁定（板上实验三重证据）

- **`ZYNQ_CLK_FIELDS` = 硬件真值**：`FPGA0_CLK_CTRL (0xF8000170)` = DIVISOR0[13:8] /
  DIVISOR1[25:20] / SRCSEL[5:4]；**bits[3:0] 保留、写忽略**（attempt-2 拒写实测）。
  `Overlay.download()` 按 HWH clock_dict 编程 FCLK0，写入落位正确。
- **唯一真缺陷 = 参考时钟模型**：`_ClocksZynq.DEFAULT_SRC_CLK_MHZ = 50.0`，本板晶振实为
  33.3333 MHz ⇒ **pynq 报告的所有 MHz 一律 1.5× 高**（报 150 = 真 100；报 75 = 真 50）。
  附带：`fclk0_mhz` 在分频积=0 时抛 ZeroDivisionError（attempt-2 日志实证）——只记录、不门控。
- 板卡常数（probe_clk2 实测，raw 列为权威；其 decode 行是错误布局时代的历史产物，正确解码
  以 CK_Fb/restore_clk.py 为准）：IO PLL FBDIV[18:12]=30×33.3333=1000 MHz。

## 寄存器史定稿（OBSERVED=板上实测 / MODEL=写入模型推定）

| 时点 | 0xF8000170 | 解码（裁定布局） | 真实频率 | 证据 |
|---|---|---|---|---|
| Boot FPGA0 | 0x00101400 (MODEL) | IO÷20÷1 | 50 MHz | 与 M13 示波器实测 50 MHz、pynq 报 75（=1500/20）吻合 |
| run23/24 下载后 | **0x00400500** (MODEL) | IO÷5÷4 | **50 MHz 精确** | 干净 RMW 写入模型（attempt-1 实测 0x00200500 无残留位类比证实） |
| run25 attempt-1/2 下载后 | 0x00200500 (OBSERVED) | IO÷5÷2 | 100 MHz | attempt-1 日志、probe_clk2 |
| attempt-2 误写后 | 0x00000200 (OBSERVED) | div1=0 | 未定义 | attempt-2 日志拒写行 |
| 恢复后 / attempt-3 | 0x00200500 (OBSERVED) | IO÷5÷2 | 100 MHz | restore_clk_output.txt、board_run25.log CK_F0 |

**勘误（写进证据链，防止错误传播）**：本 run 分析过程中 9 处文本曾把 run23/24 下载后值写成
`0x00140500` 并"解码"为 div0=5/div1=4——该值既非板上观测（全部出现在分析文本里），按位展开
也是 [25:20]=1≠4 的算术错误。正确值由 pynq Register 掩码 RMW 模型推定 = 0x00400500（div0=5、
div1=4、src=IO），与 attempt-1 实测的干净写入（0x00200500，boot 残留位全清）同机制互证。
结论不变（run23/24 = 真 50.00 MHz，B1/B2 回溯完整性成立），依据修正为正确算术。物理旁证：
OOC 实测 Fmax≈116 MHz，若 run23/24 真跑 200 MHz 则 288/288 + 416 次回读零错不可信。

## 证据清单（本目录）

| 文件 | 说明 |
|---|---|
| `board_run25.log` | attempt-3 终版全绿日志（BOARD_FREQ100_PASS） |
| `board_run25_attempt1.log` | attempt-1 失败日志（CK_F v1 错误布局判据） |
| `board_run25_attempt2.log` | attempt-2 失败日志（拒写证据 `wrote=0x205 readback=0x200`） |
| `pl_freq100_run25.py` | 驱动终版 v3（verify-only CK_F + 修正 docstring） |
| `probe_clk.py` / `probe_clk2.py` / `probe_clk2_output.txt` | 时钟侦察（pynq MMIO 失败 → raw /dev/mem 成功） |
| `restore_clk.py` / `restore_clk_output.txt` | 寄存器恢复 + 原始输出转写 |
| `run_freq100.sh` | 板上执行包装（sha256 `2edec674f7db11ef…`） |
| `display_test_wrapper.bit` / `.hwh` | 100 MHz 比特流（sha 见上） |

## 边界与下一步

- 100 MHz 频率门独立收官（用户决策：与 B3 分开验证）。设计余量：板级 100 MHz 通过 +
  OOC Fmax≈116 MHz；如需再提频需重新过时序与板验。
- 板上现挂 = 100 MHz 版 GEMM+CSR+DMA 三从机基线（FCLK0=100 MHz）。
- B3（DMA+GEMM 大 KC）桥接设计立项与 4 个授权决策点仍待用户；本 run 未动 B3 任何设计。
