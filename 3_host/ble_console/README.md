# EES331 BLE Console

## v1.1：已验证直连流程进入 GUI

2026-09-12 本地交付完成：31项离线/Tk测试、冻结EXE自检通过；
新版后端三轮双向各18字节、ready后60.5秒保持通过；实际发布EXE连接及发送按钮
另行完成55AA3132/AA553231双向核对。新包位于8_tools/EES331_BLE_Console_v1.1，
旧包保留。用户已另行手动确认双向通信；此为短时验证，不替代长期通信验收。
后续应用户要求上传源码、说明与精选证据；提交范围与结果见
[v1.1发布记录](../../4_metrics/logs/2026-09-12_ble_v11_publish_run01/REPORT.md)。

默认启用 MLT-BT05 未配对门控：重新扫描目标、只读检查配对状态、显式
`pair=False` 与 `use_cached_services=False`、三次无缓存 GAP 设备名读取和
每轮 2 秒保持、检查配置的透传特征、自动订阅通知，最后才发出可收发事件。
禁止通过缓存枚举结果或单次连接返回值宣称校验通过。已有配对只提示人工处理，
不自动配对/移除配对，不改 AT 配置。取消推荐选项为通用 GATT，明确不标为 MLT 校验通过。
后端对连接/IO 设置超时，支持取消、主动断开回调过滤和旧会话排队 IO 作废；
异常断连停止循环发送，不自动重放命令。

新增配置是向后兼容的 version=1 可选字段 `verified_direct` / `auto_notify`。
新版源码离线及本地实机尝试以
[v1.1 验证记录](../../4_metrics/logs/2026-09-12_ble_console_v11_run01/REPORT.md)
为准；不能把下文早先独立脚本的板测自动记作新版 EXE 已验收。

Windows BLE GATT上位机源码。目标设备默认为板载MLT-BT05，但设备地址、名称过滤、
Service UUID、Write UUID、Notify UUID、写响应方式、数据格式、行结束符、超时与循环
发送周期均可在GUI中即时修改，并保存到用户配置目录。

## 功能边界

- 扫描BLE广播并显示名称、地址和RSSI；
- 使用Windows系统蓝牙适配器连接BLE设备；
- 动态枚举全部GATT服务、特征UUID和属性；
- 支持HEX/UTF-8写入、Write With/Without Response、读取和通知订阅；
- 支持可配置循环发送和JSON指令预置；
- 保存逐事件JSONL日志，便于后期机械臂协议分析；
- 后端、数据编解码和GUI解耦，后续可增加机械臂协议插件或PS/PL控制协议。

本程序不能在BLE已连接时直接修改MLT-BT05的名称、PIN、波特率或角色。这些属于
模块AT参数，必须由PL-UART配置桥在断开状态发送相应AT指令；GUI中对此有明确提示。

## 实机确认

最新状态：2026-09-12独立测试使用同一Bleak/WinRT环境，在新PL电平桥上完成11轮
双向字节核对，连接61.703秒、每方向166字节全部一致，结束主动断开。经用户授权
移除目标Windows配对后以未配对GATT完成测试；不是Windows PIN配对稳定性证明。
详见[实测报告](../../4_metrics/logs/2026-09-12_ble_bridge_duplex_run01/REPORT.md)和
[无需ILA的串口桥操作](使用说明.md)。下段是早期枚举证据，不能替代最新范围说明。

本次分支交付包括源码、测试与构建入口；打包EXE和依赖目录仍为本地交付，不随此次
日志更新重复上传。构建脚本要求全新BuildRun和空ReleaseRoot，禁止覆盖已有本地发布包。

2026-09-12已通过Windows WinRT后端连接地址`6A:C2:D2:F2:1B:5D`。实测透传服务为
FFE0，透传特征FFE1同时具有`read`、`write`、`write-without-response`和`notify`
属性，枚举MTU为23。该结果证明扫描、连接与能力枚举通过；实际PC到PL、PL到PC字节
传输仍应分别配合ILA和通知日志验收。

18:25更新：该板卡在未配对状态下已通过3次实际设备名读取和单字节55的带响应GATT
写入，PL侧仍需ILA确认。使用时直接扫描并连接，无需在Windows添加设备窗口猜PIN。
此前加密配对状态发生快速断连，配对状态变化后恢复；精确安全/密钥原因尚未确定。

## 开发运行

```powershell
python -m pip install -r requirements.in
python app.py
```

离线单元测试：

```powershell
python -m unittest discover -s tests -v
```

只读扫描、连接和服务枚举：

```powershell
python probe.py --address 6A:C2:D2:F2:1B:5D
```

## 发布构建

构建必须使用新的项目证据目录，脚本拒绝覆盖已有环境、构建目录或非空发布目录：

```powershell
powershell -ExecutionPolicy Bypass -File `
  E:\competition\3_host\ble_console\build_ble_console.ps1 `
  -BuildRun E:\competition\4_metrics\logs\2026-09-12_ble_host_tool_build_run01
```

发布目标固定为 `E:\competition\8_tools\EES331_BLE_Console_v1.1`，旧版不覆盖。
可以传 `-OfflineWheelhouse <已有wheelhouse路径>`，复制固定依赖到新 run，
在全新 venv 中离线安装；版本清单与 wheel/package SHA-256 保存在 BuildRun。
