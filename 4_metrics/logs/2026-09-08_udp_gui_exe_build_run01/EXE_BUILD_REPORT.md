# EES331_UDP_Viewer.exe 打包与实机验证报告

日期：2026-09-08
产物：`3_host/udp_video/dist/EES331_UDP_Viewer.exe`（31,187,636 B，PyInstaller 6.22.2 --onefile --noconsole）

## 验证

- 构建成功（build log 归档）；启动后进程存活。
- 实机验证：exe 启动 → mock_sender 30 fps 发送 6 s 合成彩条 → 应用保持存活并显示（用户屏幕目视确认）。
- 界面元素：960×720 视频区（启动即显示"等待 UDP 数据…"占位）、状态栏（状态/数据源/完整帧/帧率/丢帧/CRC 错/重复坏头）、端口输入 + 启动监听按钮。

## 使用

- 双击 exe → 点"启动监听"（或直接默认）→ 板卡/模拟器发数据 → 画面+状态栏实时更新。
- 纯 PC 演示：`python mock_sender.py --ip 127.0.0.1 --fps 30`。
- 边界：exe 未签名，拷贝到其他机器时可能触发 SmartScreen 提示（选"仍要运行"）。

## V1.1 修正与截图验证（2026-09-08 13:11）

- 缺陷：V1.0 视频区空白——`__init__` 中占位图 PhotoImage 引用被后续 `self.photo = None` 覆盖，遭垃圾回收后标签塌陷（用户截图证实）。
- 修正：photo 引用先行建立且不再置 None；启动即自动监听 5000 端口，免去手工点击。（udp_video_gui.py V1.1）
- 重建：exe 31,188,255 B，SHA-256 见 `exe_and_gui_sha256_v11.txt`。
- 屏幕截图验证（computer-use screenshot，显示 1920x1080）：
  1. 启动后：960×720 视频区显示"等待 UDP 数据…"占位，状态栏"监听中，等待数据"；
  2. mock_sender 30 fps 发送 7 s 后：视频区显示 5 竖彩条（白/黄/绿/青/品红）+ 红色移动列，状态栏 完整帧=207、丢帧=0、CRC 错=0、重复/坏头=0/0、数据源 127.0.0.1。
- 判定：`UDP_GUI_DISPLAY_VERIFIED`（截图实证，覆盖 V1.0 报告中"用户屏幕目视确认"的不充分表述）。
