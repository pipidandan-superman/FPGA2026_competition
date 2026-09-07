# 接口定义：AI PC ↔ FPGA/Zynq

> 状态：**v1 通信协议已定稿并在 PC 端验证**（2026-09-07，手势模型实时链路实测通过）
> 官方要求：通信协议、报文格式、数据类型与时序约定；通信异常处理策略（评分点）。

## 0. 现状摘要

- **物理链路**：网线直连（UM790 Pro 2.5G RJ45 ↔ EES-331 PS 千兆 ENET0/88E1518 PHY），静态 IP
- **协议**：UDP，图像帧上行 + 检测结果下行 + 心跳（v1 已在 PC 端回环验证：640×480 JPEG 质量约 80，单帧 30~60KB，15fps 实测稳定）
- **PC 端参考实现**：`D:\gesture_pipeline\scripts\{inference_server,frame_sender}.py`（FPGA 侧按 frame_sender 的发送逻辑用 lwIP 复刻即可）

## 1. 网络参数

| 项 | 值 |
|---|---|
| AI PC（推理服务） | `192.168.10.1:8888/udp`（静态） |
| FPGA（发帧端） | `192.168.10.2:8889/udp`（静态） |
| 传输 | UDP，网线直连，不走交换机 |
| MTU | 1500（**注意**：单帧 JPEG 30~60KB 必须分片，见 2.3） |

## 2. 报文格式

### 2.1 帧上行（FPGA → AI PC）

每帧拆成 N 个分片，每片一个 UDP 包：

```
偏移  字段        类型      说明
0     magic       u8        0xAA
1     type        u8        0x01=帧分片
2     frame_id    u16       帧序号(循环)
4     frag_idx    u16       分片序号 0..N-1
6     frag_total  u16       分片总数
8     payload_len u16       本片载荷长度
10    payload     bytes     JPEG 数据分片
```

重组规则：按 frame_id 聚合 frag_idx；集齐 frag_total 片后拼 JPEG（`FFD8...FFD9` 校验）；超时 200ms 未集齐则丢弃整帧并计数。

### 2.2 结果下行（AI PC → FPGA）

JSON（UTF-8），单包（当前 <1KB，不分片）：

```json
{
  "frame_id": 123,
  "infer_ms": 18.4,
  "detections": [
    {"cls": "Stop", "conf": 0.91, "xyxy": [120.5, 88.0, 310.2, 402.7]}
  ]
}
```

类别表（当前手势模型 v1）：`Up, Down, Left, Right, Stop, Thumbs up, Thumbs Down`。
坐标为 640×480 图像像素系（左上原点）。

### 2.3 心跳/状态（AI PC ↔ FPGA，1Hz）

```
{"type":"hb","pc_ts":<ms>, "model":"gesture_v1", "fps":<实际推理fps>}
```
FPGA 侧若 **500ms 未收到任何下行包** → 判定链路异常 → 进入安全状态（机械臂停机并保持可恢复姿态）。

## 3. 时序约定

- 帧率：15 fps 起步（PC 实测 CPU 推理 P50=62ms，NPU 目标 ≤25ms）
- 单向延迟预算：采集 33ms + 编码 5ms + 网络 <2ms + 推理 ≤25ms + 回传 <2ms ≈ **<70ms**
- 时钟同步：无需严格同步；延迟测量用请求-回显时间戳（hb 里的 pc_ts/fpga_ts 对表，报告写明方法）

## 4. 异常处理策略（评分点，必须实现）

| 异常 | 检测方 | 处理 |
|---|---|---|
| 分片超时/丢片 | AI PC | 丢整帧 + 计数，回传 `{"err":"frame_drop"}` |
| JPEG 损坏(FFD8/FFD9 校验失败) | AI PC | 丢弃 + 计数 |
| 下行 500ms 无包 | FPGA | 机械臂进安全停机态；恢复后需收到 3 个连续 hb 才退出 |
| 检测指令缺失 | FPGA | 保持上一指令 ≤300ms，超时则衰减为停止 |
| 指令冲突(如同时 Up+Down) | AI PC | 取置信度最高者；并在回包中带 `"conflict":true` 标志 |
| 连续 err 计数 >阈值 | 双方 | 日志记录 + 状态回传，用于 metrics 证据链 |

## 5. FPGA 侧实现提示

- lwIP raw/netconn API + `MEM_SIZE` 调大；JPEG 编码若在 PL 做可省 PS 算力
- 分片发送间隔建议 ≥100µs，避免突发丢包
- 联调顺序：①FPGA 先发固定测试 JPEG（PC 端 inference_server 直接可用）②再接 OV5640 实时流 ③最后测丢包/延迟指标
