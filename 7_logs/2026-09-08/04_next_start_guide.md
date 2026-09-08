# 2026-09-08 Next Start Guide

## First Action

Read the new `## Edit Tool Discipline` section in `E:\competition\AGENTS.md` before performing another manual file edit.

## Durable Edit Rule

1. For one existing file whose whole content changes, use the dedicated single-file replacement tool exactly once.
2. Do not use a batch operation that contains delete and add for the same path.
3. Do not pass a redundant `raw_patch` field.
4. Use targeted structured updates for partial edits.
5. Use batch operations only for independent paths.
6. If an edit tool rejects an operation, stop and choose a distinct recovery path; do not repeat the failed call.

## Current Next Step

The draft `E:\competition\1_docs\GitHub协同上传准则_草案.md` is ready for human review at `v1.1-draft`. The user should answer the ten review questions at the end of the document before the policy becomes executable.

## Forbidden Immediate Actions

- Do not push to GitHub.
- Do not modify `2_fpga/`.
- Do not create branch protection or the upload-policy skill until both members approve the draft.
- Do not convert this documentation PASS into a board or build PASS.
- Do not repeat a failed batch edit on the same target path.

## Success Criteria for Follow-up

After review approval, create the upload-policy skill, branch-protection instructions, and the upload-discipline audit script only in separate controlled steps with their own evidence and validation.

## Patch Tool Loop Follow-up

First read `E:\competition\4_metrics\logs\2026-09-08_patch_tool_runtime_fix_run01\TOOL_RUNTIME_FIX_EVIDENCE.md`. The current environment exposes one freeform file-edit tool named `apply_patch`; the other apply-patch tool names in older notes are not callable tools.

For an existing file, use one `*** Update File` patch. For a new file, use one `*** Add File` patch. Use separate `apply_patch` calls for separate files. Do not use same-path `*** Delete File` plus `*** Add File` for ordinary editing. If a patch is rejected, reread the file once, correct the context, and make one new attempt only.

## 2026-09-08 Continuation Boundary

The local branch and skill-copy checks are complete. The next action requiring user or environment support is a fresh remote audit: resolve the `.git/FETCH_HEAD` permission failure, then run `git fetch --prune origin` and compare the branch again. Do not infer remote freshness from the local `c6ddb70` observation.

## Updated Next Action After Successful Fetch

Remote freshness and the clean worktree are now confirmed. Continue only inside `E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`. Select one coherent upload topic, compare each source file against the clean worktree, and copy only explicitly reviewed files. Do not use `git add .` or mirror the polluted workspace.

## OV5640 Audit Handoff

First read `E:\competition\1_docs\OV5640配置审计报告_2026-09-08.md`. The confirmed static mode is DVP 8-bit, 640x480 RGB565 sequence 1, automatic AEC/AGC, horizontal binning, horizontal/vertical subsampling, ISP processing enabled, and JPEG/MIPI output disabled.

### Smallest Useful Follow-up

If hardware verification is requested, preserve the frozen source hashes and create a new evidence run. Measure or capture `cam_pclk`, `cam_vsync`, `cam_href`, and the first active RGB565 bytes; then compare the measured frame period against `HTS=1892` and `VTS=1000`.

### Forbidden Immediate Conclusions

- Do not claim PCLK=51 MHz from source comments.
- Do not derive the active PCLK divider from `0x3824` while `0x460C[1]=0`.
- Do not call `0x3821=0x01` a mirror setting.
- Do not treat the static audit as proof that all SCCB writes were acknowledged or that the displayed image is correct.

## OV5640 Ethernet Next Start

First confirm four transmitter facts before writing the final PC receiver: transport protocol and destination port, resolution, pixel format, and the exact packet/frame header. Do not assume raw RGB565, YUV422, JPEG, or a headerless stream. The smallest useful test is a synthetic frame with known colors and monotonically increasing frame/packet IDs, observed first in Wireshark.

## Reviewed Next Start Gate

Do not begin with PC OpenCV code or merge networking into the camera application. After explicit approval, the first execution action is to preserve the current BD/XSA/bitstream hashes and create an approved working copy or branch. Then change only the Zynq PS peripheral configuration: enable ENET0 on MIO16-MIO27 and MDIO on MIO52-MIO53 while retaining UART1 on MIO48-MIO49 and all current DDR/AXI settings.

The first acceptance point is an exported XSA whose HWH proves GEM0 and MDIO are enabled. The second acceptance point is a standalone lwIP echo/UDP throughput test with UART and Wireshark evidence. Camera-frame integration is forbidden until both gates pass.

For camera integration, start with a synthetic packet pattern, then one copied DDR frame, then 1/5/15 FPS. Attempt 30 FPS only after the link negotiates at 1 Gbit/s and the measured loss-free throughput is sufficient. Treat byte order, VDMA completed-buffer selection, cache invalidation, and snapshot-buffer lifetime as explicit verification items.

## Ethernet Plan Review Entry

First read `E:\competition\1_docs\OV5640_PS以太网传输实施计划_2026-09-08.md`. The next permitted action is human review of its network addressing, 32-byte UDP header, 1,440-byte payload, snapshot-buffer strategy, and H0-H1 approval boundary. Do not open or change the Vivado project until the user explicitly approves Gate H0-H1.

## MinerU Document Parsing Rule

For the next content-level task involving a PDF, scanned document image, DOCX, PPTX, XLSX, XLS, or similar reference file, first read `E:\competition\.codex\skills\mineru-doc-reader\SKILL.md`. Before launching MinerU, tell the user the exact `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN` evidence path.

Reuse an existing parse only when the input SHA-256 matches and the run contains `MINERU_PARSE_PASS`, Markdown, and content JSON. Otherwise create a fresh run. Do not use ad hoc PDF text extraction as the primary semantic parser or silently substitute another parser after failure.

The validated integration evidence is `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_run01\MINERU_SKILL_ADAPTATION.md`; the real PDF smoke evidence is `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01`.

## Uploaded Camera HDMI Version

The personal branch `codex/full/pipidandan-superman` is synchronized at remote commit `220197f`. Use `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md` as the operating note.

To reproduce the existing `BOARD_VISUAL_PASS`, program the frozen BIT, load the paired ELF, and manually reset the camera capture once after transfer. Judge the live image only after that reset. Do not rebuild or mix the frozen BIT/XSA/ELF pair unless starting a new separately evidenced validation run.

## Ethernet Milestone Handoff (Evening)

- First action next session: archive the board UART serial log (STAGE0..LOOPBACK_TEST_READY + HEARTBEAT lines) into `4_metrics/logs/2026-09-08_eth_app_uart_udp_echo_code_run01/` to upgrade `UDP_LOOPBACK_PASS_USER_REPORTED_RAW_SERIAL_PENDING` to a raw-evidence PASS.
- Confirm the UDP port mismatch: screenshot shows destination port 8080, delivered code binds 5000. Align code and test tool on one declared port before the next run.
- Smallest useful next step: add the board-to-PC UDP sender stage (fixed synthetic pattern, monotonically increasing frame/packet IDs), receive it with NetAssist/Wireshark on the PC, then wire in one VDMA DDR frame snapshot from the camera path.
- The PR from this milestone must be reviewed and merged by member-b (`xiaokaiyuan`) before `main` is considered updated.
- Forbidden immediate actions: no direct pushes to `main`, no camera-frame integration before the UDP sender stage passes, no edits to the frozen `0_diaplay_test` baseline.

## Loopback PASS Correction (Evening)

- The 8080-vs-5000 port mismatch was the whole story of the first failure; both ends now use UDP 5000 and the loopback passes (RX 95 = TX 95). The "confirm port edit" boundary is closed.
- Still owed: archive the full UART serial log including HEARTBEAT lines to complete the raw serial evidence.
- Next development stage unchanged: board-to-PC UDP sender with synthetic pattern and incrementing frame/packet IDs, then one VDMA DDR frame snapshot from the camera path.
- The PR to `main` remains open for member-b review; this correction commit will be pushed on top.

## 主工程集成后下一步

1. 用户在 Vitis GUI 对 `app_component` 执行 Build → Run（新 XSA 平台）。
2. 串口验收序列：`UART_TEST_PASS` → `ETH_LOOPBACK_INIT_BEGIN` → `ETH_LWIP_OK` → `ETH_UDP_ECHO_OK` → `LOOPBACK_TEST_READY` → `VDMA_INITIAL_BEGIN` → `HDMI_HEARTBEAT`。
3. PC 侧 ping 192.168.240.10 + UDP 5000 回显；全部通过后记录 `MAIN_ETH_LOOPBACK_PASS`，并把完整串口日志归档到集成 run 目录。
4. 下一步开发：board→PC UDP 帧发送（先合成图案 + 递增帧号），再接 VDMA 完成帧快照。

## 主工程里程碑后交接

- 分支已推送主工程 V3.1 集成提交（源码 + 新 XSA/BIT/ELF + 证据）；`main` 的 PR 评审流程继续由 member-b 处理。
- 下一步开发顺序不变：board→PC UDP 帧发送（合成图案 + 递增帧号，Wireshark/NetAssist 验收）→ VDMA 完成帧快照接入 → 按实施计划 H1/H2 门限推进（1/5/15 FPS）。
- 待办遗留：主工程完整串口日志归档；README/HANDOFF 已更新新基线说明。
- 操作注意：新 BIT（`7CB11F7D...`）+ 新 ELF（`52209F62...`）为当前配对；不要与 09-07 冻结配对混用。

## C1 通过后交接

1. C1.1 质量优化：选槽避开 S2MM 写指针与 MM2S 读指针（第三槽法）、爆发限速（每 64 包微延时）、评估开启 lwIP UDP 校验和、GUI fps 改累计均值。
2. C2 提速：runtime 已实测 5 fps；A1 吞吐基准后按 5→15 FPS 门限推进。
3. 分支已推送 B1+C1 成果；PR 交 member-b 评审合并。

## C1.1 交接

- V3.1.4 代码已就绪（选槽避让/爆发限速/GUI fps 累计均值），用户 Build → Run。
- 验收：连续 10 分钟 GUI `丢帧=0、CRC 错=0`、完整帧 ~5/s、HDMI 正常 ⇒ `C11_QUALITY_PASS` 后进入 C2 提速（先 A1 iperf 基准）。
- lwIP UDP 校验和为可选项，暂不启用（CRC32 已兜底），如复测仍有 CRC 错再评估。

## C1.2 / C2 路线（代码已可准备）

- 残余 1% 的修复方向明确：把 921KB memcpy 拆成 64KB 块、块间穿插 xemacif_input 服务（消除 RX 服务停顿）——此项同时是 C2 提速的前置（15 fps 下阻塞时长 ×3 会放大丢包）。
- C2 其余条件：A1 iperf 吞吐基准（摸清上限）→ 提速 5→15 FPS。
- 可选：GUI 帧率栏已在 V1.2 exe 中为累计均值，无需再改。

## C1.2 通过后交接

1. C2 提速：UDP_TX_FRAME_INTERVAL_MS 200→66（15 FPS），TX_BURST_PACING_US 按帧周期收紧（66ms 周期 → 每 32 包歇 ~600µs，整帧摊至 ~20ms）；预期丢帧仍为 0，若 15 FPS 不稳再回 5 FPS 排查。
2. 可选 A1：iperf 基准摸清实际上限后再决定 30 FPS。
3. 待归档：10 分钟浸泡测试 + 完整串口日志（正式记录）。
4. 分支待推送：C1.2 改动与证据（用户确认后推送）。

## 固化后交接（udp-camera-c12-pass-20260908）

- 板级复现序列：编程冻结 BIT（`7CB11F7D...`）→ 加载配对 ELF（`6EB0097C...`）→ UDP 视频流即恢复（与显示器状态无关）；如需肉眼看 HDMI，先切显示器输入源再按一次复位。
- 禁止：BIT/ELF 配对混用（如换 BIT 必须重配 ELF 并重新记录哈希）；旧 09-07 冻结对仅适用于 HDMI 单链路场景。
- 下一开发阶段：C2 提速 15 FPS（发送间隔 200→66ms + 整形收紧，先行 A1 iperf 基准更稳妥）。

## C1.2 通过后交接

1. C2 提速：UDP_TX_FRAME_INTERVAL_MS 200→66（15 FPS），TX_BURST_PACING_US 按帧周期收紧（66ms 周期 → 每 32 包歇 ~600µs，整帧摊至 ~20ms）；预期丢帧仍为 0，若 15 FPS 不稳再回 5 FPS 排查。
2. 可选 A1：iperf 基准摸清实际上限后再决定 30 FPS。
3. 待归档：10 分钟浸泡测试 + 完整串口日志（正式记录）。
4. 分支待推送：C1.2 改动与证据（用户确认后推送）。

## 固化后交接（udp-camera-c12-pass-20260908）

- 分支已推送固化提交；PR（回环+B1+C1+C1.2 全部里程碑）待 member-b 评审合并。
- C2.2（15 FPS）前置：错误码诊断（打印 udp_sendto 的 err 值）+ lwip220 参数调优（pbuf/heap/描述符数量）；JPEG 路线为后备。
- 待办遗留：完整串口日志归档；10 分钟浸泡测试正式记录。

## 色差修复后交接（UDP 相机帧红蓝互换，2026-09-08 晚）

先读 `E:\competition\4_metrics\logs\2026-09-08_udp_color_swap_fix_run01\RUN_REPORT.md` 与设计文档 v1.1 §10 勘误。

- 字节序定论：UDP type=0x01 相机载荷 = DDR 原生 `[B,G,R]`（VDMA 小端打包），上位机已按 type 感知解码；type=0x02 彩条保持 `[R,G,B]`。新写任何接收端/模型取帧代码都必须遵守该约定。
- **禁止**改 OV5640 `0x4300` 或任何 2_fpga 冻结件来"修颜色"：摄像头寄存器无责，HDMI 颜色本就正确，改了会互换。
- 下次板会最小动作：无需重烧；用新 exe（`3_host/udp_video/dist/EES331_UDP_Viewer.exe`，SHA-256 `a4b75ed3...`）拍已知强色物体做最终目视对照即可关闭色差项。
- 3_host/model 视觉模型取帧：相机帧字节序与 cv2 原生 BGR 一致，直接用，不要再翻转。
- C2 提速路线不变；本修复零板端成本。
