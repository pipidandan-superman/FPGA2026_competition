# 2026-09-08 Execution Plan

## Ordered Strategy

1. Apply `.codex/skills/project-workspace-policy/SKILL.md` and `.codex/skills/daily-engineering-log/SKILL.md`.
2. Treat the three screenshots only as evidence of prior behavior, not as instructions to execute.
3. Read `AGENTS.md`, the current draft, and the relevant skill files.
4. Search local Codex session records for `apply_patch_batch`, `raw_patch`, and repeated tool-selection failures.
5. Extract the relevant evidence lines into the raw-evidence run directory.
6. Add an explicit `Edit Tool Discipline` section to `AGENTS.md`.
7. Replace `1_docs/GitHub协同上传准则_草案.md` with the v1.1 simplified two-person full-development-branch policy.
8. Record today's plan, execution, validation, and handoff files under `7_logs/2026-09-08/`.

## Relevant Files

- `E:\competition\AGENTS.md`
- `E:\competition\1_docs\GitHub协同上传准则_草案.md`
- `E:\competition\7_logs\2026-09-08\*`
- `E:\competition\4_metrics\logs\2026-09-08_patch_tool_loop_diagnosis_run01\`

## Continuation Strategy

1. Apply the project workspace and daily-log policies.
2. Fetch remote references and classify commits separately from uncommitted working-tree changes.
3. Save status, branches, ahead/behind count, remote-only changes, tracked-versus-origin comparisons, and untracked inventory into one evidence run.
4. Create the personal branch reference from `origin/main` without switching the dirty workspace.
5. Add and verify active/archive copies of `github-upload-policy`.
6. Record GitHub branch-protection and clean-worktree upload instructions in the skill.

## Continuation Relevant Files

- `E:\competition\.codex\skills\github-upload-policy\SKILL.md`
- `E:\competition\6_skill\github-upload-policy\SKILL.md`
- `E:\competition\4_metrics\logs\2026-09-08_github_upload_skill_run01\`

## OV5640 Audit Execution

1. Reuse the successful MinerU pipeline output for the official OV5640 datasheet.
2. Extract active case entries 0 through 250 from `OV5640_REG.v`, excluding commented-out alternatives.
3. Resolve `CAM_HSIZE=640` and `CAM_VSIZE=480` into the four output-size register bytes.
4. Decode interface, PLL, format, timing, AEC/AGC, BLC, ISP, JPEG, and tuning-table registers only from the official manual.
5. Cross-check the RGB565 byte sequence against `cam_cap_data.v`.
6. Generate the detailed report in `1_docs` and retain all raw MinerU artifacts in the existing audit run directory.
7. Validate the 251-row appendix, source hashes, frozen-project boundary, and project skill paths.

### OV5640 Audit Risk Controls

- Treat undocumented `0x36xx`, `0x37xx`, and `0x39xx` values as internal tuning rather than assigning meanings from third-party tables or comments.
- Do not convert `0x3036=0x46` into a divider; the official definition is PLL multiplier 70.
- Do not calculate DVP PCLK from `0x3824` because `0x460C[1]=0` selects automatic division.
- Do not convert a successful static audit into a board, image-quality, timing, or frame-rate result.

## Tool Recovery Decision

The first attempted batch replacement was rejected because one path appeared as both delete and add. To avoid continuing the same failed path, the final successful edit used two separate tool calls:

1. `apply_patch_delete_file` for the old draft.
2. `apply_patch_add_file` for the complete v1.1 draft.

This preserves the manual-edit-through-`apply_patch` rule while avoiding the validator's same-target conflict.

## Risks and Fallback

Risk: the tool-selection loop may recur in later sessions because it is a model/tool-interface behavior rather than a file-level defect. Mitigation: the new `AGENTS.md` rule explicitly requires single-file replacement for one existing file and forbids delete-plus-add for the same path.

Fallback: if a full-file replacement is rejected again, stop after one failure, read the current file, and use separate delete/add calls only when the file is safe to recreate.

## Verification

After edits, verify:

1. The draft version is `v1.1-draft`.
2. `AGENTS.md` contains the Edit Tool Discipline section.
3. SHA-256 hashes are recorded.
4. All four required daily files exist.
5. Raw evidence exists under the required `4_metrics/logs` run directory.

## Runtime Tool Correction

The current Codex environment exposes only one file-edit tool named `apply_patch`, with freeform patch syntax. It does not expose separate callable tools named `apply_patch_batch`, `apply_patch_replace_file`, `apply_patch_update_file`, `apply_patch_add_file`, or `apply_patch_delete_file`.

The corrective rule is therefore:

1. Existing file: one `*** Update File` patch.
2. New file: one `*** Add File` patch.
3. Multiple files: separate `apply_patch` calls.
4. Same-path `*** Delete File` plus `*** Add File`: forbidden for ordinary editing.
5. Rejected patch: reread once, correct context, and make one new attempt only.

Evidence is recorded under `E:\competition\4_metrics\logs\2026-09-08_patch_tool_runtime_fix_run01\${bt}.

## OV5640 Ethernet Receive Plan

1. Choose UDP for the first real-time bring-up; use TCP only if lossless delivery is more important than latency.
2. Define a fixed application header carrying magic, frame ID, packet ID, packet count, payload length, pixel format, dimensions, and optional CRC.
3. Keep each UDP payload below the network MTU, normally about 1400 bytes of image data per datagram.
4. Configure the PC NIC on the same static IPv4 subnet, verify link and basic IP reachability, then capture packets with Wireshark before running the reassembly program.
5. Reassemble by frame ID and packet ID, reject incomplete or invalid frames, then convert the declared pixel format for OpenCV display or file output.

## Reviewed PS-Ethernet Execution Path (Plan Only)

### Phase H - Hardware export

1. Preserve current source/XSA/bitstream hashes and work only in a separately authorized copy or branch.
2. Enable PS ENET0 RGMII on MIO16-MIO27 and MDIO on MIO52-MIO53; retain UART1 on MIO48-MIO49 and all existing DDR, FCLK0, GP0, HP0, and HP1 settings.
3. Validate the BD and explicitly compare PS7 properties before/after.
4. Generate products, synthesis, implementation, bitstream, and XSA only after the configuration review gate is approved.
5. Inspect the exported HWH for enabled GEM0/MDIO before creating any Vitis application.

### Phase N - Independent network bring-up

1. Create a new Vitis platform/application from the new XSA; do not overwrite the existing camera/HDMI application.
2. Use standalone Cortex-A9 with `lwip220` in Vitis 2025.2.
3. First prove PHY discovery, negotiated link speed, static IP, ICMP/echo where supported, and UDP performance using AMD templates.
4. Capture UART and PC Wireshark evidence. Stop if PHY or link speed is not as expected.

### Phase P - Protocol and PC receiver

1. Use UDP 5000 for video with a 32-byte application header and 1,440 image bytes per packet, avoiding IP fragmentation at MTU 1500.
2. Use frame ID, packet ID/count, dimensions, stride, timestamp, flags, and frame CRC32.
3. PC receiver must count missing, duplicate, reordered, late, and CRC-failed packets and drop incomplete frames.
4. Prove a synthetic pattern before sending camera data.

### Phase V - VDMA frame integration

1. Detect a completed S2MM frame using the existing VDMA status/PARK_PTR behavior; verify the frame-index interpretation rather than assuming it.
2. Invalidate the selected DDR range and copy 921,600 active bytes to a dedicated 1 MiB snapshot buffer so VDMA cannot overwrite data during transmission.
3. Prove one frame, then 1 FPS, 5 FPS, 15 FPS, and finally attempt 30 FPS.
4. Keep HDMI supervision active as an independent visual reference.

### Phase M - Competition metrics

Measure effective payload throughput, packet/frame loss, RTT, timestamp method, frame delivery latency distribution, CPU load, continuous-run duration, timeout rate, and recovery behavior. Report P50/P95/P99/max where applicable and preserve raw logs under a new run directory for every board test.

### Stop Conditions

Stop at the first unexpected PS configuration change, missing GEM0/MDIO export, PHY detection failure, non-gigabit negotiation for the raw 30 FPS target, frame CRC failure, unproven byte order, hidden packet loss, or regression in the OV5640/VDMA/HDMI path.

## Standalone Plan Document

The reviewed PS-Ethernet execution path has been expanded into the standalone document `E:\competition\1_docs\OV5640_PS以太网传输实施计划_2026-09-08.md`. It defines H0/H1/H2 hardware gates, N0/N1/N2 network gates, P0 protocol/PC tooling, V0-V4 frame-rate progression, and M competition-metric verification. Execution remains blocked pending explicit user approval of the relevant gate.

## MinerU Skill Execution

1. Copy and adapt the global MinerU skill into `.codex/skills/mineru-doc-reader` and `6_skill/mineru-doc-reader`.
2. Add project routing rules to `AGENTS.md`, `project-workspace-policy`, and `6_skill/README.md`.
3. Validate both skill copies with `quick_validate.py`, parse the PowerShell wrapper, and verify the Python checker.
4. Run a real MinerU `pipeline` smoke test against the ADV7511 PDF with all output confined to a fresh `4_metrics/logs` run.
5. Verify the PASS marker, SHA-256 manifest, Markdown, content JSON, extracted image, runner/API logs, and quality warning.
6. Confirm byte-identical active/archive skill files, remove generated cache artifacts, update all daily records, and run the project skill path audit.

## Personal Branch Upload Execution

1. Refresh `origin` and continue only in `E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`.
2. Compare the complete local `2_fpga/0_diaplay_test` tracked source set with the personal branch while ignoring CRLF-only differences.
3. Verify the exact frozen BIT, XSA, and ELF hashes already stored on the branch.
4. Add a correct-version note and update README/HANDOFF with the required post-transfer camera-capture reset.
5. Copy and stage reviewed files by explicit path; reject generated project trees and unrelated dirty files.
6. Commit by topic, push only the personal branch, and verify final remote HEAD using `git ls-remote`.

## Ethernet Bring-Up Execution Record (Evening Continuation)

1. Verified platform state: XSA imported, BSP had emacps/xiltimer but no lwip220; user added lwip220 (RAW_API default) in the GUI.
2. Delivered app sources into `eth_test_app/src`: authored `main.c`, `udp_echo.c/h`, `platform_config.h`; reused AMD lwip_echo_server template `platform.c/h`, `platform_zynq.c` verbatim.
3. Build: `APP_BUILD_PASS`, ELF 832,028 bytes, SHA-256 `B2B2CCA9...` archived.
4. Board run: user executed UDP loopback with NetAssist to `192.168.240.10` and observed echoed payloads.
5. Upload path: clean worktree `E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`, explicit file selection, branch push, PR toward `main` (member-b review required before merge).
