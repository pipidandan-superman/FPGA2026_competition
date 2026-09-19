---
name: zynq-pynq-overlay-workflow
description: Develop, deploy, and validate Zynq PYNQ overlays on an existing Linux SD image, including PS compatibility, AXI control, BD reset wiring, staged board diagnosis, and safe restoration. Use for BIT/HWH replacement and PS-PL integration; not for arbitrary SD-image rebuilding or bare-metal-only workflows.
---

# Zynq PYNQ Overlay Workflow

An SD image boots the PS; a compatible overlay can replace PL while Linux runs. A successful bitstream download does not prove AXI responsiveness, application correctness, or restoration of the previous workload.

Workspace adaptation: in `E:\competition`, apply its project-workspace-policy and daily-engineering-log skills; evidence belongs in `4_metrics/logs/<run>` and daily records in `7_logs/YYYY-MM-DD`. Other workspaces retain their own approved paths.

## Establish scope and compatibility

- Obtain authority for each hardware-changing phase. A question about deployment does not authorize downloading, stopping services, rebooting, or changing boot files. Preserve the user's selected board, project, and stage gates.
- Follow the current workspace's path/log/frozen-baseline rules. Snapshot the exact source, BD/XCI/XDC, matched BIT/HWH/XSA, hashes, and runtime configuration before changing a proven design. Keep each failed run immutable; use new run names.
- Separate PS boot configuration (DDR, crystal/PLL assumptions, MIO, Ethernet/SD/UART, memory map) from PL topology and fabric clocks. Loading a BIT does not rerun the new XSA's complete FSBL initialization. Review FSBL/device tree/kernel driver changes if those foundations differ; do not promise arbitrary old SD images will work. Enabling PS-PL interfaces (GP/HP/ACP ports, IRQ_F2P) in the PS wizard is FSBL-side metadata, not a runtime PS action — an overlay that newly wires such ports downloads exactly like any other BIT; only the fabric connections differ.
- Audit kernel-bound PL devices, interrupts, DMA ownership, and userspace mappings before replacing hardware. HWH metadata is not a substitute for a Linux device tree. Quiesce every actual owner, not just a conveniently named service.
- For an EES-331 task, read [references/ees331.md](references/ees331.md). Treat it as a board profile, not universal parameters.

## Verify hardware beyond pure RTL

- Exercise AXI independent AW/W arrival, backpressure stability, delayed backends, WSTRB, access errors, reset, and command snapshot/sequence/ACK semantics with self-checking simulation. Do not inject intentionally invalid MMIO accesses on Linux merely to duplicate SLVERR coverage.
- Check the generated BD and HWH: every reset input's polarity **and connected inactive level**, clock lock input, debug reset, clock association, address aperture, and interconnect clock conversion. Unused active-low reset inputs must be high. Checking only the primary reset misses auxiliary-reset faults.
- Include official-IP/BD integration evidence. Reproduce the faulty connection in a controlled test when useful, then prove correct reset assertion, release, and an actual CSR response. Pure RTL PASS and Vivado `validate_bd_design` do not establish integration correctness.
- Build with the project's approved Vivado launcher. Require implementation, timing/DRC, address/clock/reset reports, no unresolved black boxes, matched BIT/HWH, and XSA consistency. Regenerate dependent IP and synthesis runs after BD changes.
- Gate board downloads on the generated hardware contract, not only file names or prior build PASS. Reject known-faulty artifacts even if their old manifest is internally consistent.

## Stage board operations

1. Confirm actual SSH/console login, runtime, boot ID, original workload, and physical/streaming baseline. Board wall-clock dates can be stale; use boot IDs and monotonic event timestamps. When preflighting a startup service that is expected to die, wait for its TERMINAL state (failed/inactive, process gone) — a wait loop that breaks on `active` races the service's own failure window and misreads a live owner as vacuous.
2. Transfer matched artifacts and software into a new independent directory; verify hashes after transfer. Resolve physical addresses from the matching HWH, and peripheral register models from the IP's own generated metadata (XCI memory maps, generated headers) rather than recollection — silicon-observed reset values then double as a configuration audit. Compile architecture-specific MMIO/barrier helpers on the target and retain their hashes.
3. Announce the interruption. Acquire ownership, stop the original application, and verify DMA has halted and buffers are released. If that cannot be established, stop before reconfiguration. When ownership is vacuous — the previous workload is already dead (service in failed terminal state, hardware removed) and no client holds the PL device — record that finding and proceed; the halt-and-release gate applies to live owners.
4. On a new or previously failed design, separate metadata parsing, download-only, liveness, identity read, and functional commands into explicit checkpoints. For a design with no addressable PL slave (e.g. PS-only), identity is the artifact hashes plus the HWH contract plus kernel-side download evidence (fresh FPGA-manager/zocl log entry per reload), not a CSR read. Preserve a known restoration route. Do not repeat a known bad MMIO read to diagnose a bus hang.
5. Run deterministic functional tests with sequence/result/count checks, timeout handling, reset/reload coverage, and stage-specific criteria. A software timeout cannot necessarily interrupt a CPU load stalled on AXI; prevent invalid/held-reset access through structural gates first.
6. Restore the previous overlay/workload and verify actual new frames or equivalent output. `systemctl active` alone is not recovery. Physical HDMI observation and packet/CRC evidence are distinct requirements.

Gate reload success on observed data movement, not download completion: a bitstream can download with the FPGA manager reporting `operating` while the design's external devices (sensors, codecs) never resume, because hot reload loses boot-time implicit settling such as camera SCCB configuration. Insert an explicit timed settle before first use, then wait a bounded first-frame/first-transaction window with periodic slot/status reports and fail closed on timeout. For the EES-331 camera overlay, follow the proven per-board sequence in [references/ees331.md](references/ees331.md).

Use PYNQ's paired HWH clock divisors, then verify their meaning against the board's real reference clock/PLL state. Some Zynq PYNQ releases assume a 50 MHz reference clock; do not treat their reported MHz as a measurement on a 33.333 MHz board or change a system PLL to fix a display-only discrepancy.

## Evidence, failure, and handoff

- Stream stdout and stderr into durable host logs during execution; do not buffer until process exit. Flush board events, and use fsync at important checkpoints where power-loss retention matters — fsync applies to durable log files only; character devices and pipes reject fsync (EINVAL). Retain partial/truncated evidence rather than manufacturing a complete result.
- After timeout or lost communication, command execution is uncertain: do not auto-resubmit. Inspect existing events, current boot/service state, serial output, and safe metadata. Do not infer root cause solely from black HDMI or an extinguished PL LED when the new overlay intentionally omits them.
- If no safe control channel remains, stop and request the smallest required user action. After reboot, recover old logs before retrying. Distinguish recovery success from test success.
- Packet receivers joining a live stream should explicitly synchronize at a frame boundary and record startup discards; never silently forgive CRC/loss after synchronization or overwrite the initial failed observation.
- Report separately: RTL PASS, official-IP/BD PASS, build PASS, board function PASS, workload-restoration PASS, and main-project coexistence PASS. Independent PASS is not integration PASS; unimplemented BRAM/DMA/business features remain unaccepted.
- Publish only authorized, reviewed sources, reproducible entries and selected evidence. Project integration is not permission to merge a protected Git branch. Shutdown requires separate explicit authority and saved work; never force-close unrelated unsaved applications.
