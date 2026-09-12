# 来源与发布文件清单

本页用于区分随仓库提供的文档、已有仓库资料和仅在本机留存的原始证据。来源哈希用于定位输入，不代表对应硬件或算法已通过验收。

## 本次发布范围

| 文件 | 用途 | SHA-256 / 字节数 |
|---|---|---|
| [architecture.png](assets/amd_arm_2026-09-12/architecture.png) | 发布件 | `b7208becb2dc53eaa81394e7dde81b238b8a5b64d4a2852608659df632908742` / 150272 字节 |
| [geometry_and_states.png](assets/amd_arm_2026-09-12/geometry_and_states.png) | 发布件 | `87451c448965c656839e5da4a0afeabc61b726d7105756f37919ef779c4f0ab1` / 136481 字节 |
| [amd_topic2_redesign_2026-09-12.md](../amd_topic2_redesign_2026-09-12.md) | 修改链接前的原始 Markdown | `e97d6f11b5284c84830c5a5e3b20e59e29b24968391326bc9fdb5b454df71042` / 37823 字节 |
| [amd_arm_fpga_roadmap_2026-09-12.md](amd_arm_fpga_roadmap_2026-09-12.md) | 修改链接前的原始 Markdown | `a5afd875625722ac940a01288b00094fe1b483f94bfbd092d2aaac2f3c30b862` / 32764 字节 |
| [amd_arm_fpga_roadmap_2026-09-12.docx](amd_arm_fpga_roadmap_2026-09-12.docx) | 发布件 | `a82b01ddaadfb1865493434396001b3718f8014b33e81f365db2b33b8cc56cb7` / 336780 字节 |
| [amd_dual_model_arm_design_2026-09-12.md](amd_dual_model_arm_design_2026-09-12.md) | 双视角与PC/FPGA双模型新方案；GitHub发布件 | 原始归档SHA-256 `A968D675280F4B5FF626EED6D8CD182E2D19C7D6413FB948D5EC044D70FC689E` / 24827 字节；发布件因链接适配而不同 |

两张 PNG 为本项目生成的最终技术图，按原始字节复制。Word 大小约 0.34 MB，为用户要求的可编辑完整方案；只修改超链接关系，正文和嵌入图片与原始交付件一致。Markdown 发布后的哈希另存本机上传审计 manifest，避免自引用哈希。

## 已有仓库来源

- [1_docs/pdf/AMD赛题.pdf](../pdf/AMD赛题.pdf)
- [2_fpga/0_diaplay_test/pynq/camera.py](../../2_fpga/0_diaplay_test/pynq/camera.py)
- [3_host/model/MODEL.md](../../3_host/model/MODEL.md)
- [3_host/udp_video/udp_video_rx.py](../../3_host/udp_video/udp_video_rx.py)
- [4_metrics/logs/2026-09-11_pynq_camera_run01/REPORT.md](../../4_metrics/logs/2026-09-11_pynq_camera_run01/REPORT.md)
- [4_metrics/logs/2026-09-11_pynq_camera_run01/pc_final_status.json](../../4_metrics/logs/2026-09-11_pynq_camera_run01/pc_final_status.json)
- [9_pynq/sd/README.md](../../9_pynq/sd/README.md)

## 本机留存来源

以下资料未纳入本次文档提交。方案中的相应证据链接指向此处，是本机证据登记项，不是可在线下载的源报告。需要复核原始数据时，应在 E:/competition 打开下列路径。

## source-01

来源：`E:/competition/3_host/model_env/README.md`。

SHA-256：`1278dd1d6be4ac59a7af2283e4aec3f538f9ef3ee08e7991ab2eb22b99e2d6f0`；4147 字节。状态：仅本机留存，本次未上传。

## source-02

来源：`E:/competition/4_metrics/logs/2026-09-12_amd_arm_only_design_run01/report.md`。

SHA-256：`630cf7b157b4d0c325b6e053cdff22ccd742ac0b33d82ff6f3fafc9a31def96d`；7070 字节。状态：仅本机留存，本次未上传。

## source-03

来源：`E:/competition/4_metrics/logs/2026-09-12_amd_arm_only_design_run01/source_verification.json`。

SHA-256：`33a14e2af1943b2fb320aabe67aa7d01afb04c28f7b61731343ac5d294ed7f82`；864 字节。状态：仅本机留存，本次未上传。

## source-04

来源：`E:/competition/4_metrics/logs/2026-09-12_amd_topic2_redesign_run01/report.md`。

SHA-256：`593f196c429115dabd100eec16a3860109e7cd370ffcd8b09d88fa7e89c5fa43`；7213 字节。状态：仅本机留存，本次未上传。

## source-05

来源：`E:/competition/4_metrics/logs/2026-09-12_model_env_run01/REPORT.md`。

SHA-256：`0a1096f6bdf35e39e608537d92c273418f1e4d79bf26de06f56b5b38b95ef03e`；3565 字节。状态：仅本机留存，本次未上传。

## source-06

来源：`E:/competition/4_metrics/logs/2026-09-12_amd_dual_model_design_run01/research_record.md`。

SHA-256：`829E971D5C4E0F5C792CC945A14FDD7401FBDE9D7D2B35E5FBB267378706BA68`；4047 字节。状态：仅本机留存，记录双模型方案的来源边界与排除项，本次未上传。

## source-07

来源：`E:/competition/4_metrics/logs/2026-09-07_vivado_full_build_run01/post_build_outputs/impl_1/display_test_wrapper_utilization_placed.rpt`。

SHA-256：`E9CA94C4FCA485F2190A25BC9D1272CED4D747E42BCB033F47C620C4D6053972`；16898 字节。状态：仅本机留存的历史placed资源报告；未证明与当前运行位流一致，本次未上传。

## source-08

来源：`E:/competition/4_metrics/logs/2026-09-09_amd_sait_pynq_mineru_run01/AMD赛题/auto/AMD赛题.md`。

SHA-256：`1FDE4DA8CDBB23D900F5177481B11AAE4220097B6F4064028CA2FBC25D1B2F93`；56849 字节。状态：仅本机留存的MinerU Markdown；仓库已有原始赛题PDF，本次未上传解析产物。

## source-09

来源：`E:/competition/4_metrics/logs/2026-09-09_amd_sait_pynq_mineru_run01/AMD赛题/auto/AMD赛题_content_list.json`。

SHA-256：`1F0138FE23DCA11615CCBA1372E68F6810C0B4498F46CBD2CFBE4452CD52CFF7`；146078 字节。状态：仅本机留存的 MinerU content JSON；本次未上传解析产物。

## 赛题解析与验收边界

赛题输入为 1_docs/pdf/AMD赛题.pdf，SHA-256 为 C6AD82ACD4F7BDCD13BD412E232ED85D05F2A87DD5E2CDD04F9D219F88B569FC。前述方案撰写阶段复用同 SHA 的 MinerU pipeline 结果 MINERU_PARSE_PASS，中文质量 pass、无回退；完整解析路径为 4_metrics/logs/2026-09-09_amd_sait_pynq_mineru_run01/AMD赛题/auto/AMD赛题.md 与同目录 AMD赛题_content_list.json。此处登记既有来源，本次上传未重新解析或进行硬件验收。

本次双模型方案 Git 审计原始记录位于 E:/competition/4_metrics/logs/2026-09-12_amd_dual_model_github_run01；日记索引位于 7_logs/2026-09-12/03_validation_summary.md。未批量上传原始运行目录、模型环境、用户硬件照片、渲染临时文件或冻结工程。
