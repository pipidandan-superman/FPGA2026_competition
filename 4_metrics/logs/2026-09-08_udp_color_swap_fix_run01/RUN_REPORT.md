# UDP 相机帧红蓝互换（色差）根因分析与修复报告

- 日期：2026-09-08
- 任务：分析以太网显示色差（对照 Apple 相机参照照片），并协同摄像头寄存器配置处理
- 结果：`UDP_CAMERA_RB_SWAP_ROOT_CAUSE_PASS` + `UDP_COLOR_SWAP_FIX_DELIVERED` + `UDP_COLOR_SWAP_USER_VISUAL_PASS`
- 边界：板端（2_fpga 冻结 BIT/ELF/寄存器）零修改；修复全部在 PC 上位机侧；无新的板级构建

## 1. 现象（用户三组对照照片）

| 物体 | 真实颜色（Apple 照片） | UDP 显示颜色 | 对应 R/B 互换后预期 |
|---|---|---|---|
| 三号 | 黄色 | 淡蓝 | 黄 (250,230,150)→(150,230,250) 淡蓝 ✓ |
| 二号 | 蓝紫色 | 棕橙色 | 蓝紫 (150,140,230)→(230,140,150) 橙粉 ✓ |
| 一号 | 淡紫色 | 粉色 | 淡紫 (210,180,230)→(230,180,210) 粉 ✓ |

三个颜色全部命中 **红/蓝通道互换**，排除白平衡/饱和度类成因。

## 2. 根因链路（证据闭环）

1. **摄像头寄存器无责**：`0x4300=0x61`（RGB565 sequence 1，首字节 `{R[4:0],G[5:3]}`）与
   `cam_cap_data.v:96` `{cam_data_d0,cam_data}` 组字节一致（见《OV5640配置审计报告_2026-09-08》）；
   HDMI `BOARD_VISUAL_PASS`（2026-09-07 冻结）证明 RGB565→RGB888 通道映射正确，
   AXIS `tdata[23:0]={R[7:0],G[7:0],B[7:0]}`（`cam_cap_data.v:106` 位复制扩展）。
2. **VDMA 小端打包**：`display_test_axi_vdma_0_0.xci`：S2MM AXIS 24 bit → AXI 64 bit；
   24 位像素字按 AXI 小端从最低字节逐个填入内存 ⇒ DDR 每像素 3 字节为 `B,G,R`（stride 1920 佐证）。
3. **板端逐字节搬运**：`main.c copy_camera_snapshot`（memcpy）与 `udp_video_tx.c send_one_frame`
   （`payload[i]=src[...]`）均无重排 ⇒ UDP 载荷 = DDR 字节序。
4. **上位机解码假设错误**：`udp_video_gui.py` V1.1 `Image.frombytes("RGB", ...)` 按 `R,G,B` 解释 ⇒ 红蓝互换。
5. **决定性对照**：type=0x02 合成彩条由软件按 `[R,G,B]` 直接组包、不经 VDMA；B1 板测截图
   （`2026-09-08_mainproj_eth_loopback_integrate_run01/gui_b1_frames22.png`）显示彩条与红色移动列全部正确
   ⇒ 传输/解码链路字节忠实，互换仅发生在"VDMA 打包字节序 vs 解码假设"这一层。
6. **历史误判纠正**：C1 日志中"色差为 HDMI(YCbCr 有限范围) 与 UDP 双管线预期差异"不成立——
   limited-range 只影响亮度/饱和度，不可能造成色相 180° 翻转。

## 3. 为什么 HDMI 正确且不受影响（对用户预期的修正）

S2MM 打包与 MM2S 解包对称：MM2S 从 DDR 读出后恢复 `tdata[23:0]={R,G,B}`，HDMI 链路颜色本来就正确。
因此本修复**不会改变 HDMI 显示**（无需"变得更佳"，它已是基准）；修复后 UDP 与 HDMI 色相一致，
残余差异仅剩 HDMI 侧 BT.601 limited-range 造成的亮度/饱和度差（预期，非缺陷）。
**严禁**改 `0x4300` 输出顺序来"纠正"以太网——那会使 HDMI 红蓝互换并破坏冻结基线。

## 4. 修复内容（全部在 3_host / 1_docs，板端零改动）

| 文件 | 变更 |
|---|---|
| `3_host/udp_video/udp_video_gui.py` | V1.2：按包头 type 感知解码，type=0x01 用 Pillow raw `"BGR"`，其余 `"RGB"`；raw_mode 随帧入队 |
| `3_host/udp_video/udp_video_rx.py` | V1.1：type=0x01 字节序已是 `[B,G,R]`（cv2 原生）不再翻转；type=0x02 保持 RGB→BGR 翻转 |
| `3_host/udp_video/dist/EES331_UDP_Viewer.exe` | PyInstaller 重打包（31,187,867 B，2026-09-08 18:23） |
| `1_docs/OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md` | v1.1：新增 §10 字节序勘误（根因链路/修复决定/验证证据） |

附带收益：相机载荷字节序与 OpenCV 原生 BGR 一致，后续 3_host/model 视觉模型取帧零转换。
选择接收端修复而非 PS 端换字节的原因：PS 端每帧多 921 KB 内存流量，D-Cache 关闭下直接侵蚀
C2 提速（15 FPS）余量；接收端修复零板端成本。

## 5. 验证

### 5.1 端到端注入测试（本机，`ALL_COLOR_SWAP_FIX_TESTS_PASS`）

`verify_color_swap_fix.py`：经真实 localhost UDP 发送 640 包/帧（32B 头+CRC32）：
- test1：type=0x01、按 DDR 字节序 `[B,G,R]` 编码的三个真实物体颜色 → 修复后解码
  `(250,230,150)/(150,140,230)/(210,180,230)`，与真值逐像素相等；旧解码器输出
  `(230,140,150)/(230,180,210)` 与用户截图屏幕色一致（before/after 双向印证）。
- test2：type=0x02 彩条帧 `[R,G,B]` → 解码不变，证明合成图案路径不受影响。
- 控制台日志：`verify_console.log`。

### 5.2 重建 exe 实机目视（用户确认）

- 重建 exe 启动后即收到板卡实时流（192.168.240.10，6.30 fps），随后注入 127.0.0.1 的 BGR 测试彩条。
- 用户截图 `user_visual_pass_bgr_bars_127001.png`：黄 / 蓝紫 / 淡紫三色条与 Apple 参照一致，
  完整帧 190 递增、丢帧 0、CRC 错 0、重复/坏头 0/0。

### 5.3 最终板端实时流目视 PASS（用户录屏，2026-09-08 21:43–21:44）

- 视频：`user_final_visual_pass_board_stream.mp4`（20,403,871 B ≈ 19.5 MB，
  SHA-256 `de165b6f9f25db8d3b6c3ff10623c7256d2a9090433d8286b881393e65ea9599`）。
  大二进制入库理由：最终板级目视验收的原始录屏证据，无法用截图替代动态画面与统计栏，按上传准则规则 8 声明后入库。
- 视频事实：用户从任务栏打开重建后的 `EES331_UDP_Viewer.exe`；exe 自动监听 5000，
  状态 `receiving from 192.168.240.10`，完整帧 508→622 递增，帧率 6.25 fps 稳定，
  丢帧/CRC 错 5→6（≈1%，与 C1.2 固化基线一致），重复/坏头 0/0。
- 内容：真人面部、手部（挥手/比手势/握拳）动作下肤色与画面色彩自然，无红蓝互换迹象。
- 判定：`UDP_COLOR_FIX_BOARD_STREAM_VISUAL_PASS`（用户确认"显示颜色正常"）。
  边界：目视验收；完整串口与定量色彩测量未做，不声明 FULL acceptance。

## 8. 最终固化

- 修复版本：`udp_video_gui.py` V1.2 + `udp_video_rx.py` V1.1 + exe（SHA-256 `a4b75ed3...`）。
- 板端配对不变：C1.2 冻结 BIT `7CB11F7D...` + ELF `3E295D51...` + XSA `30644B31...`（本次零改动）。
- 固化标记：随上传提交打 tag `udp-color-fix-pass-20260908` 推送个人分支。
- 结果：`UDP_COLOR_SWAP_FIX_FREEZE_PASS`。

## 6. 工件哈希

见本目录 `artifacts_sha256.txt`（修复后的 gui/rx/exe/文档/截图/脚本）。

## 7. 后续建议

1. 下次板会无需重烧板端；直接用新 exe 验证真实相机帧颜色（拍一个已知强色物体对照即可）。
2. C2 提速按原路线推进；本修复不影响其判据。
3. 若日后改用 PS 端换字节方案（如模型侧强制要求 RGB 内存序），需重开证据 run 并重测 fps。
