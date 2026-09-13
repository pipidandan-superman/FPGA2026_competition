# BLE Console v1.1 本地交付报告

时间：2026-09-12 22:42，工作区 E:/competition。结果：**BLE_CONSOLE_V11_DELIVERY_PASS**。

## 交付范围

- 源码：3_host/ble_console。用户要求将成功的未配对 GATT 流程同步至上位机。
- 新独立包：[EES331_BLE_Console.exe](../../../8_tools/EES331_BLE_Console_v1.1/EES331_BLE_Console.exe)；
  需连同整个 _internal 目录使用，不需安装 Python。
- EXE SHA-256：82BDD94C77F2090A4A4086EB10D6706443BDE21E216B02AB93A87DD5E0C93381。
- v1.0 旧包未覆盖，旧 EXE 哈希前后相同；冻结 2_fpga 未修改、未重新综合/下载。
- 本次仅本地交付，无新 Git push。之前 c101d87 的发布不包含本次 v1.1 修改。

## 已实现

重新扫描目标 BLEDevice；推荐模式在连接前后只读检查未配对状态；显式 pair=False、
use_cached_services=False；实际远端 GAP 名称读取三轮（use_cached=False，每轮保持2秒），
验证配置的服务和特征后自动订阅通知，最后才将 GUI 状态变为“校验通过，可收发”。
通用模式保留未来模块适配入口，不要求 MLT 名称、不宣称通过其门控。

已有 Windows 配对只提示由用户自行处理，不自动取消配对、不弹 PIN 请求、不更改模块 AT
参数。异常断连/IO失败停止周期发送，不自动重连、不重放旧会话排队命令。支持连接取消，
过滤主动断开产生的回调；订阅期间修改 UUID 后，停止订阅仍操作真实旧订阅。

## 验证与原始证据

1. [unit_tests.log](unit_tests.log)：新隔离环境中 **31 项 PASS**，含原编解码/配置、
   配对拒绝、名称错误、缺服务、通知失败、短连接、超时、取消、重复订阅、旧 IO 作废、
   旧配置迁移、Tk 控件门控/周期停止/真实订阅 UUID。
2. [build_console.log](build_console.log)、[pyinstaller.log](pyinstaller.log)、
   [exe_self_test.txt](exe_self_test.txt)：构建及冻结 EXE 自检 PASS version=1.1.0。
   Bleak 3.0.2、PyInstaller 6.22.2、WinRT 3.2.1；从前次 wheelhouse 复制到本 run，
   全新 venv 离线安装。完整依赖见 resolved_requirements.txt、wheel_sha256.txt。
   构建日志的缺少 objc 是 macOS 可选后端收集警告，本机 Windows WinRT 实际验证通过。
3. 首次 [worker_board_events.json](worker_board_events.json)：未找到目标广播，FAIL 保留；
   用户随后明确确认当时未上电/未下载 bit，不记作协议兼容性失败，更不伪记 PASS。
4. 用户上电、下载串口桥 bit 后，新版后端同一公共命令/事件队列重跑：
   [board run02](../2026-09-12_ble_console_v11_board_run02/REPORT.md)，
   三轮双向、每方向18字节一致，ready 后保持 **60.5秒**，最终无缓存读取通过，
   主动断开且串口 helper 退出0。
5. 实际发布 EXE 经 GUI 点击“连接”和“发送”，完成三次读取、自动订阅；
   EXE发55AA3132 → COM4收55AA3132，COM4发AA553231 → EXE通知AA553231。
   原始会话日志、串口对照和窗口截图均位于 board run02，不是仅用源码替代 EXE 验收。
6. [delivery_verification.json](delivery_verification.json)：独立检查上述事件、
   逐方向数据、旧版哈希和整个发布目录 manifest；PASS。
   [skill_path_audit.log](skill_path_audit.log)：13项路径审计 PASS。

## 复现

构建入口：3_host/ble_console/build_ble_console.ps1，BuildRun 必须为新的项目证据目录，
ReleaseRoot 固定 v1.1 且非空时拒绝覆盖。使用 -OfflineWheelhouse 指定现有 wheelhouse，
创建全新 venv。此次命令：

```powershell
& E:/competition/3_host/ble_console/build_ble_console.ps1 -BuildRun E:/competition/4_metrics/logs/2026-09-12_ble_console_v11_run01 -OfflineWheelhouse E:/competition/4_metrics/logs/2026-09-12_ble_host_tool_build_run02/wheelhouse
```

该命令为已执行证据，不能向同一 run 重建。source_before 是修改前快照；
source_final_hashes.json / release_sha256.txt 是最终源文件与发布文件清单。
界面操作方式见发布包 使用说明.md。

## 验收边界与交接

本轮使用项目工作区/日志技能保留冻结工程和四份规范日记；电脑操作技能仅用于新 EXE
界面验证。结论是新上位机已完成推荐直连接入和短时双向通信验证，不代表长期稳定性、
满速同时双工、B1每方向1000帧、机械臂兼容或安全控制链路验收。
交付时新 EXE 窗口保留并已连接，循环发送关闭，COM4 已释放。
下一步用户可直接操作新窗口；异常时保存 JSONL，不盲目改 PIN/恢复出厂。
