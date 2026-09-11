# AMD AIPC 借用报告编制与验证

日期：2026-09-10。用户要求参照指定目录中的模板，编写符合当前工程的报告并保存在同目录。实际模板目录为 `E:/competition/1_docs/doc/`，未创建误写的 `1/_docs/doc`。

## 交付

- [AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx](<E:/competition/1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx>)。
- 输出 SHA256：`DC535EA60D83B79E10FFC81ED51C4AB4524B5B25B0363CBCF3170B7BD8823F7A`。
- 2 页，保留模板的 Letter 纵向、1英寸页边距、信息表字段、合并关系和总体两页形式。报告正文与总设计/任务流程图均改为 EES-331 当前项目。无文件发送或提交动作。
- 当前状态 `REPORT_DOCUMENT_QA_PASS_WITH_PENDING_FIELDS`。团队编号未独立确认，标为“待确认（模板编号4062）”；队长/学校/邮箱/电话/两位指导教师均“待补充”。机型暂按模板标为 `AMD RyzenAI 370（32G）拟申请`，未冒称用户已选择或设备已借到。已通过异步问题询问，交付时尚未收到回答。

## 模板解析与回退

原 DOCX：`E:/competition/1_docs/doc/AMD AIPC 借用报告 - 模板.docx`。
SHA256：`EBBC3F74BB0E42663E54245EFB0624AE4E692CF37F2110A5DE9AC75A6DCFEFA6`。原件保持不变。

1. 项目 MinerU wrapper直接解析DOCX，进程返回0但缺失Markdown和内容JSON，结果 `MINERU_PARSE_FAIL`。原始 `mineru_results.json`、API/stdout/stderr和runner日志保留，不以退出码冒充成功。
2. 已向用户披露回退：通过documents技能的 `render_docx.py` 将DOCX转换为PDF，仍用MinerU pipeline解析该PDF。转换属于格式预处理，不使用其他文本提取器替代MinerU语义解析。
3. PDF输入：`template_render/AMD AIPC 借用报告 - 模板.pdf`；SHA256 `3C8598A76C21692B8223D97C16CB7E0C5F094E979AA0D880A77B35D129842BD9`。
4. PDF解析run：`E:/competition/4_metrics/logs/2026-09-10_aipc_template_pdf_run01/`；marker `MINERU_PARSE_PASS`，Markdown/contentJSON均存在，2张图片。中文质量 `review`，原因 `short_text`；已阅读Markdown/JSON并人工核对模板两页PNG，表格字段、两页限制和示例结构完整。wrapper自身Fallback=false，而本任务层面明确是DOCX→PDF回退。
5. Markdown：[AMD AIPC 借用报告 - 模板.md](<E:/competition/4_metrics/logs/2026-09-10_aipc_template_pdf_run01/AMD AIPC 借用报告 - 模板/auto/AMD AIPC 借用报告 - 模板.md>)。
6. 内容JSON：[AMD AIPC 借用报告 - 模板_content_list.json](<E:/competition/4_metrics/logs/2026-09-10_aipc_template_pdf_run01/AMD AIPC 借用报告 - 模板/auto/AMD AIPC 借用报告 - 模板_content_list.json>)。

## 当前工程取材与事实边界

- `README.md`、`5_report/作品命名与简介.md`：队名“小月文刀队”、作品“锐眼·智行——具身智能分拣”、EES-331/Zynq-7020与Ryzen AI PC架构；README记录摄像头→VDMA→DDR→HDMI的可视化板测。
- `1_docs/设计方案_具身智能视觉分拣.md`：YOLOv8-n和视觉分拣方向作为拟定方案。旧简介将加速比、RTT等目标写成成果，报告不照搬这些未由当前实测闭环支持的数字。
- `1_docs/OV5640_PS以太网传输实施计划_2026-09-08.md`、`1_docs/OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md`：当前以太网/UDP路线仅作为拟实施方案，不写成已经完成。
- `3_host/model/MODEL.md`、`3_host/app/README.md`、`1_docs/interface.md` 当前仍为待填/模板，不能把其他主机旧记忆中的手势模型mAP或CPU时延用于本次申请实测结论。
- `4_metrics/logs/2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt` 与同日SD Builder报告/验证日志：只继承SD启动到Linux Shell以及启动包工具v0.2软件验证；摄像头完整PYNQ整合、网络/Jupyter、Overlay和机械臂联调明确待完成。
- 机械臂型号/接口未确认，因此按配套控制器实际协议接入，并提出超时、停止、急停与互锁设计目标；不承诺控制器不存在的能力，不描述为已实现。
- 机型遵循模板选项暂拟，不声称特定ROCm版本或任何GPU/NPU后端一定支持，要求到机后核对适配并保留CPU对照。

## 格式与包保留验证

- 执行合同 `artifact.md`；构建脚本 `create_report.py`；原模板结构读取 `template_xml_audit.txt`。
- 从原DOCX逐ZIP部件继承，只改 `word/document.xml` 和两张原示例图片。全部其余部件（含styles/theme/customXml/关系/字体/脚注等）字节保持一致，见 `package_audit.json` → `TEMPLATE_PACKAGE_PRESERVATION_PASS`。
- 标题使用原有Title样式并保持参考尺寸。将示例图的浮动锚定改为设计槽内的内联图，防止新版文字量增加后发生重叠；两个图均明确描述本项目的拟定总体链路。
- 最终 `render_and_diff.py` 结果 `fidelity_final/summary.json`：模板2页、输出2页；变动均为预定正文与图示槽。`template_sections.txt` 与 `final_sections.txt` 显示页尺寸、页边距、节数不变；style审计见对应JSON。
- 已逐页查看 `fidelity_final/b_render/page-1.png`、`page-2.png`；无表格裁切、文字重叠、缺字或额外空白页。信息表、正文和两张图均完整可读。图的替代文本标记本run的证据报告路径，供内部追溯。
- 原模板仍为原SHA256。未修改板卡文件/SD卡/冻结FPGA工程；未更改SD Builder工具。

## 可复现命令

使用workspace dependencies返回的Python运行 `create_report.py`，随后运行documents技能 `scripts/render_and_diff.py`、`scripts/section_audit.py` 和 `scripts/style_lint.py`。原始控制台 `fidelity_console.txt`。MinerU输入/命令均由项目wrapper记录。

提交申请前只需补齐身份信息、确认机型与团队编号；正文方案与工程状态已经完成编写。
