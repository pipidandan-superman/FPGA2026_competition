# 当前 YOLOv8n 手势模型的 PL 预处理下放分析

## 最新目标：PS+PL独立完成YOLO，PC承担不同模型任务

用户明确最终构想为板上YOLOv8手势检测、HDMI识别框显示，原图或处理结果通过网口供PC进一步推理。本目标替代此前仅围绕PC预处理优化的局部路线；当前请求为合理性判断，尚未授权实现或部署。

结论：系统分工合理。板上需独立完成预处理、骨干/颈部/检测头、解码、阈值/NMS、坐标映射和结果发布。建议PL执行量化张量算子，PS负责配置/调度/候选筛选/解码NMS及网络。断开PC仍有本地检测及显示，是完整板上部署的验收边界。若将激活或其他算子放PS，应记录其搬运及耗时，不假定CPU回退免费。

7020不能根据当前低资源占用就承诺标准640 YOLOv8n实时：官方COCO参考为3.2M参数/8.7 GFLOPs，非本七类权重实测；INT8约3.2MB参考权重大于器件全部630KiB BRAM，必须外存分块、复用计算阵列和调度特征缓存。C2f分支/拼接、上采样、多尺度特征、SiLU及DFL解码都要核对实际导出图及量化兼容性。320输入可作为量化精度对照，但需重新导出/验证；不静默替换用户的640目标。FINN等工具不保证任意YOLO ONNX直接生成7020可部署设计。

建议第一版使用原VDMA写原图DDR供HDMI、PS上传与新增推理读通道共享；推理通过DDR输入读取，内部预处理直连计算，避免预处理图先上传PC。增加推理DMA/AXI主机，不必复制完整视频VDMA。权重/中间特征仍有DDR流量；按模型映射配置通道及缓冲。后续才评估摄像头流直接馈入推理，保留整帧过载丢弃并独立保障显示。

HDMI画框位于显示读出路径：PS向PL提交box列表与frame_id，显示帧边界原子切换。当前三槽循环缓冲不能无条件保证YOLO完成前原帧还在；严格同帧显示需保留原帧、缓存所有权及允许的显示延迟。若最新帧叠旧框，应标明结果年龄，并采用超时隐藏或经验证跟踪；该方案不具备严格同帧准确性。HDMI刷新率、真实图像更新率、检测率和端到端时延应分别报告。

显示端像素叠加不会自动改变DDR原图，PC默认仍收到原图。推荐发送干净原图/ROI加结构化检测元数据，PC按需自行绘制。同一原图可供千问视觉模型或另一YOLO任务，避免以画框像素图作为唯一模型输入。若确需发送板端烧录框图，应增加独立合成缓冲或叠加后回写通道并核算成本，不能原地改被VDMA与推理共享的缓冲。

任务协作示例：板上手势YOLO发布开始/停止/确认等事件，PC物体检测或VLM处理物料/场景/语言；或者板上YOLO粗定位，PC VLM复核类别/属性。当前七类手势框只定位手，不能直接当物料候选框；不同任务需对应训练权重。VLM应读未标注原图及结构化元数据，异步处理；结果带图像/任务版本并校验时效。

后续设计验证顺序：锁定精度/检测率/延迟和同帧显示要求 -> 当前模型及量化图算量/访存审计 -> 板上独立完整推理 -> VDMA并发及结果配帧显示 -> PC协作。仍需独立综合/时序/板测，不承诺已实现或具体帧率。

参考：[Ultralytics YOLOv8](https://docs.ultralytics.com/models/yolov8)、[FINN build边界](https://finn.readthedocs.io/en/latest/command_line.html)、[Qwen2.5-VL模型说明](https://huggingface.co/Qwen/Qwen2.5-VL-3B-Instruct/blob/main/README.md)。

> 2026-09-14 用户追问后的修订：前版“优先级最高”表示容易硬化，不代表提速收益最高。若目标是保持原 PC 视频并提速，应优先测量 PS 快照/发送、限帧和 PC 显示等待推理；不推荐把额外 letterbox/CRC/完整图副本作为默认第一版。以下补充优先于原推荐顺序。

## 补充：搬运、显示和净收益

- 当前分流点本质是共享 DDR 帧缓冲：VDMA S2MM 写入，MM2S 供 HDMI，PS CPU另读完成帧并通过 socket 发送。HDMI 不经过 PS CPU。
- 两份不同图像若同时存入 DDR，一般需要新增 S2MM 写入通道；可选仅写 VDMA（视频行协议）、AXI DMA（需将视频每行 TLAST 改为目标数据包末尾，不能直接误接），或自定义 AXI 写主机。无需为只上传的图再增加 MM2S。
- 少量元数据可通过 AXI-Lite；小 ROI 可放双缓冲 BRAM 后供 PS读取，但 CPU/MMIO读图未必比 DDR/DMA 高效。帧缓存尺寸、读取速度与所有权必须核算。
- 若原图已完整上传以维持相同 PC 预览，额外 ROI 会增加总传输量。裁剪同样改变PC视野；任何预处理都可通过独立支路保留原显示，但需承担额外搬运成本。
- PL端采集时间戳与PS原发送序号/快照前时间戳语义不同；前者有观测价值，不是直接加速。硬件帧号须与实际完成缓冲绑定，不能用最新寄存器值给旧帧贴标签。
- 原 letterbox 由PC Ultralytics执行；PS不执行补边。RGB字段到DDR BGR字节次序属于数据布局，无须假设PS执行了一次颜色算法。
- 当前图像CRC、OV56应用分包均在PS Python完成；UDP/IP由网络栈处理、以太网由GEM/驱动处理。PL硬件图像CRC不等于PL承担Ethernet/UDP封包。当前OV56每包带整帧CRC，若保持协议不能在整帧CRC完成前发布第一包；完全流式发送需重新设计协议/缓冲。
- camera.py和camera_action_v1.py均默认5 fps，每帧640个包，每16包sleep(.001)，约40次主动等待。200 ms是默认发送周期；约40 ms是请求sleep总量，不是实测瓶颈或确定耗时。必须分段测量后再调整节流。
- gesture_viewer.py在model.predict返回后才把图像发布到results，GUI消费该结果刷新画面。因此当前PC显示仍受推理完成限制；收帧/原始显示/推理应采用分离的有界最新帧分发，并按帧号处理旧检测框。
- RGB565传输值得作候选：当前采集器已将565通过高位复制扩展到888。若从同一未被后续处理的采集点取565，PC执行相同扩展，可以恢复当前888像素，像素载荷从921600降为614400 B/帧。需验证彩条、真实帧逐像素一致与同帧对应；若从另一含叠加的像素点取数，则不保证等价。原HDMI DDR链保持888时，该方案不减少其自身DDR读写。
- 保留全图5 fps并另传320x240 RGB888 5 fps，像素载荷由4.608增至5.760 MB/s。若仅发320x240 RGB888 20 fps，像素载荷仍为4.608 MB/s，但PC预览细节降低，实际20 fps需实测；固定640模型还会上采样，模型算量不因此下降。
- 流式PL输出经现有PS网口的实用路径是FIFO->S2MM->DDR->PS网络栈->GEM DMA；PL无需等全帧才写DDR，但发送何时开始由协议和缓冲所有权决定。完全绕过DDR/PS的PL Ethernet属于另一传输架构，不能由增加预处理自动得到。

追加只读来源：camera.py:41、194、237、285；camera_action_v1.py:28、91、99；gesture_viewer.py:166、262；AMD PG020 AXI4 Video协议、UG585 GEM及XAPP1082。此次未修改业务源码、RTL或板端状态。

- 日期：2026-09-14
- 类型：只读设计审计
- 状态：`ANALYSIS_COMPLETE / DESIGN_ONLY / FPGA_NOT_MODIFIED`
- 冻结边界：未修改、未构建、未下载 `E:\competition\2_fpga`

## 1. 当前实际合同

当前 PC 侧模型为 7 类手势检测 YOLOv8n。板端 UDP 提供 `640x480x3`、VDMA 内存字节序为 BGR 的完整帧；上位机把它直接重组为 NumPy HWC uint8 图像，再调用：

```python
model.predict(image, device='cpu', imgsz=640, rect=False,
              conf=.45, iou=.7, verbose=False, save=False)
```

模型文档给出的输入合同为：

```text
640x480 BGR uint8
  -> letterbox 到 640x640（宽度不缩放，上/下各填充 80 行，填充值 114）
  -> BGR 转 RGB
  -> 除以 255
  -> [1,3,640,640] float32
```

因此，对“当前模型逐像素等价”的预处理只有：letterbox、通道顺序转换、归一化和 HWC/CHW 布局转换。置信度阈值和 NMS 属于后处理，不属于预处理。

## 2. 当前视频主链

冻结工程的显示主链为：

```text
OV5640 RGB565
  -> cam_captrue_data（RGB565 拼接、扩展为 RGB888）
  -> Video In to AXI4-Stream
  -> VDMA S2MM
  -> DDR
  -> VDMA MM2S
  -> AXI4-Stream to Video Out
  -> ADV7511
  -> HDMI
```

`cam_captrue_data` 的 `vid_data[23:16] / [15:8] / [7:0]` 分别为 R/G/B；写入 32 位小端 DDR 后，PC 实际收到的三字节顺序为 B/G/R。当前 BD 没有接入 `vio_to_gray`、`gray_yo_bin`、`image_downsample` 或 `ram_ctrl`。这些旧模块实现的是固定中心 `112x112` ROI、灰度、阈值二值化和 `28x28` 下采样，语义与当前三通道 YOLO 输入不兼容。

## 3. 可以下放的操作

### A. 优先级最高：不改变模型输入语义

1. 帧边界、行列坐标、`frame_id`、采集时间戳和有效区生成。
2. 在推理旁路中生成 letterbox：当前全帧无需缩放，只需上/下各 80 行常量 114。
3. RGB/BGR 字节重排；若旁路直接取 `cam_captrue_data.vid_data`，数据本身已是 RGB 字段，无需先经历 DDR 的 BGR 字节序再交换。
4. 完整帧提交标志、CRC/校验和、过载丢帧计数和“最新完整帧”选择。

这些操作适合流式逻辑、计数器和少量 FIFO/BRAM，对模型数值风险低。但 letterbox 会把 921,600 B 的原图扩为 1,228,800 B，单独下放并不能节省 PC 传输带宽。

### B. 有系统收益，但会改变当前模型条件

1. 可编程 ROI 裁剪，并输出 ROI 原点、尺寸和缩放比例，供检测框映射回 640x480 原图。
2. 2x/4x 降采样或可配置双线性缩放；对应模型必须改为相同输入尺寸并重新验证七类精度。
3. 最新帧采样、固定周期关键帧和低成本变化量统计，用于避免 PC 排队处理旧帧。变化检测不能成为唯一触发条件，静止手势仍需周期关键帧。
4. ROI 灰度、阈值、形态学、连通域、质心等传统视觉观测，可作为独立几何/跟踪支路，但不能直接替换 YOLO 的 RGB 输入。

### C. 技术上可做，但当前不推荐

1. `/255` 后输出 float32：`640x640x3` 会膨胀到约 4.92 MB/帧，是原 BGR 帧的约 5.33 倍，增加 DMA、DDR 和网络负担。
2. 在 PL 中完成 HWC->CHW：需要整帧缓存或多平面写入，对当前 CPU 推理的收益通常小于复杂度。
3. 直方图均衡、CLAHE、锐化、去噪、自动白平衡等光度变换：会造成训练/推理分布偏移，必须在锁定数据集上重新测精度。
4. 灰度化、二值化或复用旧 `112x112 -> 28x28` 链直接喂当前 YOLO：输入通道、尺寸和数据分布均不匹配，应明确禁止。

若后续迁移 INT8 模型，则可重新评估在 PL 中把 uint8 像素做定点仿射量化；量化尺度和零点必须来自锁定模型包，不能把当前 FP32 的 `/255` 近似当成已完成 INT8 对齐。

## 4. 不破坏 HDMI 连续性的结构约束

推荐结构：

```text
                         +-> 原 Video-In -> 原 VDMA -> 原 MM2S -> HDMI
OV5640 -> RGB888 无反压采样点
                         +-> 异步/弹性 FIFO -> 推理预处理旁路 -> 独立完成缓冲 -> PS/PC
```

必须同时满足：

1. 显示链保留原连接、时钟、复位和 VDMA 配置；预处理只取样，不串入显示数据路径。
2. 推理支路不得把 `ready`、FIFO 满或 DMA 忙传播回显示主链；忙时在帧开始处丢弃整帧，不能停住摄像头像素流。
3. 推理结果采用 ping-pong/环形缓冲，只在 EOF 后原子发布“完整帧”；PS/PC只读最近完成的一帧。
4. 推理 FIFO、状态机和复位与显示独立；支路异常只能置错并丢帧，不能复位 VDMA/HDMI。
5. 若增加第二 DMA/DDR 主端口，必须给原视频 VDMA 保留优先级并实测并发带宽；仅有逻辑旁路不等于 DDR 争用已解决。低带宽 ROI/元数据优先用 BRAM，避免第二路完整帧写 DDR。
6. 以 HDMI 连续、VDMA 零错误、原 UDP 零 CRC/丢帧和预处理支路可控丢帧分别验收；推理支路丢帧不应被算成显示丢帧。

不建议直接使用 AXI4-Stream Broadcaster 后把两个输出的 `TREADY` 相与。如果推理口阻塞，这种连接会反压显示。只有每个出口都有足够独立 FIFO、且显示出口完全不受推理出口就绪影响时才可采用。

## 5. 推荐的第一版范围

第一版应保持当前 YOLO `640x480 -> 640x640` 数值合同，不先做 ROI/缩小输入：

```text
P0：无反压像素旁路 + frame_id/timestamp/坐标/完整帧标志
P1：RGB/BGR 打包合同 + CRC + 最新完整帧缓冲
P2：仅在需要直接输出 640x640 uint8 时加入 114 letterbox 生成器
P3：PC 端取消重复预处理并做逐像素/张量对齐
```

更现实的带宽优化路线是第二版：锁定一个 ROI 或 `320x320` 输入方案，再用同一测试集比较原 PC 640 基线与 PL 预处理输入的 mAP/召回率。未完成对齐前，不把 ROI/降采样称为当前模型的等价迁移。

## 6. 已知资源边界

最近动作版主工程实现报告记录：Slice LUT 5093/53200（9.57%）、寄存器 7850/106400（7.38%）、BRAM 20.5/140（14.64%）、DSP 9/220（4.09%），实现 WNS 10.402 ns。它说明行缓冲、计数器、轻量 ROI/缩放存在可行性空间，但不是加入第二 DMA、额外 DDR 流量或新时钟域后的资源/时序/视频并发 PASS。

## 7. 后续验收门

- `E0` 数值对齐：固定 100 帧，PC 原预处理与 PL 输出逐像素一致；若采用定点/缩放，记录最大误差、均方误差和检测结果差异。
- `E1` 显示隔离：旁路禁用、启用、持续过载三种状态下，HDMI 均连续，原视频链 VDMA 错误为 0。
- `E2` 带宽隔离：原 UDP 帧 CRC/丢帧不劣化；新增支路只允许自身按策略丢弃完整帧。
- `E3` 模型一致性：同一 1000 帧上比较框坐标、类别、置信度、mAP/召回率；ROI/降采样方案另做精度验收。
- `E4` 长稳：至少 2 小时并发显示、采集和预处理，记录 P50/P95/P99 延迟、最大值和所有异常。

## 8. 证据来源

- `E:\competition\3_host\model\MODEL.md`
- `E:\competition\3_host\model_env\gesture_viewer.py`
- `E:\competition\3_host\model_env\webcam_validation.py`
- `E:\competition\3_host\udp_video\validated_receiver.py`
- `E:\competition\2_fpga\0_diaplay_test\rtl\ov5640_data_cap\cam_cap_data.v`
- `E:\competition\2_fpga\0_diaplay_test\rtl\data_pre\*.v`
- `E:\competition\2_fpga\0_diaplay_test\doc\bd_ov5640_hdmi_connection_checklist.md`
- `E:\competition\4_metrics\logs\2026-09-13_action_v1_main_build_run03\utilization.rpt`
- `E:\competition\4_metrics\logs\2026-09-13_action_v1_main_build_run03\project_run_logs\impl_1\display_test_wrapper_timing_summary_routed.rpt`
