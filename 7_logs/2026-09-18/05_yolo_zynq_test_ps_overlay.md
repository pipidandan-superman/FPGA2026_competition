# yolo_zynq_test PS 最小系统 overlay 上板 run01（2026-09-18 下午）

用户新建纯 PS7 工程（proj/yolo_zynq_test，BD display_test），授权"直接上板"。
三关全绿：
1. Overlay 加载 PASS（PYNQ v3.0.1 正典，pl0→pl5，root 跑；非 root 死在
   Clocks.set_pl_clk 且位流未下——download() 先时钟后位流新钉死）；
2. UART PASS（COM6 双向全闭环，ttyPS0 为 PYNQ 自登录 bash）；
3. 网口 PASS（1000Mb 全双工零错，scp 4MB sha 一致）。
= 11 冻后首个干净加载，分步验证（S 级）干净基线确立。
回环辅件部署板 ~/overlay_test/（net_echo TCP+UDP:7777 在跑已自测；
uart_echo 须 stop getty，用户上位机自验用）。
证据：4_metrics/logs/2026-09-18_yolo_zynq_test_ps_overlay_run01/（README）。
skill 修正：ees331.md 补"PS-only overlay baseline and PYNQ load mechanics"段。
