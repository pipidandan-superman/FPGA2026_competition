# EES-331 SD Builder v0.2 交付验证

2026-09-10。用户授权保留旧版并生成新版，修正原版 PYNQ-Z2 入口和 PS/设备树工作流。

## 交付结果

- 软件结果：`V02_RELEASE_PACKAGE_PASS`。程序 [EES331SDBootBuilder_v0.2.exe](E:/competition/8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe)，完整工具包 [EES331_SD_Builder_v0.2.zip](E:/competition/8_tools/sd_start_tool_v0.2/EES331_SD_Builder_v0.2.zip)。
- 源码：[sd_boot_builder_v02/README.md](E:/competition/3_host/pynq/sd_boot_builder_v02/README.md)。EXE 22,776,980 字节，SHA256 `b4a2b971432dd91f70fc27a54e5f78670f3ac5ffb8c6b38cfbbb6843034a0a6e`；ZIP 29,694,632 字节，SHA256 `8e2452c366ade42f44bf96b4a06216ed023c3d0d313f89854de64d9adca53a40`。
- v0.1 的 19 个源文件/资产/EXE/ZIP 哈希全部未变：`v01_preservation_result.json` → `V01_PRESERVATION_PASS`。原 `8_tools/sd_start_tool/` 也保留并核对，详见 `v01_tools_preserved_hashes.json`、`release_result.json`。
- 未修改 `2_fpga/`，未写入物理 SD 卡。本次所有新输出的板级状态为 `NOT_TESTED`。

## 修正内容

1. 完整 IMG 的默认输入和哈希从原版 PYNQ-Z2 切换为已适配 EES-331 的固定基础 IMG；界面不再出现原版 PYNQ-Z2 入口。错误原版 IMG 明确拒绝。
2. 从 XSA + 固定板级模板自动生成 PS 设备树；常规外设变化不再统一要求手工 DTB。DTB 完整覆盖移到默认折叠的高级设置；未知外接从设备、复位/供电、SD1/GEM1/USB1 等列出具体缺项。
3. 保持含位流 XSA 强制输入；兼容实际 Vivado 导出的辅助 SmartConnect HWH，选择唯一包含 PS7 的系统 HWH，拒绝多个系统 HWH。
4. PS 参数或初始化变化时生成新 FSBL/BSP；三种 PL 加载模式附中文说明。USB0 角色可选择，需配合 JP6/JP7。
5. 高级页展开导致底部截断的问题已修复为可滚动页面；真实 EXE 默认页面和滚动到底部均检查，见 `gui_default.png`、`gui_advanced.png`。
6. 完整 IMG 的临时 FAT 文件转存构建 work/，最终 output/ 不再包含该中间文件。

## 验证与原始记录

| 验证 | 结果与证据 |
|---|---|
| 22 项规则/输入/GUI 测试 | PASS，`test_v02.py`、`tests_release_console.txt`。涵盖 UART0、USB0/复位46、QSPI、I2C总线频率、SPI片选、CAN外部时钟、SD卡检测、FCLK/GPIO、外设禁用、缺位流、错误电压、错误基础镜像、辅助/歧义HWH、真实未开SD的XSA拒绝 |
| DTC 真编译与反编译 | `dt_tests/` 各案例的 DTS/DTB/日志及独立句柄、控制器状态校验。外设变化为合成 PS 参数测试，不是这些新配置的板级验收 |
| 参考 XSA 手动启动包 | `2026-09-10_sd_builder_v02_173836_5d93b4`，BOOT/FIT/ZIP PASS |
| 最终后端整卡 IMG + FSBL/BSP 强制重建 | `2026-09-10_sd_builder_v02_175423_0bb6c6`，`full_build_result.json`、`full_build_console_v2.txt`；来源 `REGENERATED_FROM_INPUT_XSA`；完整镜像读回与根分区不变 PASS |
| EXE 自检 | `frozen_self_test_final.json` → `FROZEN_GUI_SELF_TEST_PASS`；最终冻结日志 `pyinstaller_final_console.txt` |
| EXE 手动模式构建 | `frozen_build_config.json.result.json`，`2026-09-10_sd_builder_v02_175742_16fccb` → `SD_PACKAGE_STATIC_PASS` |
| 最终 EXE FSBL 模式构建 | `frozen_fsbl_config.json.result.json`，`2026-09-10_sd_builder_v02_180104_171c99` → `SD_PACKAGE_STATIC_PASS`，四个 BOOT 分区及真实位流载荷匹配 |
| 交付压缩包 | `package_release.py`、`package_release_console.txt`、`release_result.json`；ZIP CRC、EXE内容哈希、交付目录副本一致 |
| 路径审计 | `skill_path_audit_console.txt` → `pass=true` |

参考输入：`E:/competition/2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa`，SHA256 `b3343e2161fdfc4aa744a211e65059346ae48e0f7ea5f1b41b945e4f9124576a`。

实际显示 XSA `2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa` 含两个 HWH。修正解析后确认其 SD0 禁用且无 MIO40..45 路由，因此拒绝作为 SD 启动输入；见 `alternate_xsa_rejection.txt`。没有修改这个 XSA，也没有用合成 XSA 冒充真实硬件构建通过。

本轮最新完整测试 IMG：[ees331_pynq_sd.img](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_175423_0bb6c6/output/ees331_pynq_sd.img)，7,858,807,808 字节，SHA256 `ae016a04126cb61a9893cf01e565135c5c49b5479ea75570d83b48917cd38eab`。PL 加载方式为 Linux 后自动加载，使用参考最小 XSA；它是软件验证样例，不代表用户未来 PL 工程已适配或已通过板测。早期 `174532_932baf` 构建也通过，但其 output/ 含临时 FAT，最终验证以上述 `175423_0bb6c6` 为准。

## 基础 IMG 与板级证据

固定基础 IMG：`E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img`；SHA256 `203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`。该 7.86 GB 文件保留在原处，未重复塞入工具 ZIP。EXE 在当前主机自动定位；移机时放在 EXE 同目录或通过高级设置选择。

已复用 MinerU 历史通过结果，复用前已核对手册当前 SHA256，详见 [mineru_reuse.json](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/mineru_reuse.json)：

- 结果 `MINERU_PARSE_PASS`；输入 `E:/competition/1_docs/pdf/EES-331 User Guide.pdf`；SHA256 `27C26F39F3E35132A89FAE2155FA23575E850B0A22E3D9DC64FD73186B3F5949`。
- Markdown：[EES-331 User Guide.md](<E:/competition/4_metrics/logs/2026-09-08_eth_zynq_psw_check_mineru_run01/EES-331 User Guide/auto/EES-331 User Guide.md>)，85,454 字节。
- 内容 JSON：[EES-331 User Guide_content_list.json](<E:/competition/4_metrics/logs/2026-09-08_eth_zynq_psw_check_mineru_run01/EES-331 User Guide/auto/EES-331 User Guide_content_list.json>)，413 项。
- 质量 `pass`，无 fallback。据此补充 UART0/1、USB0 ULPI与复位、QSPI 型号/接线等板级规则；PHY0 地址及现有 GEM 信息同时采用工程基线/历史 UART。`sdt_probe/` 是工具链生成能力探测，未直接用作 Linux 设备树。
- USB/PHY 属性核对来源副本为 `usb_nop_binding.yaml` 与 `ethernet_phy_binding.yaml`；`usb_nop_binding.txt` 为失败探测的 404 文件，不用作证据。

## 限制和下次验收

当前保留 Linux 5.15/PYNQ 3.0.1 内核、根分区和 U-Boot 载荷，不自动新增任意内核驱动/PL dtbo。XSA 能描述控制器，但无法完整推导板外 I2C/SPI 从设备、供电和业务驱动；这类配置仍需具体补充。

历史 UART 只证明旧适配启动链到 Linux Shell。v0.2 增加 PHY 复位属性及自动 DT 规则后，应重新冷启动验证串口、SD、网络、实际启用外设及 PL/DMA/应用。此前的 U-Boot PHY读取、随机MAC、zocl IRQ/Jupyter问题不能宣称已经修复或验收。v0.1 及已启动镜像保留作对照。
