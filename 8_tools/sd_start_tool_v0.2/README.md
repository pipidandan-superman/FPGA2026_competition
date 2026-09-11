# EES-331 SD Builder v0.2

Windows 工具：输入 Vivado 2025.2 导出的 **含 bitstream 的 XSA**，自动生成 EES-331 的配套 SD 启动 ZIP，可同时导出整卡 IMG。v0.1 源码、EXE 和 ZIP 独立保留，本版源码在 `3_host/pynq/sd_boot_builder_v02/`。

## 打开与使用

程序：`E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/distribution/EES331SDBootBuilder_v0.2.exe`。EXE 自带 Python/Tk 和板级资源，不需单独装 Python。本机仍需 Vitis 2025.2 的 Bootgen、DTC、XSCT 与 ARM GCC，默认目录 `F:/vivado2025/2025.2/Vitis`，可在高级设置中调整。

1. Vivado 生成 bitstream，Export Hardware 时勾选 Include bitstream。
2. 选择 XSA，点击“检查 XSA / 配置差异”。单独 bit、不含位流、错误器件或不兼容启动引脚均拒绝。XSA 有多个 HWH 时自动选择唯一包含 PS7 的系统 HWH；辅助 SmartConnect HWH 不再导致误拒绝。
3. 选择 PL 加载方式，下方直接显示该模式说明。
4. 默认从 **XSA + EES-331 板级模板** 生成设备树。USB0 启用时选择 otg/host/peripheral，需与实际 JP6/JP7 及接线一致。
5. 需要整卡安装文件时保留“同时输出完整 .img”。只更新已有兼容 SD 系统的启动分区时可仅导出 ZIP。
6. 点击“生成启动包”，成功后打开输出目录。

高级设置默认折叠，包含工具目录、EES-331 基础 IMG 定位、完整 DTB 手动覆盖和强制重建 FSBL。**一般情况下 DTB 留空**。

## 基础镜像已改为 EES-331

v0.2 不再要求原版 PYNQ-Z2 镜像。完整 IMG 只接受已经完成本板启动适配的固定基线：

- 文件：`E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img`
- 大小：7,858,807,808 字节（约 7.32 GiB）。
- SHA256：`203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`。

程序先检查分区布局、EES-331 设备树身份，再计算整个 IMG 的 SHA256。原版 PYNQ-Z2 镜像以及未登记的新镜像会被拒绝。该基线保留 PYNQ 的 Linux 内核和根文件系统，启动链已针对 EES-331 适配；它是安装镜像，不包含首次启动后用户的账户、网络或业务改动。

7.86 GB 基础 IMG 不重复放入应用 ZIP。本机自动定位现有文件；换电脑时可把上述同名 IMG 放在 EXE 旁，或在高级设置中选择它。生成的新版 IMG 不用作下一次构建的基础镜像。

## 三种 PL 加载方式

| 方式 | 加载时机 | 输出行为 |
|---|---|---|
| 手动加载（默认） | Linux 启动后，由应用调用 PYNQ Overlay | 携带 overlay.bit/hwh，boot.py 不下载 PL |
| Linux 后自动加载 | PYNQ 启动钩子运行时 | boot.py 调用 Overlay('/boot/overlay.bit')；不自动启动业务程序 |
| FSBL 加载 | U-Boot/Linux 之前 | BOOT.BIN 包含 XSA 位流，启动顺序为 FSBL → PL → U-Boot → 控制 DTB |

新增 PL IP 如果必须由 Linux 内核在启动时探测，需配套完整设备树、驱动及合适的早期加载方式。仅携带 bit/hwh 不等于 Linux 驱动适配完成。

## PS 自动适配范围

Zynq IP 确定 PS 控制器、MIO/EMIO、时钟和 DDR 初始化；板级模板补充 XSA 不能表达完整的板上外部器件与 Linux 属性。

- 固定启动条件：xc7z020clg484-1、UART1/MIO48..49/115200、SD0/MIO40..45、1 GiB/32 bit DDR3、33.333333 MHz 晶振及本板 Bank 电压；不兼容的配置明确拒绝。
- 自动更新 UART0/1、SD0、GEM0、USB0、QSPI、I2C0/1、SPI0/1、CAN0/1、WDT 等控制器状态；TTC 内部时基保留。
- 板载 GEM0 使用已登记 PHY0、MIO47 复位；USB0 使用 ULPI/MIO28..39、MIO46 复位和界面选择的角色；QSPI 描述板载单片 N25Q256A。
- SD0 支持卡检测使能/关闭的对应描述；FCLK 使能与 EMIO GPIO 宽度从 XSA 同步。
- EMIO I2C/SPI/CAN 可生成控制器节点。I2C 总线默认 100 kHz；不将 PS 输入时钟误当作总线 SCL。
- PS 参数或初始化变化自动生成新平台/BSP并重编带调试打印的 FSBL；相同时可复用已启动基线 FSBL，高级选项允许强制重建。

**外接 I2C/SPI 从设备、CAN 收发器控制、SD1/USB1/GEM1、额外供电或复位等信息仍可能需要补充。** 工具列出具体缺项，允许提供完整高级 DTB，并校验启动条件和控制器状态；不会把任意 PS 改动都归类为必须手工 DTB。覆盖 DTB 按原内容使用，不再套自动生成规则，USB 角色也以覆盖文件为准。

本版使用与保留的 Linux 5.15 内核配套的 DT 模板和规则，由 DTC 编译。不是将新版 SDT 原样当作 Linux DT，也不是通用 PetaLinux 构建器。不会自动编译新内核/模块、生成任意 PL IP 驱动或动态 dtbo。未知硬件连接不能仅凭 XSA 推断。

## 输出与校验

每次构建写入独立的 `E:/competition/4_metrics/logs/YYYY-MM-DD_sd_builder_v02_HHMMSS_<id>/`：

- `hardware_analysis.json`：XSA/bit/HWH 指纹、PS 差异及板级缺项。
- `device_tree_generation.json`：自动/覆盖模式、控制器和句柄校验。
- `fsbl_provenance.json`、`boot_validation.json`、`build.log`、`command_*.log`：真实工具输出和校验记录。
- `boot/`：配套 BOOT.BIN、image.ub、system.dtb、boot.scr、boot.py、REVISION、overlay.bit/hwh。
- `output/sd_boot_package.zip`、`manifest.json`、`result.json`。
- 选择整卡导出时增加 `output/ees331_pynq_sd.img`、SHA256 文件、镜像读回与分块校验记录。

BOOT 中的控制 DTB 与 FIT 内 Linux DTB 同步更新。检查 BOOT 头/分区/ELF 实际载荷、FIT 数据/hash、ZIP CRC 和文件 hash；FSBL 模式额外验证实际位流载荷。完整 IMG 双 FAT/文件内容和全文件读回通过，并验证启动分区外字节不变。

构建完成前存于 .pending-output，所有选定检查通过才发布 output；失败构建只留诊断记录。程序不写物理 SD 卡。ZIP 的 boot/ 文件应作为一套更新，勿混用旧 BOOT 与新 FIT。IMG 可交给烧录软件作为整卡安装镜像。

## 验证边界与版本保留

`SD_PACKAGE_STATIC_PASS` 表示构建和文件检查成功，不表示已经在板上验证。当前历史基线 UART 已证明 SD → FSBL → U-Boot → Linux Shell；网络/Jupyter和新 PL 应用仍需独立验收。v0.2 新增 PHY 复位和设备树规则的输出也需要重新冷启动验证，不能继承旧版的板级 PASS。

v0.1 保留位置：
- 源码：`E:/competition/3_host/pynq/sd_boot_builder/`
- EXE/ZIP：`E:/competition/4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/distribution/`

v0.2 的测试、FSBL 重建、整卡读回、EXE 验证和旧版哈希核对见 `E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/REPORT.md`。

## 源码运行

安装 requirements.txt 到隔离 Python 环境后，在本目录运行：

```powershell
python builder.py --xsa <含位流的XSA> --inspect
python builder.py --xsa <含位流的XSA> --mode linux --full-image
python builder.py --xsa <含位流的XSA> --mode fsbl --rebuild-fsbl
python app.py
```

board_profile.py 管理板级规则，hardware.py 解析 XSA，builder.py 编排构建，images.py 校验/封装 IMG，app.py 为界面。assets/ 的每个资源均校验 SHA256。

基线资源来自同项目的 SD 修复记录及 PYNQ 3.0.1。U-Boot 沿用原有二进制载荷，FSBL 可按当前 XSA 重编；资源原许可证不因工具封装而改变，应用不包含 Vitis 安装介质。
