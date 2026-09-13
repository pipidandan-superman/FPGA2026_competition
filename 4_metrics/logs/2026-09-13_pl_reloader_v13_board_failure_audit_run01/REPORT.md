# v1.3 动作加载失败只读审计

## 结论

本次 GUI 并非永久卡死。主机端在 `FOUND` 后使用 `Popen.communicate()` 等待整个板端控制器命令结束，期间不流式显示 stdout，因此约 50 秒没有新增界面日志；控制器结束后才一次性显示全部事件。

实际板端结果为动作 Overlay 位流下载成功，但摄像头/VDMA 在固定 5 秒首帧门内没有观察到两个缓冲槽的真实帧切换，触发 `FIRST_FRAME_TIMEOUT` 和 fail-closed。动作服务未到达 `ACTION_SERVICE_READY`/`ACTION_OVERLAY_READY`，随后安全 HALT、释放缓冲并自动恢复原视频。

## 当前运行证据

- 载荷验证：`PAYLOAD_VERIFIED`，13 文件，`ACTION_HARDWARE_CONTRACT_PASS`。
- MMIO：`MMIO_LIBRARY_READY`，SHA-256 `753b36efadfb1da6f626bd267b8d97da3d9e1d927a856852fca894e5b5429e23`。
- 原视频停止：`ORIGINAL_STOP_SAFE`。
- 动作位流：`PL_LOADED`，SHA-256 `bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`，FPGA manager state `operating`。
- 视频初始化：`SENSOR_SETTLE_COMPLETE seconds=1.0`、`VDMA_RESET_OK`、`BUFFER_ALLOCATED`。
- 第一失败点：`FIRST_FRAME_TIMEOUT`，`seen=[false,false]`，`mm2s_sr=0x11000`、`s2mm_sr=0x10000`、`mm2s_cr=0x1008b`、`s2mm_cr=0x180cb`。
- 清理：`VDMA_HALTED` 后 `BUFFER_FREED`，动作服务 inactive/dead。
- 自动恢复：原 `ees331-camera` PID 1284、active/running；用户独立确认 HDMI 已恢复正常，见 `physical_confirmation.json`。

原始只读 SSH 输出保存在 `board_failure_readonly.txt`；第一次沙箱内 SSH 因权限隔离失败，未接触板卡，成功读取使用的是获准的只读 SSH。

## 与历史证据比较

本次失败签名与此前 `action_v1_board_run03` 及 `action_v1_end_to_end_run01` 的失败完全一致：同一 BIT 哈希、`seen=[false,false]`、相同 VDMA CR/SR 和 `No real frame transition`。同一 BIT 在 `action_v1_controlled_video_run01` 的 T2 中曾于加载后约 1.35 秒出帧，也在 `action_v1_load_sequence_board_run01` 的 S1/S2 中通过原 5 秒门。

因此可确认问题位于动作 Overlay 热重载后的摄像头/VDMA 首帧恢复路径，具有前置状态或初始化时序敏感性；现有证据不能把它归因为固定 RTL/地址冲突，也不能声称根因已经闭环。单纯放宽超时或重复点击会掩盖问题，不作为修复。

## 状态边界

- `V13_FALSE_POSITIVE_FIX`: PASS；本次确实进入板端 load，没有复现旧 `pgrep` 假成功。
- `PAYLOAD_AND_HWH_CONTRACT`: PASS。
- `PL_DOWNLOAD`: PASS。
- `ACTION_VIDEO_FIRST_FRAME`: FAIL。
- `ACTION_SERVICE_READY`: FAIL/未到达。
- `ACTION_LINK_AXI_LED`: NOT_RUN。
- `AUTOMATIC_ORIGINAL_RESTORE`: PASS。
- `PHYSICAL_ORIGINAL_HDMI_RESTORE`: USER_CONFIRMED_PASS。
- `ROOT_CAUSE`: UNCONFIRMED。

## 下一步建议（未执行）

先改进主机端控制器输出为流式显示，避免正常等待被误认为卡死；功能诊断则保持同一 BIT、Camera 和 5 秒门，只增加摄像头/SCCB就绪、采集时钟/帧计数和 VDMA 首个状态变化观测，定位第一处分歧。未经单变量方案确认，不重复加载、不改地址/RTL、不盲目延长超时。
