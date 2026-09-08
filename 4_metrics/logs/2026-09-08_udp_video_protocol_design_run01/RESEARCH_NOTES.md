# 调研依据（2026-09-08，WebSearch）
1. CSDN 实测：Zynq 7020 裸机 lwIP UDP 吞吐 943.7 Mbps（RAW API）——千兆可行性依据
2. 红外期刊：ZYNQ 以太网红外图像系统——帧头+帧位置标志上位机组包（同构先例）
3. Hanspub：ZYNQ 水果识别——千兆自定义 UDP 协议至上位机（同构先例）
4. Tecphos EEVideo 规范——SOF/EOF 包模式（本设计用 flags bit0/bit1 等价实现，不设独立帧尾包）
5. ADI GMSL-Ethernet——一行一包 MTU 对齐思路
6. Xilinx Wiki Zynq-7000 Ethernet 基准方法——A1 阶段基准测试方法来源
7. RTP 对比（知乎/WebRTC 指南）——选型排除理由：裸 RGB 无标准 payload，播放器支持差
结论：自定义 32B 帧头方案与公开工程实践一致，维持实施计划 §5.2 设计并细化。
