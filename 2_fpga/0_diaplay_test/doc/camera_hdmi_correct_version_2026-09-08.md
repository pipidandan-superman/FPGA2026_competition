# OV5640 摄像头 + HDMI 正确显示版本说明

## 版本状态

- 冻结标签：`camera-hdmi-visual-pass-20260907`
- 板级结论：`BOARD_VISUAL_PASS`
- 视频链路：OV5640 DVP → Video In to AXI4-Stream → VDMA S2MM → DDR → VDMA MM2S → Video Out/VTC → ADV7511 → HDMI
- 显示模式：640×480，摄像头实时画面经 HDMI 正常显示

该结论来自已归档的三张板级显示照片和冻结产物一致性检查，不等同于完整 UART 验收通过。

## 必须使用的冻结配对

以下三个产物必须成套使用，不能混用其他重新生成的 BIT、XSA 或 ELF：

| 产物 | SHA-256 |
|---|---|
| `display_test_wrapper.bit` | `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624` |
| `display_test_wrapper.xsa` | `7374BD4EE2D30C726FC0135E1960BA2BE19BD22C3B9D75B0AB0BBEE1CE64A6E1` |
| `app_component.elf` | `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990` |

冻结产物位于：

`4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/frozen_artifacts/`

## 上板操作要求

1. 下载冻结的 `display_test_wrapper.bit`。
2. 加载与其配套的 `app_component.elf`。
3. 完成传输后，手动执行一次摄像头采集复位。
4. 复位后再检查实时摄像头画面和 HDMI 输出。

当前板测经验表明，完成 BIT/ELF 传输后需要复位一次摄像头采集，画面才能正常显示。这是该冻结版本的必要恢复步骤，不应把复位前暂时无摄像头画面误判为版本失效。

## 必要工程文件范围

个人分支保留 `2_fpga/0_diaplay_test` 下的摄像头配置与采集 RTL、VDMA/视频链路 BD 和 XCI、HDMI/ADV7511 RTL、引脚约束、Vivado XPR、Vitis 应用源码及验证文档。`_ide`、BSP、平台缓存、综合/实现临时目录和其他自动生成树不属于源码交付范围。

`rtl/data_pre` 当前未连接到该摄像头 + HDMI 显示 BD，不作为此版本正常显示的依赖条件。

## 证据

- 冻结报告：`4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/CAMERA_DISPLAY_SUCCESS_FREEZE_REPORT.md`
- 产物清单：`4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/FROZEN_ARTIFACT_MANIFEST.sha256`
- 一致性审计：`4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/FREEZE_CONSISTENCY_AUDIT.txt`
- 板级照片：同一证据目录下的 `DISPLAY_SUCCESS_PHOTO_01.jpg` 至 `DISPLAY_SUCCESS_PHOTO_03.jpg`
