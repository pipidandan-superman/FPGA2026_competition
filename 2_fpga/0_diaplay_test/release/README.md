# EES-331 已验证发布文件

`ees331_vitis_board_pass/` 保存当前 EES-331 Vitis/JTAG 板测基线所需的固定输出：XSA、BIT、HWH、应用 ELF 和 FSBL。对应 SHA-256 位于同目录 `SHA256.json`。

工程源码、XPR、BD、RTL 和 Vitis 应用源码仍保留在上级目录。Vivado `.cache/.gen/.runs/.sim/.hw/ip_user_files`、Vitis 平台导出树和应用 build 目录属于可再生成缓存，已在发布文件固化后清理。

PYNQ/SD 业务镜像位于 `E:/competition/9_pynq/sd`，不放入本目录。当前 PYNQ 板测成功镜像为 `ees331_pynq_sd_20260911_222654.img`。
