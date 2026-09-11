# EES-331 SD Builder 0.1

Windows 图形工具：强制导入含 bitstream 的 XSA，导出配套 SD 启动 ZIP 和可选整卡 IMG。第一版支持 EES-331 / xc7z020clg484-1 / Vivado-Vitis 2025.2 / PYNQ 3.0.1。

## 启动

已构建程序：`E:/competition/4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/distribution/EES331SDBootBuilder.exe`。双击即可打开；EXE 包含 Python/Tk 运行环境和已校验的板级基线资源，不需要另外安装 Python。

程序使用本机 Vitis 2025.2 的 Bootgen、DTC、XSCT、ARM 编译器，不将整个 Vitis 安装打进 EXE。默认工具目录为 `F:/vivado2025/2025.2/Vitis`，界面可更改。

完整 IMG 需要原版 `pynq_z2_v3.0.1.img`，默认位置为 `E:/competition/3_host/pynq/download/pynq_z2_v3.0.1.img`。程序验证其 SHA256 必须为 `f17405d25298a2c5ea23ccf95f868b42b18f819ff9d7fe5d079ac9ef53415861`。这是基础根文件系统来源，不要选择后来生成的 EES-331 IMG 作为本配置的基础镜像。

## 常用流程

1. Vivado 中生成 bitstream，执行 Export Hardware，并选择 Include bitstream，得到一个 `.xsa`。
2. 打开程序，选择该 XSA，点击“检查 XSA / 配置差异”。不接受单独 bit，也不接受不含位流的 XSA。
3. 选择 PL 加载方式：
   - **手动加载 PL**：默认。启动包携带 overlay.bit/overlay.hwh，Linux 起来后由应用按需加载，boot.py 不自动下载位流。
   - **Linux 启动后由 PYNQ 自动加载**：boot.py 执行 `Overlay('/boot/overlay.bit')`，配套同名 HWH；适用于独立 PYNQ Overlay。
   - **FSBL 阶段加载 PL**：BOOT 顺序为 FSBL→XSA位流→U-Boot→控制DTB，boot.py 不再次加载。
4. 按需勾选完整 IMG。PS 外设变化若需要设备树适配，在界面提供匹配的板级 DTB。
5. 点击“生成启动包”。成功后点击“打开输出目录”。新构建目录为 `E:/competition/4_metrics/logs/YYYY-MM-DD_sd_builder_HHMMSS_<id>/`。

## 输出

```text
<构建目录>/
  hardware_analysis.json        XSA 指纹、PS差异、器件信息
  build.log / command_*.log     完整工具输出
  fsbl_provenance.json          FSBL来源、初始化文件哈希
  boot_validation.json          BOOT头/分区/载荷校验
  boot/                         配套启动文件
  output/
    sd_boot_package.zip         boot/文件 + manifest +说明
    manifest.json
    result.json                 完整构建结果
    ees331_pynq_sd.img           选择完整镜像时生成
    ees331_pynq_sd.img.sha256
```

ZIP 中的 boot/ 文件应整套更新到 SD 启动分区。IMG 是包含分区表和根文件系统的整卡安装镜像，可直接交给烧录工具。程序本身不写 SD 卡。构建完成前输出保存在 `.pending-output`，失败构建保留日志，不生成最终 output/。

## 自动化能力和边界

- 同一个 XSA 提取 bit、HWH 和 ps7_init，避免手工混用多个工程文件；验证位流头部器件、长度、归档完整性和输入哈希。
- 以已启动的板级基线比较 PS 参数。PS 和初始化完全相同则可复用基线 FSBL；有变化则生成当前 XSA 的新平台/BSP，以 FSBL_DEBUG_INFO 重编。也可勾选强制重建验证流程。
- 当前 profile 固定 EES-331 的 UART1/MIO48..49/115200、SD0/MIO40..45、1GiB DDR 和 33.333333MHz 晶振。不兼容关键配置会被拒绝。
- FCLK/部分 AXI/EMIO GPIO 配置变化走现有板级描述路径；DT 中同步 FCLK 使能，PYNQ加载也使用 XSA 的 HWH 参数。
- **影响 PS 外设的其他变化需要匹配的新 DTB。** 工具会列出差异并停止，不能凭 XSA 推断 PHY 型号/复位连线、外部器件或 Linux 驱动。新 DTB 仍需按板级硬件与驱动约束适配，程序会核对基本 UART、DDR、PS 时钟和部分外设使能。
- `.bit` 与 `.hwh` 来自同一 XSA；新的 PL 设计是否满足时序、复位、AXI协议和软件驱动要求，必须实际验证。XSA 是工具输入，不是板级功能证明。
- 当前保持 PYNQ 3.0.1 的原 Linux 内核与根分区，不自动编译新内核/模块，也不自动生成任意 PL IP 的驱动或动态 `.dtbo`。需要内核驱动的新增 PL 外设应先完成相应驱动/设备树适配。第一版不是通用 Linux 发行版构建系统。
- 控制 DTB 与 Linux DTB 都在实际启动容器中更新；不以单独复制 system.dtb 假装适配已生效。当前 profile 对两者使用同一板级 DTB。
- BOOT 校验头校验和、FSBL加载长度、分区边界、ELF LOAD数据、U-Boot/DTB加载地址；FSBL模式还校验位流转换后的实际载荷。FIT 内核/DTB hash与内容独立校验。
- 完整 IMG 校验源镜像哈希、FAT双副本/文件链/内容、输出全部分块哈希，证明启动分区外所有字节不变。IMG不含已运行卡上的账户/网络/应用改动。

“SD_PACKAGE_STATIC_PASS”仅表示软件生成与文件校验通过。每个新 XSA 仍须冷启动、PL加载、寄存器、DMA和应用验收。已继承的原始板级基线只证明 SD→Linux Shell；网络、Jupyter和XRT/新Overlay的功能不能据此标记通过。

## 源码与命令行

源文件位于本目录：hardware.py（XSA预检）、builder.py（构建编排）、images.py（FAT/IMG）、fdt_reader.py（独立FDT读取）、app.py（GUI）。assets/ 是已验证基线资源与manifest。

安装 requirements.txt 到隔离 Python 环境后：

```powershell
python builder.py --xsa <含位流的XSA> --inspect
python builder.py --xsa <含位流的XSA> --mode linux --full-image
python builder.py --xsa <含位流的XSA> --mode fsbl --rebuild-fsbl
python app.py
```

EXE 已对GUI初始化/资源/依赖执行自检，也通过 `--build-config` 用实际XSA构建启动包。验证证据和样例配置见 `4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/`。

基线资源来源于同项目 `2026-09-10_sd_boot_fix_run01` 和已验证原版 PYNQ v3.0.1 镜像。U-Boot沿用原版二进制载荷，原FSBL来自本板XSA；相应源码/来源说明在先前修复run。程序不包含Vitis安装介质，资源原许可证不因工具封装而改变。
