# EES-331 工作区基线收敛报告

## 结论

工作区已按 EES-331 板卡基线收敛。当前保留两条可复现链路：

- Vitis/JTAG：`2_fpga/0_diaplay_test/release/ees331_vitis_board_pass/`
- PYNQ/SD：`9_pynq/sd/01_base_ees331` 最小系统和 `02_integrated_camera_hdmi_udp` 板测成功业务镜像

用户提供的 PC UDP 动态画面已归档为 `pynq_udp_board_pass.png`。

## 清理结果

- 顶层 Cygwin 下载缓存、`.Xil`、`dfx_runtime.txt` 已移入回收站。
- 28 个旧 SD Builder 运行目录、旧 Builder 工具、通用 PYNQ-Z2 下载镜像、阶段性 FPGA 工程已移入回收站。
- 失败/重复 IMG、中间 root/boot 分区、PyInstaller/Cygwin/测试文件系统和 Vivado/Vitis 可再生成缓存已移入回收站。
- 当前正式文档入口新增 `1_docs/README.md`；发布目录新增 `2_fpga/0_diaplay_test/release/README.md`。
- 当前 v0.2.2 EXE 已按新 EES-331 基线路径重建，自检 `FROZEN_GUI_SELF_TEST_PASS`。

## 保留文件

- PYNQ 成功镜像 SHA-256：`8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`
- EES-331 最小系统 SHA-256：`203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`
- Builder v0.2.2 SHA-256：`b104e7ca7fcdf54d80382195c9374a459f71f68c62fa2593fe1cc4ec7ad5760b`

详细回收路径见 `recycled_paths.txt`，清理前体积见 `top_level_sizes_before.txt`。回收站方式保留恢复能力，复现确认后再决定是否清空。
