# Template execution contract

Reference: E:/competition/1_docs/doc/AMD AIPC 借用报告 - 模板.docx
SHA256 EBBC3F74BB0E42663E54245EFB0624AE4E692CF37F2110A5DE9AC75A6DCFEFA6.
Reference render: template_render/page-1.png and page-2.png; two pages, one section.
Primary semantic source: converted PDF parsed by MinerU in ../2026-09-10_aipc_template_pdf_run01. Direct DOCX parse failed; PDF parse passed with short_text review warning, manually checked against both pages.

## Page and styles

Retain US Letter portrait 12240 x 15840 twips, all margins 1440, header/footer720, one column. Retain source table grid 1265/1424/2333/1594/2734 twips, border0.5pt black, source merged metadata cells, one table with eight rows and merged first design column across rows6/7. No header/footer, fields or content controls; footnote/endnote parts are empty boilerplate and preserve-only.
Normal source style1: 12pt, theme minor Latin Aptos and Chinese 等线, paragraph after8pt, line278/240. Table narrative direct11pt, after2pt, line252/240. Short labels bold; centered title12pt bold. Use existing Title style12 with direct size12pt to retain reference scale. No decorative rule. Editable narrative uses source11pt pattern, black.
Metadata rows retain source minimum heights405, expanding as needed. Source row7 minimum3873 can expand; add cantSplit to put narrative/diagrams together on page2. Left merged label uses compact11pt to avoid isolated last character. Replace example floating diagrams with inline images inside their editable slot to avoid overlap; same two-component diagram purpose, system architecture plus closed-loop workflow. New images use black headings and pale blue boxes with clearly labelled planned links.

## Slot map

word/document.xml body/p[1]: title, remove 模板 marker.
body/tbl[1]/tr[1]/tc[2]: team number, pending confirmation; don't silently treat template4062 as verified.
tr[2]/tc[2]: project name from current project README, 锐眼·智行——具身智能分拣.
tr[3..5]: leader/school/email/phone/teachers input fields, pending user details.
tr[6]/tc[2]: requested AIPC model, use current template37032G as provisional only until user reply; tc[3] becomes concise borrowing need/config note.
tr[7]/tc[2]: application objective, hardware split, borrowing purpose, verified status and planned tasks. Template hint text replaced.
tr[8]/tc[2]: detailed model/interfaces/feedback/protection, borrowing milestones, validation plan and two diagrams. Clone source narrative paragraph for added content. Source example must be fully removed from body and images.
Personal fields may remain explicitly 待补充. No invented identity, measured ML results, competition scores, precise runtime support or borrowed-machine receipt.

## Package preservation

Only document.xml and media/image1.png, media/image2.png editable. Relationships, styles, themes, font tables, settings, customXml, footnotes/endnotes, properties and all remaining ZIP entries preserve byte-for-byte. Original reference hash unchanged. Inventory emitted by authoring script. Need table/section audit, <=2page render, all pages visual checked, no clipped cells or misleading project claims.

## Source precedence

Current README verifies project/team and frozen camera/VDMA/HDMI visual baseline. Current SD Builder report and actual UART establish only SD-to-Linux-shell and software packaging. Older project description's acceleration/RTT/closed-loop numbers are design targets, not measured outcomes. Model docs are placeholders; do not present memory-only YOLO/gesture metrics as current results. Control actuator type and protocol remain to be selected. Plan external arm via documented controller, not direct raw motor drive; keep room for actual selection.
