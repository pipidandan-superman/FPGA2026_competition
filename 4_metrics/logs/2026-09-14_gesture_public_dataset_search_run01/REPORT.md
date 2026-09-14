# 七类手势公开数据检索

日期2026-09-14。范围：公开页面检索与本地MODEL.md对照；未下载归档、解析样本、训练或量化，未改部署计划/模型/RTL。

结果：PUBLIC_DATASET_PAGE_FOUND / DOWNLOAD_NOT_VERIFIED / DATASET_PACKAGE_NOT_AUDITED。

首选：[Hand Gesture项目](https://universe.roboflow.com/yolo-zxvpk/hand-gesture-r7qgb)，与本地MODEL.md记录的项目slug一致，页面列出七类Stop、Down、Left、Right、Thumbs Down、Thumbs up、Up，任务Object Detection，页面标示CC BY 4.0。这里只核对页面类别名，不替代实际data.yaml编号/标签语义审核。

[v6版本](https://universe.roboflow.com/yolo-zxvpk/hand-gesture-r7qgb/dataset/6)页面显示2011张：train1870、valid72、test69，支持YOLOv8格式，Auto-Orient和Stretch to416x416，训练增强为每例2份、亮度±20%。本地MODEL.md写train1765/valid59/test69，因此不能宣称公开包与队友实际训练数据逐文件相同。原因未确认，待归档hash、清单、坏图/筛选记录和划分核对。

公开项目总览显示1088张，版本6显示2011张，两者层级不同，不将它们视为同一个计数。下载入口存在，但本轮web工具访问版本6/download报Error fetching；未验证账号要求、实际归档可下载性或包内完整性。

备选：[HaGRID作者仓库](https://github.com/hukenovs/hagrid)。作者提供手势框标注、按人物划分和YOLO转换脚本，v2体量约1.5T、1086158张。类别如like/dislike/stop可作为待审核映射候选，但没有当前四方向七类的直接同名完整映射，因此用于场景/校准补充比直接替换七类评估集更合适；不建议为首版全量下载。未下载或执行其脚本。

建议下一步（未执行）：获取首选v6的YOLOv8格式包 -> 记录hash -> 审核data.yaml/标签/实际划分/预处理和近重复 -> train中选代表性校准样本 -> 验证/测试保持独立 -> 同输入配置建立FP32与整数对照。已有416拉伸图片不能证明原始640x480摄像头场景精度，后续仍补独立现场样本。

只读核验与路径审计见console.log；路径审计15项通过，不是下载/数据质量PASS。
