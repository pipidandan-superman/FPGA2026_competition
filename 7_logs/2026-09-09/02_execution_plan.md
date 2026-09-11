# 2026-09-09 Execution Plan

## 执行顺序

1. 应用 `project-workspace-policy` 与 `daily-engineering-log` 技能，确认根路径 `E:\competition`。
2. 定位赛题 PDF 并计算 SHA-256；确认旧 MinerU 产物 `1_docs/pdf/amd_sait题_mineru/parsed/` 为空，判定不可复用。
3. 运行 `E:\competition\.codex\skills\mineru-doc-reader\scripts\run_mineru_pipeline.ps1`：
   - `-InputPath "E:\competition\1_docs\pdf\AMD赛题.pdf"`
   - `-OutputDir "E:\competition\4_metrics\logs\2026-09-09_amd_sait_pynq_mineru_run01"`
4. 校验 marker、manifest、results、Markdown、content JSON、中文质量。
5. 检索 Markdown 中全部 "PYNQ" 命中行，通读相关段落（平台介绍、3.2 具身智能赛道、3.3 初级组推荐方向）。
6. 对照本队方案 `1_docs/设计方案_具身智能视觉分拣.md`（赛题 3.2，EES-331/Zynq-7020 + Ryzen AI PC）给出结论。
7. 写入本日四文件，运行会话收尾审计脚本。

## 涉及工具/模块

- MinerU 本地 pipeline 后端、mineru-api（127.0.0.1:58120）。
- 输入：`1_docs/pdf/AMD赛题.pdf`（SHA-256 `C6AD82ACD4F7BDCD13BD412E232ED85D05F2A87DD5E2CDD04F9D219F88B569FC`）。

## 任务 2 执行顺序（同日追加：部署计划）

1. 检查 2026-09-08 既有 MinerU 运行 `2026-09-08_eth_zynq_psw_check_mineru_run01`：输入 SHA-256 与当前 `EES-331 User Guide.pdf` 一致（`27C26F39...B3F5949`）、marker=`MINERU_PARSE_PASS`、Markdown 与 content JSON 齐全 → 满足复用条件，向用户披露复用，不重新解析。
2. 从复用产物提取板卡事实：Zynq-7020 CLG484-1、1GB DDR3 MT41K256M16 RE-15E、SD0 启动（SW8=0,0,1,1,0,x）、ENET0 PHY 88E1518（MIO16~27/MDIO 52/53）、UART1 MIO48/49、USB OTG（JP6/JP7）。
3. 联网核实方案选型事实：PYNQ-Z2 PHY 为 Realtek RTL8211E-VL（与 88E1518 不同，设备树必改）；PYNQ v3.0.1 为 Zynq-7000 最新官方镜像代（Ubuntu 22.04 / 2022.2 工具链 / sdbuild 需填 prebuilt）。
4. 对照 `Zynq_PS7_Config_Report.md`（冻结工程仅使能 UART1，ENET/SDIO/USB 未开 → 部署需新建 PS 配置，不可直接复用冻结 XSA）。
5. 撰写并写入 `1_docs/doc/EES-331_PYNQ从零部署计划_2026-09-09.md`：可行性对比表、路线 A/B/C、阶段 0~5（各含 PASS 判据）、必改项清单、风险登记表、赛题对应关系、证据纪律。

## 风险与回退

- MinerU 失败：保留 API 日志、写 `MINERU_PARSE_FAIL`，不得改用临时 PDF 抽取冒充 MinerU 结果。
- 旧产物复用风险：仅凭文件名相同不可复用；本次已按空目录事实判定重新解析。
- 部署计划技术风险（DDR/PHY/FIT 重打包等）：已在计划文档第 6 节风险登记表列明，本会话不执行硬件动作。
