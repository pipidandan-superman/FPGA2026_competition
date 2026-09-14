# model_datasets：AI 侧数据集归置目录

本目录集中存放已下载并完成结构校验的训练/评估数据集。数据本体（ZIP/图片/标签）仅本地保留，不上传 Git。

## 目录索引

- [dataset/](dataset/) — Hand Gesture v6（YOLOv8 格式，主训练/评估集，见下节）
- `hagrid-sample-500k-384p.zip` — HaGRID 384p 补充集（下载中，2026-09-14，见调研文档）
- [supplementary_dataset_survey_2026-09-14.md](supplementary_dataset_survey_2026-09-14.md) — 补充数据集调研与候选清单

## Hand Gesture v6（YOLOv8 格式）｜2026-09-14

- 原始 ZIP：`Hand_Gesture_v6_yolov8.zip` 已于 2026-09-14 应用户要求删除（节省空间）；SHA-256 留档供再下载比对：`89b828c8bfad60243f790d58d896b5189a7ac6f3c498629fdd931b8179e378b5`（29,538,322 字节）。注意：Roboflow 重新导出不保证字节一致，仅作参考
- 解压目录：`dataset/`（data.yaml + train/valid/test，各含 images/ 与 labels/），完整性已按归档清单核对（1893 图 + 1893 标签）
- 规模：1893 张 416×416，train 1765 / valid 59 / test 69；七类名称与编号顺序和 `3_host/model/MODEL.md` 当前模型一致
- 来源：Roboflow hand-gesture v6（CC BY 4.0，见包内 README.roboflow.txt）
- 校验：ZIP 全条目 CRC、路径安全、图片解码、标签格式全部通过，issue_count=0；证据在 [4_metrics/logs/2026-09-14_gesture_dataset_download_run01](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)
- 使用注意：包内 `data.yaml` 保持原样（相对路径 `../train` 等）；训练前应生成单独的本地路径配置并验证解析，不修改原始导出包；test 集保持独立，禁止用测试集调参
- 已知样本局限：valid 中 Stop 仅 1 框、Thumbs up/Thumbs Down 各 4 框，test 中 Stop 2 框、Thumbs Down 3 框；单类精度结论须注明样本量限制
