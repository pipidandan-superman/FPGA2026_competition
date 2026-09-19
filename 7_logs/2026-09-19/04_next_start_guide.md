# 2026-09-19 下次启动指南（P0 收官后当前态）

## 第一步（会话开始时）

1. 读 [HANDOFF.md](../../../HANDOFF.md) 顶部节（P0 收官 + 深夜 run25）；
2. 读 `4_metrics/logs/2026-09-19_yolov8_p0_board_validation_run02/README.md`
   （P0-B 全门叙事）与 `1_docs/yolo_v8_mainline_baseline_20260919.md`（P0-A 合同）；
3. 核对 git：用户分支 `codex/full/pipidandan-superman` 应至 `d0a51a8`（P0-B 收官批）。
   注：`5de8ec7` 此前经 443 一次性 URL 推送**已达远端**，只是 raw-URL 推送不更新
   本地 origin 引用，一度显示 ahead-1——属陈旧引用假象，非丢推（本批 22 端口
   正常推送已刷新引用）。

## 主线状态（勿重做）

- **P0 整体收官**：P0-A 离线冻结（104-task schedule + 全哈希）+ **P0-B run02 板级
  全门 PASS**（在线性/身份/所有权/基线 Overlay CK1-CK5/CK_F 100 MHz/B1+B2
  smoke/恢复性；gate 值与 run23/24/25 逐位相同）。run01 在线性阻塞 fail-closed 留档。
- **B1+B2+频率门三收官**：run23 BOARD_B1_PASS（288/288）/ run24 BOARD_B2_PASS
  （DMA 回环全绿）/ **run25 BOARD_FREQ100_PASS**（FCLK0 真 100.000 MHz，全部
  gate 值与 50MHz 版逐位相同——无频率耦合缺陷）。
- **板上现挂**：P0 基线 = 100 MHz 版 GEMM+CSR+DMA 三从机 overlay
  （FPGA0_CLK_CTRL=0x00200500；P0-B run02 后挂载，板上目录 `~/p0b_run02/`）。
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

**P1/B3 真实 Conv0 的 DMA→GEMM→DDR→G0 golden——唯一挂起项（等用户授权）**。
四个决策点已呈用户：
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

## 本次全面审计补充

- `2026-09-19_project_status_audit_run01` 已完成，路径审计当前为 PASS。
- 用户分支 ahead-1 已查明为本地陈旧 remote-tracking 引用（443 一次性 URL 推送
  不更新本地 origin 引用；`5de8ec7` 实际早已达远端，`d0a51a8` 经 22 端口正常
  推送并刷新引用）；不要触碰主树 635 条既有未提交记录，也不要删除那 4 个未跟踪
  历史审计文本，除非用户明确授权。

## YOLOv8 主线启动顺序

1. （已完成 2026-09-19 深夜）权威文档统一至 P0 收官态。
2. 以 `axi_gemm_test` 为唯一主线，冻结 B3 DMA→GEMM→DDR 合同。
3. 用真实 Conv0 和 G0 golden 做第一个 B3 门，再做短子图、63 Conv+PPU 全网静态回放。
4. 依次进行固定图像板测、摄像头输入、HDMI/UDP 并发和动作闭环；每一级 PASS 才进入下一级。
5. 只在完整整网板测和长稳数据具备后发布 YOLOv8 板上 FPS、P95/P99 和任务成功率。

## P0 后的固定入口

- 读 `1_docs/yolo_v8_mainline_baseline_20260919.md` 和
  `4_metrics/logs/2026-09-19_yolov8_p0_mainline_convergence_run01/mainline_manifest.json`。
- **P0 已收官（P0-B run02 PASS，2026-09-19 深夜）**；下一门 = B3 真实 Conv0 的
  DMA→GEMM→DDR→G0 golden（桥接合同 4 决策点待用户授权）。
- 板级动作开始前需要用户物理上电；先通知用户，收到"已上电"确认后才执行任何
  物理板卡动作。

## P0 状态更正（用户纠正后）

此前的"P0 完成"标签已撤回。没有上电、没有下载、没有板级测试，就不能称为
P0 完成；下一会话必须以 P0-B 板级验证为入口，并为其建立独立不可变证据目录。
（2026-09-19 深夜更新：P0-B run02 已在独立证据目录全门 PASS，该入口完成。）

## P0-B 续接状态（已闭环）

run01 在线性阻塞（fail-closed 零写入留档）后，run02 已在用户再上电下一轮全门
PASS：在线性/身份/所有权/基线 Overlay CK1-CK5/CK_F 真 100 MHz/B1+B2 smoke
（gate 值与 run23/24/25 逐位相同）/恢复性全过。板上现挂 P0 基线。证据：
`4_metrics/logs/2026-09-19_yolov8_p0_board_validation_run02/`（run01 留档不删）。
