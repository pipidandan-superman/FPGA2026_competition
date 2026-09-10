# EES-331 PYNQ 完整 IMG 与后续 PL 更新说明

## 交付与验证

完整镜像：`E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img`

- 大小：7,858,807,808 字节，约 7.32 GiB。
- SHA256：`203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`；同目录提供 `.img.sha256`。
- 结果：`FULL_IMG_PACKAGE_READBACK_PASS`，证据 `package_result.json`、`package_console.txt`、`fat_validation.json`、`block_verification.json`。
- 可直接作为 Win32DiskImager 等工具的整卡镜像输入，包含 MBR、启动分区和 Linux 根分区。目标卡实际容量须不小于上述字节数；当前使用的 16GB 卡满足。
- 基础是经 SHA256 复核的原版 `pynq_z2_v3.0.1.img`，合入此前修正并部署的 BOOT.BIN、image.ub、system.dtb、boot.py，保留 boot.scr 和 REVISION；六个文件独立 FAT 读回与此前部署清单完全一致。
- 启动分区外全部字节按分块 SHA256 对比保持不变，包括 MBR、分区间隙和整个 Linux 根分区。完成 IMG 全文件读回和总哈希。
- 此为可复现安装镜像，不包含板卡首次启动后产生的日志、扩容结果、账户配置、网络配置等运行状态。若以后需要保存已安装应用/环境的完整现场，应正常关机后读出那张 SD 卡，另存运行快照。
- 本轮未再次烧卡。新的 IMG 容器尚未重新烧录冷启动；它所包含的启动文件与用户已成功启动的版本一致。

## 用户串口证据：启动到 Linux Shell 通过

用户提供：`E:/competition/4_metrics/logs/2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt`。

本 run 保存原始字节副本 `uart_boot_evidence.txt`，SHA256 `6122200aecca6987ec22b638893e1d34b72ffb07543dc85f15cfc38fd92be98b`。

已核实：FSBL Release 2025.2/SD 模式 → SUCCESSFUL_HANDOFF → U-Boot 2022.01、1GiB、UART1 → FIT SHA1 校验通过 → EES-331 Linux 5.15.19 → `xilinx@pynq:~$`。本次阶段结论为 `SD_BOOT_TO_LINUX_SHELL_PASS`。

记录中尚有 U-Boot 的无有效环境区/使用默认环境、PHY ID 读取失败、SPI 探测失败；Linux 使用随机 MAC，尚无网络连通性/Jupyter验收。部分 FSBL 十进制调试计数显示异常，实际分区加载和交接通过，打印格式需另行定位；本次封装保留已启动版本，未混入未板测的新修复。以上不阻止已观察到的 SD/Linux Shell 启动，不应将其扩大为所有外设和 PYNQ 应用验收通过。

## 打包复现与工具边界

用户随后补充的串口粘贴从 FIT 加载开始，内核与 DTB 的 SHA1 都与封装版本一致，再次显示 UART1、1GiB、Linux Shell。原始内容归档 `uart_user_pasted.txt`，检查结果 `uart_pasted_review.json`。其中 `Starting Jupyter Notebook Server` 只证明启动任务被发起，没有证明服务就绪；随机 MAC、zocl IRQ缺失、regulatory.db/autofs4 警告作为后续问题保留，不据此否定已到 Shell 的启动结果。新粘贴不包含此前的 FSBL/U-Boot 横幅前段，完整前段仍由 uart_boot_evidence.txt 支持。

执行：`C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe -u E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/package_image.py`。

脚本拒绝覆盖已存在的输出。复现时在新的证据 run 中准备脚本/隔离依赖并调整记录位置。原版 IMG 始终只读。先抽出 FAT 分区，在副本内编辑，独立解析器验证文件/FAT双副本/文件链后才写出完整 IMG；主镜像没有任意 raw FAT 手工修补。

依赖：pyfatfs 1.1.0、fs 2.4.16、setuptools 80.9.0。fs 依赖旧 pkg_resources，隔离降至仍提供它的 setuptools，保留弃用警告。首两次分区副本试验分别暴露已有文件截断链问题、大小写匹配导致旧短文件名残留；均在主 IMG 创建前由异常或独立比较阻止，失败副本与日志保留为 `attempt01/02_failed`。最终流程按原始大写 8.3 名称删除旧文件后重新创建，精确验证只含六个预期文件，没有旧 IMAGE.UB 与 IMAGE~1.UB 共存。

## PL 变化时更新什么

当前 BOOT.BIN 是 FSBL + U-Boot + 控制 DTB，**没有 PL bitstream**。当前 boot.py 也不自动加载 PL。建议后续将 PL 作为独立 PYNQ Overlay 开发，保留当前可启动 PS 基线。

| 改动范围 | 通常更新 | 是否需要动启动镜像 |
|---|---|---|
| 仅 PL 内部 RTL、算法、流水线；PS 配置不变 | 同一次构建的 `设计名.bit` 和同名 `设计名.hwh` | 通常不需要 BOOT.BIN/image.ub/整卡 IMG |
| PL IP/AXI 地址/寄存器/中断/DMA 配置变化，使用 PYNQ Python 驱动 | `.bit` + `.hwh`，对应 Python 驱动/应用中的寄存器、尺寸、协议 | 通常不改启动文件；若有内核驱动拥有这些资源，按下一行处理 |
| 新增或修改由 Linux 内核驱动管理的 PL 外设 | `.bit` + `.hwh`；按驱动要求更新 `.dtbo` 或基础 DTB；缺驱动时补匹配内核的 `.ko` 或内核配置 | 动态 DT overlay 可避免修改基础 FIT；改基础 DTB 时重打 image.ub，改内核时同步内核/模块 |
| 仅 PYNQ 支持的运行时 FCLK 分频/使能、部分 AXI 端口参数 | `.bit` + `.hwh` 并验证加载时参数应用 | 不应一概重编 FSBL；PYNQ 会从 HWH 应用支持的时钟/端口设置 |
| DDR、MIO、UART/SD/USB/以太网等 PS 启动配置改变 | 从新设计导出 `.xsa`，重新生成对应 PS 初始化和 FSBL；更新相关控制/Linux DTB，重打 BOOT.BIN 和受影响的 image.ub | 需要复核启动链；不能只换 `.bit` 或手改一个独立 system.dtb |
| 要求上电时由 FSBL 配置 PL，而非 Linux 后加载 | 在 BIF 中加入匹配 `.bit`，按 FSBL→bitstream→U-Boot→控制DTB 顺序重打 BOOT.BIN；按资源使用更新 DT | 需要 BOOT.BIN；避免随后应用无意加载另一份不同位流 |
| 只改 Python/Notebook/上层应用 | `.py`/`.ipynb`/应用配置 | 不需重编硬件或启动镜像 |

`.xsa` 是导出硬件平台给 Vitis/软件生成工具的工件，不是拷到 SD 根目录就会被启动链自动读取的文件。`.hwh` 描述 IP、地址、中断、时钟等硬件元数据，应与 `.bit` 来自同一个设计版本；建议每次整套替换，避免旧 HWH 控制新硬件。

当前 boot.scr 走 FIT 启动。修改 Linux 基础 DTB 必须放入 **image.ub 内**并更新 FIT 哈希；修改影响 U-Boot 的时钟/UART/MMC等配置，还需同步 BOOT.BIN 中的控制 DTB。独立 `/boot/system.dtb` 的替换不会自动覆盖这两份内嵌 DTB。PL 专用动态 `.dtbo` 可以独立管理，不必机械同步到 U-Boot。

## 建议的日常开发交付

在板上使用应用目录，例如 `/home/xilinx/overlays/vita/`，保存 `vita.bit`、`vita.hwh`、应用脚本和一份版本/hash 清单；驱动需要时再增加 `vita.dtbo`。

```python
from pynq import Overlay
ol = Overlay('/home/xilinx/overlays/vita/vita.bit')
# 若需要动态设备树且驱动/资源已准备好：
# ol = Overlay('/home/xilinx/overlays/vita/vita.bit',
#              dtbo='/home/xilinx/overlays/vita/vita.dtbo')
```

加载前停止上一版本 DMA/中断/应用，涉及内核驱动时先释放设备和旧 DT overlay；加载后核对 IP 字典、地址、时钟与复位，再做小范围寄存器读写、DMA 单次传输、应用验证。当前为最小 PS 基线，新设计仍需核对 GP/HP、DDR访问、FCLK、复位和中断连接的兼容性。`2_fpga/` 冻结工程不因本说明获得修改授权。

每次 PL 调试可独立更新 Overlay，无须每次烧整卡；当 PS 配置/内核发生变化或形成稳定交付版本时，再更新启动文件并封装新 `.img`。

来源：PYNQ v3.0 [Overlay 设计文档](https://pynq.readthedocs.io/en/v3.0.0/overlay_design_methodology/overlay_design.html)（同名 bit/hwh、PS启动配置、运行时PL时钟）和 [设备树接口](https://pynq.readthedocs.io/en/v3.0.0/pynq_package/pynq.devicetree.html)。已保存 HTML；本地官方 PYNQ v3.0.1 源码包的 `pynq/overlay.py` 也已提取保存，确认 `Overlay(..., dtbo=...)`、加载时钟和设备树的路径。在线搜索接口不可用后改用官方文档直接下载，未依赖第三方摘录。
