# SD Builder v0.2.2 自定义输出目录

用户请求：在现有应用程序指定 SD 部署包输出路径。

界面增加“部署包输出目录”输入和目录选择器；CLI 支持 --output-dir；JSON 支持 output_dir，旧配置默认行为兼容。构建证据与临时文件保留在项目证据目录，复制验证后的部署文件至所选父目录下的唯一子目录。复制过程逐文件 SHA256 读回，通过后发布，不覆盖既有包。测试目标含中文与空格。更正示例配置摄像头 XSA 路径和 integrate_pynq 参数键。

## 验证

- 5 项输出功能测试通过：默认目录、中文空格路径与重复发布、已有文件路径拒绝、读回错误不发布、冻结工程路径拒绝。
- 首次测试脚本用系统 GBK 读取 UTF-8 JSON 失败；改为显式 UTF-8 后全部通过。原失败输出 test_output_dir.txt 保留，最终输出 test_output_dir_final.txt。
- 冻结 EXE 自检：FROZEN_GUI_SELF_TEST_PASS，self_test.json。
- 最终 EXE 真实构建：SD_PACKAGE_STATIC_PASS，包含 FSBL/BSP 重建及 PYNQ rootfs 注入。
- 构建记录：E:/competition/4_metrics/logs/2026-09-11_sd_builder_v02_224206_ba86f2。
- 自定义目录：E:/competition/4_metrics/logs/2026-09-11_sd_builder_output_dir_run01/自定义 部署包/2026-09-11_sd_builder_v02_224206_ba86f2。
- 自定义复制读回：CUSTOM_OUTPUT_READBACK_PASS，export_validation.json。
- 完整 IMG 大小 7858807808 字节，SHA256 2ec71582c5cb066a9f6ae2b0735172c7414988e7cff98096ec00f0265921ab90。
- 新镜像没有写卡或冷启动板测，仍为 REQUIRES_COLD_BOOT_VALIDATION。

## 二进制发布声明

为用户提供无需安装 Python 的可运行 GUI，发布本机 PyInstaller 从本次源码打包的 EES331SDBootBuilder_v0.2.2.exe；来源为此目录 distribution，构建配置为 EES331SDBootBuilder_v0.2.2.spec，完整构建日志 pyinstaller.txt。大小 22520633 字节，SHA256 9402787351f333a6ba5c46b65970359c5485a8072465e3a310aaf0eb0049eb6a。v0.2.1 保留。源码、EXE、说明与精选结果上传个人分支；IMG、依赖和完整运行目录不上传。

输出到其他盘时，原构建盘仍保留完整产物及临时文件，目标盘另需部署包空间。故障 .pending-* 为未发布副本。此版不写物理 SD 卡。
