# 补充数据集调研报告｜2026-09-14

目的：为后期的检查与泛化能力验证寻找补充数据集。当前主数据集 Hand Gesture v6 仅 1893 张，valid/test 中弱类样本极少（valid：Stop 1 框、Thumbs up/Down 各 4 框；test：Stop 2 框、Thumbs Down 3 框），单类精度结论受限。模型弱类（`3_host/model/MODEL.md`）：Left mAP50 0.511、Right 0.418、Thumbs Down 0.335。

本轮仅完成公开信息调研与免登录直下源下载；未做任何训练/量化/评估。信息来源：HaGRID GitHub README、HuggingFace 数据集页与文件树 API（均 2026-09-14 抓取）。

## 一、模型 7 类与候选数据集类别覆盖对照

| 模型类 | HaGRID 384p | HaGRIDv2 全量 | Kaggle marusagar | Roboflow Universe |
| --- | --- | --- | --- | --- |
| Stop | ✅ `stop` | ✅ `stop`/`stop_inverted` | ✅ stop | ✅ 多个数据集 |
| Thumbs up | ✅ `like` | ✅ `like` | ✅ thumbs up | ✅ 多个数据集 |
| Thumbs Down | ✅ `dislike` | ✅ `dislike` | ✅ thumbs down | ✅ 多个数据集 |
| Up | ❌ | ❌ | ❌（swipe 为动态手势） | ⚠️ 部分数据集（如 hand-gesture-r7qgb 含 Up） |
| Down | ❌ | ❌ | ❌ | ⚠️ 未确认含 Down 类的直接候选 |
| Left | ❌ | ❌ | ⚠️ left swipe（动态语义，非静态指向） | ⚠️ 未确认 |
| Right | ❌ | ❌ | ⚠️ right swipe（动态语义） | ⚠️ 未确认 |

**关键结论：HaGRID 无方向类（Up/Down/Left/Right）。** 方向类弱项补充目前没有确认的免登录直下源，见第四节待办。

## 二、已选定的免登录直下补充集

### HaGRID 384p 样本（cj-mills/hagrid-sample-500k-384p）

- 来源：HuggingFace `https://huggingface.co/datasets/cj-mills/hagrid-sample-500k-384p`
- 单文件 `hagrid-sample-500k-384p.zip`，13,418,776,353 字节（约 12.5 GiB），LFS 直链免登录
- LFS 内容 SHA-256：`461ad5746eb95c3605f4fa2ba7daa19e2fcd4d7d91d4d26c7c31dfe228feb68e`（下载后核验）
- 内容：509,323 张图（HaGRID v1 训练集降至 384p 短边），18 类
- 标注：每图归一化 bbox `[x,y,w,h]` + labels + `user_id`（可按拍摄者划分，避免同人泄漏）+ leading_hand
- 与模型 3/7 类直接对应：`stop`→Stop、`like`→Thumbs up、`dislike`→Thumbs Down（含最弱类 Thumbs Down）
- 其余 15 类（call/fist/mute/ok/one/palm/peace/rock/three/two_up 等）不可强行映射为模型七类，但可作为：
  - **OOD（分布外）负样本/干扰评估**：验证模型对非目标手势的误检率
  - **PTQ 校准图片池**：真实人手分布，符合"校准与评估分离"原则
- 许可：衍生自 HaGRID。官方 GitHub 声明"Creative Commons Attribution-ShareAlike 4.0 International License 的变体，以具体 LICENSE 文件为准"（[github.com/hukenovs/hagrid](https://github.com/hukenovs/hagrid) License 节）。竞赛/研究用途兼容；**如后续商用需重读 LICENSE 原文**
- 状态（2026-09-14）：**下载中**（后台任务）；下载完成后核验 SHA-256 → 安全解压 → 抽查标注结构与 bbox 合法性 → 记录 4_metrics run；ZIP 内是否含标注 JSON 尚未证实，若缺失则另从官方仓库下 annotations（体积小）
- 后续处理建议：解压后按类拆分，仅 `stop`/`like`/`dislike` + `no_gesture` 映射为评估子集；`user_id` 哈希划分独立评估集，禁止与训练调参混用

### HaGRID 全量（仅记录，不下载）

- HaGRIDv2：1.5 TB、1,086,158 张 FullHD、33 类 + no_gesture，按 user_id 划分 76/9/15%；官方提供 YOLO/COCO 转换脚本
- 512px 轻量版 119.4 GB；单类压缩包 24.8–63 GB。均超出本项目当前需要与磁盘预算（E 盘剩 105G），不下载

## 三、已排除候选

| 候选 | 排除原因 |
| --- | --- |
| Jester（148k 视频片段） | 分类任务、无检测框，类别以手指计数/方向拨动为主，与七类语义不符 |
| URGR（25m 远距 RGB） | 采集距离 25 米，与 0.5–4m 场景分布差异过大；获取渠道未确认免登录 |
| RGB-NHG（IEEE） | IEEE DataPort 获取需注册/可能付费；含 point left/right 但性价比待用户决定 |
| Mendeley HANDS | 以静态/动态手势识别为主，类别映射与许可待逐项确认，优先级低 |

## 四、待用户参与的候选（需账号登录/条款确认，按政策由用户本人操作）

1. **Kaggle `marusagar/hand-gesture-detection-system`**：thumbs up/down/left swipe/right swipe/stop 五类。注意 left/right swipe 是**动态滑动语义**，与模型的静态指向类 Left/Right 语义不同，仅可作参考/OOD，不可直接改名映射（符合"不得将其他手势强行改名为现七类"的既定边界）
2. **Roboflow Universe 定向检索**（登录后按类名筛选，导出 YOLOv8 格式）：
   - `yolo-zxvpk/hand-gesture-r7qgb`（Thumbs Down/Thumbs Up/Up）
   - `project-1-je8qv/hand-tracking-and-gestures`（84 图，Thumbs Up/Down，偏小）
   - `kpt-grxkc/thumbs-up-thumbs-down`（两类）
   - 方向类（Left/Right/Down 带框标注）建议在 Universe 用 `class:Left gesture` 等类名筛选，**未在本轮确认到现成数据集**——这是当前最大缺口
3. **HaGRID 官方 annotations**（若 ZIP 内不含）：GitHub 仓库 Downloads 节 `annotations` 链接，体积小，可直下

## 五、方向类（Left/Right/Down）缺口的备选路径

1. Roboflow Universe 登录检索（上述第四节）——首选
2. 自采少量定向补充：按部署计划 r3 第 4.4 节数据准入流程，用现有摄像头采集 + 标注，量小但语义精确匹配
3. RGB-NHG（IEEE）如用户愿意注册获取

## 六、政策边界（沿用）

- 数据本体（ZIP/图片/标签）不入 Git；仅本调研文档与 README 入库
- 需登录/接受条款的下载由用户本人完成（2026-09-14 Roboflow 先例）
- 校准与评估分离；测试集不参与调参；不得将其他手势强行改名为现七类
- 单类精度结论须注明样本量限制；跨数据集对比须先核对预处理差异（v6 为 416 拉伸，HaGRID 384p 为短边缩放，须统一到模型输入合同再评）
