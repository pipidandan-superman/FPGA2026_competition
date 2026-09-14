# Hand Gesture v6 YOLOv8：下载与结构校验完成

## 2026-09-14 数据集迁移（本报告更新）

应用户要求，数据本体已从本run迁至`3_host/model_datasets/`（ZIP+解压dataset/，磁盘mv，内容未变）：原始ZIP现为`3_host/model_datasets/Hand_Gesture_v6_yolov8.zip`，解压目录为`3_host/model_datasets/dataset/`，说明见[3_host/model_datasets/README.md](../../../3_host/model_datasets/README.md)。本run保留全部校验证据（REPORT/validation.json/image_manifest.csv/verify_dataset.py/validation_console.log），"本run下"的旧表述按迁移后位置理解。数据本体不上传Git。

## 当前结果

用户明确同意接受服务条款后，已勾选并提交，再选择v6、YOLOv8、Download zip to computer完成下载。DOWNLOAD_AND_ZIP_CRC_PASS / PACKAGE_STRUCTURE_PASS；未执行校准、训练或量化，未修改原模型/冻结FPGA工程。

- 原始ZIP（本地独有，不上传Git）：本run下`Hand_Gesture_v6_yolov8.zip`，29,538,322字节，SHA-256为89b828c8bfad60243f790d58d896b5189a7ac6f3c498629fdd931b8179e378b5。浏览器原文件保留，复制前后hash一致。公开来源为[Roboflow v6](https://universe.roboflow.com/yolo-zxvpk/hand-gesture-r7qgb/dataset/6)，包内声明CC BY 4.0；不发布临时签名下载链接。
- 解压配置（本地独有）：本run下`dataset/data.yaml`，其元数据快照包含在validation.json；1893张416x416图片，train1765、valid59、test69，图片与同名标签一一配对；七类名称/编号顺序与当前模型一致。
- 实际包内划分与本地MODEL.md一致，网页1870/72/69计数不代表实际本次导出包。不能仅凭数量一致证明与队友旧包逐文件一致，仍缺旧包hash；无需再将网页数量差异误写成实际下载数据不匹配。
- ZIP全部条目CRC、解压路径与容量限制、图片完整解码、标签5字段/合法类别/有限归一化坐标/正宽高检查均通过，issue_count=0。未做人眼标签语义审核、边界框质量审核、近重复/跨集泄漏审核或识别精度测试。
- [结构检查JSON](validation.json)、[图片hash清单](image_manifest.csv)、[校验脚本](verify_dataset.py)、[原始输出](validation_console.log)已保存。固定Python初次沙箱启动失败，经批准使用同一解释器校验成功，未安装依赖。
- 原包data.yaml保持原样（相对路径为../train等）；后续执行基线时应生成单独的本地路径配置并验证解析，不修改原始导出包。训练部分可后续选校准样本，测试部分保持独立。
- valid中Stop仅1个框、Thumbs up/Thumbs Down各4个框，test中Stop2个、Thumbs Down3个；单类精度结论需注明样本限制，后续补真实场景评估。

项目技能路径审计15项通过。以下等待登录/条款记录为历史，已解除。

## 登录后的续接：等待条款确认

用户已登录。已选择Download dataset、YOLOv8、Download zip to computer并继续；网站随后弹出Roboflow Terms of Service，要求勾选“I accept the Terms of Service and Privacy Policy”。未勾选、未接受条款、未生成ZIP。当前状态改为DOWNLOAD_PENDING_TERMS_CONFIRMATION / ARCHIVE_NOT_DOWNLOADED。此项具有协议接受效力，需用户此时明确确认或亲自操作；下载授权不自动替代条款确认。标签1已再次markHandoff。

以下登录停止点是历史记录，已由上述条款停止点取代。

2026-09-14。用户已授权下载对应文件到本地，尚未完成。

状态：DOWNLOAD_PENDING_USER_LOGIN / ARCHIVE_NOT_DOWNLOADED / PACKAGE_NOT_AUDITED。

目标：https://universe.roboflow.com/yolo-zxvpk/hand-gesture-r7qgb/dataset/6/download/yolov8

经浏览器实际进入v6并选择YOLOv8，页面显示“Login or create a free account”，提供Continue with Google、Continue with Github、Continue with Email，并显示继续即接受Terms of Service和Privacy Policy。未点击登录提供商、未输入凭据、未创建账号或接受条款。不是推测需要账号，已在下载流程中实际遇到登录门。

浏览器标签1已markHandoff保留。用户自行登录完成后继续原v6/YOLOv8下载；不得猜测私有下载API、绕过认证或替换为v5/其他数据集。

计划本地下载/解包位置为本run目录。当前仅此记录，没有ZIP、图片或标注包，不生成虚假校验通过标记。后续下载完成先验证ZIP类型/完整性、SHA-256、路径安全，再解包到独立dataset子目录并检查data.yaml及划分/标签；不修改原模型、环境或冻结2_fpga。

原始可见状态：

```text
URL: https://universe.roboflow.com/yolo-zxvpk/hand-gesture-r7qgb/dataset/6/download/yolov8
Heading: Login or create a free account
Buttons: Continue with Google; Continue with Github; Continue with Email
Notice: By continuing, you are indicating that you accept our Terms of Service and Privacy Policy.
```

项目工作区/本地工程日志技能要求证据留在4_metrics/logs，本次停止点链接到7_logs/2026-09-14四文件。项目路径审计15项通过，仅为路径合规结果。
