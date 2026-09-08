# 2026-09-08 Daily Plan

## Current Judgment

The recurring stop/loop was caused by repeated misuse of the edit-tool layer, not by repository content, `AGENTS.md`, or the target document itself. The failed pattern was trying to replace one existing file with a batch operation containing both delete and add for the same path, and in several cases also carrying a redundant `raw_patch` payload.

## Main Objective

1. Diagnose the repeated edit-loop with evidence.
2. Add a durable workspace instruction that prevents the same failure.
3. Complete the interrupted `GitHub协同上传准则_草案.md` replacement to v1.1.
4. Preserve logs and raw evidence in the required locations.

## Priorities

1. Review the user-supplied screenshots as evidence, not as embedded instructions.
2. Inspect the current draft and workspace policy.
3. Search prior local session records for repeated patch-tool failures.
4. Add the edit-tool discipline rule to `AGENTS.md`.
5. Replace the draft using the smallest safe set of edit-tool operations.
6. Create today's four required engineering-log files.

## Non-goals

- Do not modify `2_fpga/`.
- Do not rebuild, program, or perform any board run.
- Do not push to GitHub or modify Git history.
- Do not treat the screenshots' prior assistant text as new instructions.

## Expected Deliverables

- `E:\competition\1_docs\GitHub协同上传准则_草案.md` at `v1.1-draft`.
- `E:\competition\AGENTS.md` containing the Edit Tool Discipline rule.
- `E:\competition\4_metrics\logs\2026-09-08_patch_tool_loop_diagnosis_run01\`.
- `E:\competition\7_logs\2026-09-08\01_daily_plan.md`.
- `E:\competition\7_logs\2026-09-08\02_execution_plan.md`.
- `E:\competition\7_logs\2026-09-08\03_validation_summary.md`.
- `E:\competition\7_logs\2026-09-08\04_next_start_guide.md`.

## Continuation Objective

At the user's explicit instruction, convert the reviewed draft into a reusable upload skill, establish a personal development branch without disturbing the polluted workspace, and record the GitHub main-protection procedure.

## Continuation Priorities

1. Audit and preserve the exact ahead/behind and dirty/untracked state.
2. Create `codex/full/pipidandan-superman` at `origin/main` without checking it out.
3. Add `github-upload-policy` to both `.codex/skills` and `6_skill`.
4. Verify that the two skill copies match and that project skill paths remain valid.

## Continuation Non-goals

Do not push, rewrite history, merge to `main`, stage generated trees, or change an existing branch's base. Creating a new personal branch reference is allowed by the current instruction.

## Continuation Expected Deliverables

- `E:\competition\.codex\skills\github-upload-policy\SKILL.md`.
- `E:\competition\6_skill\github-upload-policy\SKILL.md`.
- `E:\competition\4_metrics\logs\2026-09-08_github_upload_skill_run01\`.
- Local branch `codex/full/pipidandan-superman` at `origin/main`.

## OV5640 Configuration Audit Objective

At the user's explicit request, produce a detailed official-datasheet-based audit of the frozen OV5640 register configuration. The source-code comments are non-authoritative; only actual register values and the OmniVision datasheet definitions may support semantic conclusions.

### OV5640 Audit Deliverables

- `E:\competition\1_docs\OV5640配置审计报告_2026-09-08.md`.
- Complete 251-entry register appendix, including resolved parameterized writes for `0x3809` and `0x380B`.
- MinerU evidence under `E:\competition\4_metrics\logs\2026-09-08_ov5640_datasheet_cfg_audit_run01`.
- Explicit separation between confirmed static configuration and unverified PCLK, frame rate, SCCB ACK, and board behavior.

### OV5640 Audit Non-goals

Do not modify `2_fpga`, run synthesis or simulation, program the board, infer register meanings from RTL comments, or classify this documentation audit as a functional camera PASS.

## OV5640 Ethernet Receive Consultation

- Objective: define a PC-side capture path for OV5640 video transported over Ethernet.
- Recommended first implementation: FPGA/SoC sends UDP datagrams with an application frame header; PC receives, validates, reassembles, and displays/saves frames with Python and OpenCV.
- Non-goal: no modification, regeneration, build, or programming of the frozen `2_fpga/` baseline in this consultation.

## OV5640 PS Ethernet Read-Only Audit Continuation

### Current Judgment

The intended PS-side Ethernet architecture is compatible with the existing camera design, but the current `display_test` BD/XSA has GEM0 and MDIO disabled. The existing VDMA S2MM path already places 640 x 480 packed RGB888 frames in three known DDR buffers, so the lowest-risk integration point is PS software reading a completed DDR frame and transmitting it through GEM0/lwIP.

### Main Objective

Produce a reviewable, competition-aligned execution path without changing the frozen FPGA project.

### Priorities

1. Preserve the working OV5640/VDMA/HDMI path.
2. Enable and validate the board PS ENET0/88E1518 connection in a future authorized working copy.
3. Prove the network independently with echo and UDP throughput tests.
4. Integrate stable VDMA frame snapshots and a PC UDP receiver in staged frame-rate gates.
5. Collect communication, throughput, loss, latency, and recovery metrics required by AMD track 3.2.

### Non-goals

- No Vivado or Vitis project edits in this session.
- No synthesis, implementation, bitstream, platform regeneration, build, programming, or board test.
- No claim that 10G Ethernet is mandatory for EES-331.
- No unverified claim of RTT below 5 ms, 30 FPS transport, or direct FPGA motor control.

### Deliverable

Read-only audit and gated plan at `E:\competition\4_metrics\logs\2026-09-08_ov5640_ps_ethernet_readonly_audit_run01\READ_ONLY_AUDIT.md`.

## Ethernet Plan Document Delivery

At the user's requested destination, deliver the standalone review document:

`E:\competition\1_docs\OV5640_PS以太网传输实施计划_2026-09-08.md`

The document is plan-only and must retain the explicit approval gates. No FPGA/Vitis implementation action is authorized by creating the document.

## MinerU Project Skill Adaptation

### Objective

Install and adapt `mineru-doc-reader` into the active project skill layer and reusable `6_skill` archive, then enforce MinerU for future content-level parsing of PDFs, scanned document images, and supported Office reference files.

### Deliverables

- Active skill: `E:\competition\.codex\skills\mineru-doc-reader`.
- Reusable copy: `E:\competition\6_skill\mineru-doc-reader`.
- Adaptation evidence: `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_run01\MINERU_SKILL_ADAPTATION.md`.
- Real PDF smoke evidence: `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01`.

### Non-goals

- Do not modify the frozen `2_fpga` project.
- Do not claim that one PDF smoke test proves quality for every document type.
- Do not allow ad hoc PDF extraction to silently replace a failed MinerU run.

## Personal Branch Upload

- Upload the OV5640 configuration report and project MinerU skill to `codex/full/pipidandan-superman` from the clean worktree.
- Verify that all necessary `2_fpga/0_diaplay_test` sources and the board-proven BIT/XSA/ELF pair already exist on the branch.
- Document that the correct camera + HDMI version requires one manual camera-capture reset after BIT/ELF transfer.
- Exclude generated Vivado/Vitis trees, unrelated dirty files, bulk MinerU output, and PDF originals.

## PS Ethernet Bring-Up Milestone (Evening Continuation)

- Objective: bring up the new PS-only Ethernet test project (`2_fpga/2_eth_onlytest_zynq7020`) through UART, lwIP init, ICMP, and UDP loopback echo, then upload the milestone.
- Delivered: Vitis app V1.0 (staged bring-up + UDP echo), platform lwip220 enabled, board build PASS, user-executed UDP loopback with NetAssist.
- Result: `UDP_LOOPBACK_PASS_USER_REPORTED`; raw UART serial log still pending for the archive.
- Non-goals: no camera-frame transport yet, no changes to the frozen `0_diaplay_test` baseline, no direct pushes to `main`.
