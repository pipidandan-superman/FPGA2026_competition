# 2026-09-11 验证摘要

[只读核查记录](../../4_metrics/logs/2026-09-11_sd_loading_explanation_run01/REPORT.md)。结果 SOURCE_REVIEW_COMPLETE。

已核实源码三模式、SD0硬门禁及板级规则；历史成功包为最小PS适配、完整Linux/PYNQ根文件系统、无默认PL加载。
验收标准：解释与源码及既有启动报告一致；不宣称本轮硬件PASS。未执行构建、写卡或板测。
命令：Get-Content、rg、Invoke-WebRequest读取官方PYNQ文档；audit_project_skill_paths.ps1校验路径规范。

## Builder 修复与真实验证
已修复 PyInstaller 单文件 EXE 临时目录导致 XSCT 加载错误 Tcl 8.6.12 的问题：外部 Vitis 工具运行前清除 DLL 目录覆盖，同时清理 TCL_LIBRARY/TCLLIBPATH 等变量。新版 EXE 在 `4_metrics/logs/2026-09-11_sd_builder_rebuild_run02/dist/` 打包成功。

使用 XSA `display_test_wrapper.xsa`（SHA256 `d69fb256b66106da87514fc3821fe177bbe538c128e74485f43a4a265f092ebc`）和 Vitis `F:/vivado2025/2025.2/Vitis` 运行真实 `--build-config`，结果 `SD_PACKAGE_STATIC_PASS`；FSBL/BSP、GCC、Bootgen、FIT 均完成。完整原始证据：`4_metrics/logs/2026-09-11_sd_builder_v02_191348_126b2e/`。


## 后续修复尝试
已定位 XSCT 继承宿主 Tcl 变量导致 8.6.12/8.6.13 冲突；已在 v0.2 源码构建 FSBL 前清除 TCL_LIBRARY/TCLLIBPATH 等变量，待用真实 XSA 重跑验证。

## PYNQ 摄像头迁移实时证据
[运行目录](../../4_metrics/logs/2026-09-11_pynq_camera_run01/) 保存用户启动日志、JTAG 截图、基线哈希、串口原文和 SSH 命令输出。
已从串口确认 SD/Linux shell；Marvell 88E1510 PHY，1 Gbps/Full。初始 ping 失败原因是 Linux 地址为 192.168.2.99，与 PC 子网不同，不是已证实 PHY 故障。增加临时 192.168.240.10 后板到 PC ping 2/2 成功，SSH 可用。
SD FAT 文件名显示为 OVERLAY.BIT/HWH；已复制到应用目录统一为小写配对文件。PYNQ 控制层尚待实测，不能把用户的 JTAG 画面记为本轮 PYNQ PASS。
摄像头 SCCB 和 ADV7511 配置在 PL 内完成；纠正此前答复中需要重新在 Python 配置 SCCB 的错误。

### PYNQ 迁移完成
结果：**PYNQ_CAMERA_HDMI_UDP_PASS / SD_REBOOT_AUTOSTART_PASS**。见[完整报告](../../4_metrics/logs/2026-09-11_pynq_camera_run01/REPORT.md)。
已在指定 `2_fpga/0_diaplay_test/pynq` 开发并部署至板卡 `/home/xilinx/ees331_camera`。修复了 sudo 下 XRT 环境丢失、FAT 大小写配对、CMA 超出 PL 地址窗口和开机时首次 S2MM 同步等待顺序。
120 秒联合测试发送 600 帧；用户确认 HDMI 与 PC 均正常并随动作变化。最终版本 SD 软件重启后自动恢复，PC 124.125 秒内记录 604 完整渲染帧，CRC/丢帧/坏头均 0；持续 VDMA 状态无错。首次重启失败及等待 1 秒未奏效的实验均保留原始日志，没有记为 PASS。
服务 `ees331-camera` enabled/active，板 192.168.240.10/24，PC 192.168.240.2:5000，默认发送 5 fps；结束时服务和证据版上位机保持运行。
原 XSA、main.c 和启动 BOOT.BIN/IMAGE.UB/BOOT.SCR 哈希均未改变。三个协议互操作/损坏/缺包测试和项目路径审计通过。未进行物理断电再上电测试；原构建 IMG/ZIP 未因本次部署重打包。

## 当前运行方式与上传门禁

对当前已经安装业务且未重刷的 SD 卡，操作流程是：SW8 保持 SD 启动，连接摄像头、HDMI 和网线后上电，PC 网卡设为 `192.168.240.2/24` 并打开 UDP 上位机，等待约 60 至 90 秒。板端无需人工命令。该结论由软件重启自动恢复和现场双路画面支撑；物理断电冷启动仍标记为待验收。

阶段成果上传审计目录：[`4_metrics/logs/2026-09-11_pynq_checkpoint_upload_run01`](../../4_metrics/logs/2026-09-11_pynq_checkpoint_upload_run01/)。本轮选择上传源码、部署配置、报告、结果 JSON、最终服务日志、PC 最终状态和协议测试；不上传完整 IMG、Overlay 二进制、板端压缩包、依赖目录或整包日志。

远端 `codex/full/pipidandan-superman` 确认包含本次提交之前，SD Builder 集成和 `1_docs` 教程均不开始。
