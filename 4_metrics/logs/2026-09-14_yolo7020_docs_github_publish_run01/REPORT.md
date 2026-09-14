# YOLO7020 r3文档发布审计

日期：2026-09-14。范围：本轮完整硬件部署讨论、数据前置要求、公开v6下载结果及工程交接。发布目标为`codex/full/pipidandan-superman` → PR → `main`；另一成员审核必须满足。本报告初始状态为PUBLICATION_IN_PROGRESS，后续收据追加于此。

## 本轮修订

- [部署计划r3](../../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)：六阶段正式路线、GEMM/算子/调度、量化合同、golden、预算、视频隔离、阶段板测保留；补实际下载1893张与剩余准入门。
- [MODEL.md](../../../3_host/model/MODEL.md)：同步PS+PL目标，纠正test集可作校准的旧建议，历史精度不冒充本轮重测。
- [当天验证交接](../../../7_logs/2026-09-14/03_validation_summary.md)：四份日志保留过程事实，并以顶部最新状态消除旧登录/条款停点歧义。
- 下载报告发布版把本地独有ZIP/图片配置改为明示本地路径，保留验证JSON、逐图hash清单、脚本及原始输出。

## 边界和发布范围

仅发布清单中显式列出的MD、JSON、CSV、验证脚本与精选原始文本日志。模型profile、资源估计和旧r1/r2报告是历史证据，不重新执行也不改成当前PASS。ZIP、dataset图片/标签树、PT/ONNX、RTL/BIT/HWH及生成工程均不提交；临时签名URL和凭据不提交。

保留污染的主工作区，不切换或清理它；使用已有个人工作树，4个既存未跟踪历史txt保持原样。main基线91f3974已包含旧PR #6。无冻结2_fpga写入、无训练/量化/仿真/上板。回退通过针对本次文档提交的新revert PR，不改写历史。

原始审计见本目录preflight.log（本地保存，不发布完整污染路径清单）；发布文件清单、验证记录及Git收据分别记录在本目录。通过标准：文档事实与JSON相符、关键相对链接在发布树有效、无非范围或二进制暂存、diff --check通过、远端个人分支可确认、PR明确指向main。只有实际显示合并并经远端核对才记MERGED。

## 发布前验证结果

`DOCUMENT_VALIDATION_PASS`：r3的66项检查通过，13章节与14个本地链接正常，模型及r1快照hash不变，项目路径审计15项通过。r3 SHA-256为`772478ADA4E1D35E7237951E5A54336E18C859B325E9F5CF9552254305270835`。原始结果见[validation_console.log](validation_console.log)。

暂存41个显式文件，清单见[publication_files.txt](publication_files.txt)，无二进制、权重、dataset目录或2_fpga；diff --check通过，常见token/签名URL扫描无命中（不构成穷尽秘密审计）。8个精选.log被默认忽略，仅对清单内文件显式git add -f，不修改.gitignore。所有当前文档链接存在；只读r1原文快照有5个沿用原1_docs位置的相对链接，因此在归档位置不直接可点，其目标为同级历史部署分析run内summary.json、profile.json、conv_layers_320.csv、onnx_nodes.json、throughput_sensitivity.csv，均已发布。保留快照字节和hash，不为修链接篡改历史证据。
