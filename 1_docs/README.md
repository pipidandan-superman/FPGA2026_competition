# 文档入口

## 当前控制开发计划（2026-09-12）

[EES-331蓝牙优先验证与AXI-Lite/BRAM开发方案](doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)：先验证板载蓝牙与Windows主机双向GATT，再实现控制寄存器、4KiB双口BRAM和LED闭环，后续接LeArm。状态为计划，尚未新增硬件实测。

本目录只保存正式设计文档、复现教程、接口定义和器件原始资料。构建日志、仿真输出、截图和 UART 等原始证据统一放在 `4_metrics/logs/<run-name>`；工程会话记录统一放在 `7_logs/YYYY-MM-DD`。

## 当前开发入口

- 总体方案：`设计方案_具身智能视觉分拣.md`
- 系统架构：`architecture.md`
- 硬件连接：`hardware_setup.md`
- 通信接口：`interface.md`
- PYNQ 从零复现：`PYNQ零基础开发与EES331摄像头工程实战.md`
- UDP 视频格式：`OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md`
- EES-331 HDMI 修正：`EES-331_HDMI显示适配修正方案.md`

## 原始资料

- ADV7511：`ADV7511_Hardware_Users_Guide/`
- OV5640：`ov5640/`
- 其他 PDF：`pdf/`
- Word/PDF 正式交付：`doc/`

历史解压包、自动提取文本、GitHub 上传草案和工具缓存不放在本目录。Git/GitHub 规则以 `.codex/skills/github-upload-policy/SKILL.md` 为准。
