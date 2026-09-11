# PYNQ SD 镜像归档与文档整理报告

日期：2026-09-11

## 结果

- 已将原始 PYNQ 3.0.1 基础镜像归档到 `9_pynq/sd/01_base_pynq`。
- 已将用户实际写卡并验证成功的 222654 集成镜像归档到 `9_pynq/sd/02_integrated_camera_hdmi_udp`。
- 已归档与成功构建对应的启动分区镜像、7 MB 启动 ZIP 和应用/构建清单。
- 已计算归档 IMG 的 SHA-256，见 `images_hashes.txt` 和 `9_pynq/sd/manifests/images.json`。
- 已修订项目 README、PYNQ 教程、HANDOFF 和下一次复现指引，使其统一指向 222654 板测成功镜像。
- 未修改 `2_fpga` 冻结工程。

## 板测基线

源镜像：`4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce/output/ees331_pynq_sd.img`

归档镜像：`9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`

大小：7,858,807,808 字节

SHA-256：`8D22BCDE0268678050BCC1429BEE5ECADB0020E5CE3F5BA4DF7045066DEAFCCA`

用户确认：SD 启动正常，OV5640 配置完成 LED 点亮，HDMI 和 PC UDP 上位机均显示随动作变化的画面。首次 PC 零帧由网线未连接导致。

## 删除边界

清理前 IMG 清单见 `img_inventory_before.csv`。历史失败 IMG、重复完整 IMG 和 `work` 中间分区 IMG 已完成明确路径盘点，但本地自动安全审批拒绝了删除命令，因此本轮没有删除这些原始证据文件。归档结果不受影响；这些文件仍位于各自的 `4_metrics/logs` 历史运行目录。

## Git 上传边界

完整 7–8 GB IMG 和 136 MB 分区 IMG只在本机归档，不提交 Git。个人分支提交正式文档、`9_pynq/sd` 说明、哈希/构建清单和 7 MB 启动 ZIP。
