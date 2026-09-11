# EES-331 SD Builder v0.2.1 PYNQ 应用整合报告

日期：2026-09-11

## 目标

在 SD Builder v0.2 基础上增加可选的完整 IMG rootfs 注入能力，把已经板测的 EES-331 OV5640 → HDMI + UDP PYNQ 应用、网络配置、CMA 参数和 systemd 服务整合进镜像。

## 输入契约

- 器件：`xc7z020clg484-1`
- XSA SHA256：`d69fb256b66106da87514fc3821fe177bbe538c128e74485f43a4a265f092ebc`
- bit SHA256：`0518c46b4dca4dca83b1e94ae5c1e8cbc8bb68fbf4537e5a90c025a10b76db87`
- HWH SHA256：`96eeba65209e66ac3e05a65907f48cc374dab490b9d88e2e72e22689e939a4dd`
- 基础 IMG SHA256：`203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`
- ext4 工具：Cygwin `debugfs.exe` / `e2fsck.exe` 1.44.5

## 实现

- 新增 `rootfs.py`，解析 IMG 分区、提取 ext4 根分区并通过 debugfs 注入文件。
- 写入 `/home/xilinx/ees331_camera`、网络配置和 systemd 服务。
- 创建 `multi-user.target.wants/ees331-camera.service` 相对符号链接。
- FAT 启动分区写入 `uEnv.txt`，设置 `cma=128M@0x10000000`。
- 写入前后执行 `e2fsck -fn`；逐文件 dump 回读并比较 SHA256。
- 修改后的根分区写回 IMG，再做完整 IMG 分块读回与 SHA256。
- GUI 新增“整合 EES-331 摄像头 PYNQ 应用”和 debugfs 高级路径。
- 整合模式只允许完整 IMG 和 `manual` PL 模式，由 systemd 唯一加载 Overlay。

## 模块验证

- 小型 128 MiB ext4 注入测试：`ROOTFS_MODULE_TEST_PASS`
- 12 个目标文件逐项读回一致。
- systemd 相对链接读回正确。
- e2fsck 前后检查通过。
- 错误 XSA 拒绝测试：`WRONG_XSA_REJECT_PASS`
- 证据：
  - `rootfs_module_test_console_final.txt`
  - `rootfs_module_test_result.json`
  - `rootfs_application_validation.json`
  - `rootfs_debugfs_write.log`
  - `rootfs_debugfs_readback.log`
  - `rootfs_e2fsck_before.log`
  - `rootfs_e2fsck_after.log`

## 源码版完整构建

运行目录：

`E:/competition/4_metrics/logs/2026-09-11_sd_builder_v02_220217_3f0ee9`

结果：

- `SD_PACKAGE_STATIC_PASS`
- `PYNQ_ROOTFS_INJECTION_PASS`
- 完整 IMG、启动分区、rootfs 应用和分块读回通过。
- 输出 IMG SHA256：`752f26f543308d396716ba3aa5879536d55d94612b93109199f4b2af24eb926b`

## EXE 首次失败与根因

首次打包 EXE 的完整构建运行目录：

`E:/competition/4_metrics/logs/2026-09-11_sd_builder_v02_220613_158787`

失败原文：

`工具链未生成当前 XSA 的 FSBL BSP。`

该失败没有记为 PASS。根因是 clean worktree 漏带已经验证的 PyInstaller 单文件 Tcl/DLL 隔离处理。冻结 EXE 的 `_MEIPASS` DLL/Tcl 环境污染了外部 Vitis 2025.2 XSCT，导致 FSBL BSP 未生成。

修复：

- 外部 Vitis 工具运行前调用 `SetDllDirectoryW(None)`；
- 调用结束后恢复冻结程序 DLL 目录；
- XSCT 子进程环境移除 `TCL_LIBRARY`、`TCLLIBPATH`、`TCLLIBRARY`、`TCLLIB`。

## 最终 EXE 验证

发布文件：

`E:/competition/8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.1.exe`

- 大小：22,520,487 字节
- SHA256：`c2966e6fa52bfb8786c0232221e4eb540b96b383406be1e38d581bf3a070f49a`
- GUI 自检：`FROZEN_GUI_SELF_TEST_PASS`
- 自检记录：`exe_self_test_final.json`

最终 EXE 完整构建运行目录：

`E:/competition/4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce`

暂存审计曾发现内置应用文件存在多余 EOF 空行。为保持 `git diff --check`、源码哈希、EXE 内嵌资源和完整 IMG 一致，规范化这些文本后更新应用 manifest，重新打包 EXE，并重新执行本节的完整 IMG 构建；没有沿用规范化之前的 EXE/IMG 作为最终发布物。

结果：

- `SD_PACKAGE_STATIC_PASS`
- `tool_version = 0.2.1`
- `rootfs_unchanged = false`
- `full_readback = PASS`
- `boot_files = PASS`
- `pynq_application = PASS`
- `hardware_status = REQUIRES_COLD_BOOT_VALIDATION`

最终整合 IMG：

`E:/competition/4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce/output/ees331_pynq_sd.img`

- 大小：7,858,807,808 字节
- SHA256：`8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`

完整 IMG 不进入 Git。

## 写卡工具

- 安装器：`E:/competition/8_tools/win32diskimager-1.0.0-install.exe`
- 大小：12,567,188 字节
- SHA256：`a51c9fc75c9caa44df03502838f229a70d484963f54675c241799093a59d8874`

Win32DiskImager 只负责把完整 IMG 写入 SD 卡；XSA 解析、FSBL/启动包生成和 ext4 注入由 Builder 完成。

## 结论与边界

结果：`SD_BUILDER_V021_PYNQ_INTEGRATION_STATIC_PASS`

源码版和冻结 EXE 均已完成完整 IMG 的离线生成、注入和读回验证。最终 IMG 尚未写入 SD 卡，也未执行物理断电冷启动、HDMI 和 UDP/PC 联合实测，因此不能声明该新 IMG 已通过整卡板级验收。下一步必须用 Win32DiskImager 写入备用 SD 卡并执行冷启动验收。

## 最终静态检查

- Builder Python 语法检查通过：`app.py`、`board_profile.py`、`builder.py`、`fdt_reader.py`、`hardware.py`、`images.py`、`rootfs.py`。
- UDP 协议测试实际入口为 `2_fpga/0_diaplay_test/pynq/test_protocol.py`，3 项测试通过。
- 首次误从 `3_host/udp_video` 调用测试文件，因路径不存在退出；该结果属于测试入口错误，随后已定位真实文件并通过。
- rootfs 模块复测：`ROOTFS_MODULE_TEST_PASS`。
- 错误 XSA 应用契约复测：`WRONG_XSA_REJECT_PASS`，原始输出见 `wrong_xsa_rejection.txt`。
- `git diff --check` 通过。
- `audit_project_skill_paths.ps1` 返回 `pass: true`。
