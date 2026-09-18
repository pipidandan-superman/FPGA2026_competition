# 2026-09-18 下次启动指南

## YOLO PL CSR 子系统（当前主线）
先读 `4_metrics/logs/2026-09-18_yolo_csr_bd_board_run01/board_verify_r1.log`
——**板级 r1 全绿 BOARD_CSR_PASS**（2026-09-18 10:29）。

刚完成（勿重做）：合同仿真 81/81；BD 集成 run4 PASS；bit 4,045,696 B
（WNS=+11.168 / WHS=+0.027，真 BRAM：desc=4×RAMB36 + ring=1）；
skill 固化 vivado-bd-bitstream（通用，6_skill）；
**板级 L1+L2 验证通过**：下载真实（zocl 新 UUID 6574abd2 锁定），
ID=0x594F4C32 / VERSION=0x0300 / STATUS=0x11(IDLE+DESC_EMPTY 健康)，
MODEL_ID 与 BUF 窗口(0x3000) 写读回全对——**首写类安全，M13 判别通过**
（旧毒 fabric 任何 GP0 写即死机，新设计读写全通）。
overlay skill 两副本（6_skill + .claude/skills）已同步补：phys_addr 键名、
Windows ssh 三引号坑、sudo \r 毒化、50MHz FREQ_HZ 事实、七步正典。

板级 5 级检查进度：L1 身份读 ✅、L2 表窗口读写 ✅；
L3 门铃小帧全链（对照 TB T4 金标准）待做；
L4 溢出/协议错路径（SLVERR 子进程防 SIGBUS）；L5 性能（叠 Conv 后）。

第一步（具体操作）：L3 门铃测试——PS 经 DESC_WIN(0x1000) 写入 1 条
最小描述符，DESC_DOORBELL(0x114) 敲铃，轮询 SCHED_STATUS/DESC_HEAD/
DONE_COUNT，结果环 RING_WIN(0x6000) 回读。写前置/后置双通道标记
（board_load_verify.py 模式复用）。跑前问用户确认轮次。

刚开始时不要做：不要重构已验证 RTL；不要把 63 Conv 引擎、HP 口、
DDR 通路混进本轮 BD 改动；不要动 axi_action(0x43C0_0000)。

成功标准：L3 门铃帧描述符走完 DONE_COUNT+1 且结果环数据与金标准一致。

阻塞：无。GUI 进程随会话变化（重启后需重查 PID）。

下一步之后：code-review skill 审 RTL；PS 端驱动化；再叠 Conv 引擎。

## YOLO 量化审查线（背景）
先阅读本日验证摘要和 [软件量化审查报告](../../1_docs/yolo_quant_software_audit_20260918.md)。
禁止直接修改/构建冻结 2_fpga，禁止以FakePL或仿真通过代替板测通过。
成功标准：后续硬件逐层复现 63 Conv 和三尺度 raw head；先修正评估器并确认测试集精度门。
当前待办：对 Right、Thumbs Down、Left 做逐图量化误差分析；必要时重新校准/QAT；不要把当前 valid 改善视为最终精度通过。
