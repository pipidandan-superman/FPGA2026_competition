EES-331 的旧 SD 启动载荷缺少有效 FSBL 加载头和完整启动链，并使用不匹配的 PYNQ-Z2 设备树。本次归档修复到 Linux Shell 的证据，同时交付输入含 bitstream XSA 即可生成启动包的 SD Builder v0.2，并保留 v0.1。

范围：`3_host/pynq/sd_boot_builder*` 源码及必需资产、`8_tools/sd_start_tool*` 两版 EXE、`1_docs/doc` AIPC 模板/成品与部署计划、9 月 9/10 日四件套、README/HANDOFF，以及明确精选的 `4_metrics/logs` 证据。每个文件的大小、SHA-256 和来源见 `4_metrics/logs/2026-09-10_session_archive_upload_run01/selected_manifest.json`，二进制收录理由见同目录 `binary_manifest.md`、`REPORT.md`。多 GB IMG、重复 ZIP、构建缓存和波形不上传。

验证：旧基线原始 UART 证明 SD→FSBL→U-Boot→Linux Shell；v0.2 已有 22 项规则测试、真实 FSBL/BSP 重建、EXE 构建和整卡读回证据。本次归档核对精选文件、两版资产和 v0.2 发布源码哈希，并在交付 worktree 运行两版 EXE 自检通过。路径审计通过，暂存范围无 `2_fpga`。文档空白检查通过；已验证发行物和原始日志保留原始 CRLF/空白，完整 diff --check 的提示记录为已知归档特性，未改动资产来消除提示。

边界：新工具输出未上板，Linux 网络/Jupyter/新 Overlay、最终机械臂闭环尚待验收。远程已有 9 月 8 日裸机 UDP 与 BGR 板测结论保留。AIPC 报告已完成两页 QA，但人员/团队编号/机型等字段待确认，未向外提交。

冻结 BIT/XSA/ELF/source 没有修改、重编或上板；只读复制一份 313,220 B 的参考 XSA 到归档目录用于追溯。原工作区的其他未提交改动和索引保留。回退使用保留的旧工具和基础镜像；Git 回退通过新提交处理，不改写历史。合并 main 前需另一成员审核。
