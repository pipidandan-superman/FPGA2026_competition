# 验证摘要

## 今日已核对事实

- 赛题 PDF 共 17 页；赛题二要求基于紫光同创 FPGA 开发板或以紫光同创 FPGA 为核心的自制板，并使用 PDS。
- 实际工程目录为：
  - `E:\FPGA_Project\2020_2\cnn_PS_PL_ACC_final\cam_vdma_hdmi_true`
  - `E:\FPGA_Project\2020_2\cnn_PS_final\cam_vdma_hdmi_true`
- PS+PL 版本包含 PL Conv/ReLU/MaxPool、BRAM 交换、OV5640、VDMA、HDMI 和 PS 端 FC 推理。
- PS-only 版本在 PS 端执行完整 CNN，可作为性能对照基线。
- GitHub 私有仓库已创建，当前只有初始 README，工程源码尚未上传。
- 已在 `C:\Users\Administrator\Desktop\competition\README.md` 创建项目总说明，并通过 GitHub 提交 `docs: align project README with competition plan` 同步到远程仓库；远程 README 当前为 85 行、约 3.3 KB。
- MinerU pipeline 解析 PDF 返回 HTTP 500；已使用 pypdf 生成降级文本，原始 PDF 仍为权威来源。

## 今日尚未完成

- 未完成 RK3568_MES2L100H 上的 PDS/Logos-2 移植。
- 未完成真实相机标定和畸变参数验证。
- 未完成 FPGA 畸变映射、双线性插值、任意角度和动态控制。
- 未完成多路视频或神经网络扩展。

## 赛题二验收门禁

- [ ] 真实相机标定参数可复现。
- [ ] 二阶径向/切向畸变模型与软件参考一致。
- [ ] 双线性插值无明显黑边、空洞和撕裂。
- [ ] 单路实时视频达到目标分辨率和帧率。
- [ ] 动态角度参数可更新且画面稳定。
- [ ] 保存直线度误差、MTF50/SFR、端到端延迟、帧率和资源报告。

每次综合、仿真、板测或图像质量测试都必须在本日志根目录下保存完整原始输出，不得只保留摘要。

## 结果占位

当前状态：已将主线调整为 AMD 3.2 具身智能赛道；XC7Z020/Zynq-7020 仅作为原型平台，正式赛道闭环尚未完成。

## AMD 具身智能验证边界

- ViTA 的 `XC7Z020 / Zynq-7020` 原型通过，可以证明视频链路、算法、协议和闭环逻辑可行。
- Zynq-7020 原型通过，不等于已经完成 Ryzen AI PC + AMD FPGA/Zynq 的正式赛道验收；需另行记录平台型号和赛事合规确认。
- 普通 PC 替代 Ryzen AI PC 的测试只能作为软件/通信联调证据。
- 最小闭环通过标准：目标识别结果可复现；板卡可向机械臂控制器发送有效指令；机械臂返回状态可被可靠解析；连续运行不少于规定次数且无通信死锁。
- 每次实验必须保存完整视频/串口/网络日志、动作指令、反馈数据、失败样本和时间戳。

## AMD 3.2 正式验收占位

- [ ] Ryzen AI PC 型号和软件环境确认。
- [ ] XC7Z020/Zynq-7020 或替代 AMD 平台的参赛资格确认。
- [ ] 真实机械臂及控制器通信协议确认。
- [ ] 感知—决策—执行—反馈闭环现场演示。
- [ ] 端到端延迟、抓取成功率、识别准确率和通信稳定性报告。

## Python/PYNQ 状态

- 已确认：Zynq-7020 芯片具备在 ARM PS 上运行 Linux/Python 的能力。
- 未确认：EES-331 是否已有可直接启动的 PYNQ 镜像、设备树、板级约束和 Python 外设驱动。
- 验证结论前不得把“能运行 Python”写成“已有 PYNQ 支持”。
