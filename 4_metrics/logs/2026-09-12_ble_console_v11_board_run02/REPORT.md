# BLE Console v1.1 实机复测

结果：BLE_CONSOLE_V11_WORKER_BOARD_PASS；冻结 EXE GUI 双向字节核对 PASS。

用户确认重新上电并下载 ble_uart_debug_top.bit 后测试；没有改 FPGA、AT参数或配对。
所有连接前后配对状态均为 false。

- [worker_board_events.json](worker_board_events.json)：新版 GUI 使用的 BleWorker 公共队列，
  三次无缓存名称读取、约6.375秒准备校验、自动 FFE1 通知；三轮双向各18字节一致，
  ready_hold_s=60.5，最终无缓存名称读取成功，最后主动断开。
- [worker_board_console.log](worker_board_console.log) /
  [worker_board_debug.log](worker_board_debug.log)：完整输出。
- [validate_worker_live.py](validate_worker_live.py)、
  [serial_rpc.ps1](serial_rpc.ps1)：测试脚本及 COM4/9600/8N1 helper，退出码0。
- [exe_session_snapshot.jsonl](exe_session_snapshot.jsonl)：发布 v1.1.0 EXE 真实窗口会话，
  22:40:01.237 校验完成；22:40:47.518 TX=55AA3132，
  22:40:47.708 notification=AA553231。
- [exe_serial_console.log](exe_serial_console.log)：COM4 actual=expected=55AA3132，
  反向发送AA553231；与 EXE 会话逐字节对应。
- [validate_exe_serial.ps1](validate_exe_serial.ps1)：只在 COM4 接收已知测试字节，再返回已知字节，
  没有 AT 指令；结束释放 COM4。
- [exe_connected_duplex.png](exe_connected_duplex.png)：电脑操作技能捕获的实际窗口，
  “校验通过，可收发”、自动订阅和双向收发日志可见。

实际 EXE：
E:/competition/8_tools/EES331_BLE_Console_v1.1/EES331_BLE_Console.exe。
SHA-256：82BDD94C77F2090A4A4086EB10D6706443BDE21E216B02AB93A87DD5E0C93381。

这是短时分方向收发测试；不代表正式B1长期/满速/机械臂验收。
初次未广播记录保留在 [build run01](../2026-09-12_ble_console_v11_run01/REPORT.md)，
用户已说明当时尚未上电。
