# udp_video 上位机工具 v1 交付（含本机自测）

日期：2026-09-08
交付：`3_host/udp_video/mock_sender.py`（模拟发送器）、`udp_video_rx.py`（接收端 v1）

## 自测结果（本机 127.0.0.1 闭环，30 fps，~5 s）

- 接收统计：ok_frames 递增正常（~29.7 fps），lost_frames=0，crc_err=0，dup=0，bad_header=0，short=0，bad_geom=0
- 判定：`HOST_RX_LOCALHOST_SELFTEST_PASS`
- 边界：cv2.imshow 显示路径未在本环境验证（无 GUI 会话），`python udp_video_rx.py` 带窗口由用户确认；解析/组包/CRC/统计链路已全部验证

## 用法

1. 纯 PC 自测：`python mock_sender.py --ip 127.0.0.1 --fps 30` + 另一窗口 `python udp_video_rx.py`
2. 对接板卡（板卡发送端就绪后）：`python mock_sender.py --ip 192.168.240.10 --fps 30`（先验证板卡回环）→ 板端发送真实数据后 `python udp_video_rx.py` 直接显示
3. 依赖：pip install numpy opencv-python（本机已装）

## 与设计文档的对应

- 头格式：`>4sBBH I HHHHHH II` = 设计文档 §4 的 32 B 头，逐字段一致
- 完整性：packet_count + EOF 标志 + CRC32 三重校验；不完整帧丢弃并计数
- 丢帧口径：相邻完整帧 frame_id 缺口；另有 dup/bad_header/short/bad_geom 分项
