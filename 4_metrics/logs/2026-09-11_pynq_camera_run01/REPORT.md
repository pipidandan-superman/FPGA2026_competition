# SD/PYNQ camera migration, 2026-09-11

Scope: user authorized new development in `E:/competition/2_fpga/0_diaplay_test/pynq`, deployment on the SD-booted board and functional HDMI/UDP validation. Existing RTL/BD/Vitis files are preserved.

## Baseline and raw evidence

- `user_sd_boot.txt`: user-provided SD Linux startup UART.
- `user_jtag_viewer.png`: user-provided successful standalone viewer screenshot; not PYNQ evidence.
- `baseline_hashes.json`: current XSA/main.c/HWH hashes.
- `serial_session.raw`: COM6 bytes from network diagnosis and reboot observations. Initial printing failed on Windows GBK, but the raw bytes had already been saved; later console encoding was corrected.
- `preflight.log`, `xrt_env.log`, `overlay_load_attempt01.log`, `overlay_load_attempt02.log`: installed PYNQ 3.0.1 runtime, initial missing XRT environment, and successful Overlay/FPGA manager/VDMA/allocate checks.
- `memory_mapping.log`, `reboot_cma.log`: PL master windows and verified `cma=128M@0x10000000` boot parameter.
- `hdmi_attempt01.log`: 15-second run, 76 stable snapshots, 445 observed read/write pointer transitions, no VDMA errors, clean halt and free.
- `combined_complete.log`: 120-second joint run, 600 sent frames / 384000 UDP packets, 4.9994 fps, no VDMA errors, clean halt and free.
- `pc_live/pc_stats.jsonl`, `pc_combined_saved_status.json`: receiver snapshot recorded 582 complete frames / 372480 packets at 116.188 seconds; CRC, loss and bad-header counters absent in Counter mean zero. This final saved snapshot precedes the sender's 600-frame completion; do not claim all 600 were counted in this saved snapshot.
- `pc_live/pc_first.png`, `pc_live/pc_latest.png`: images rendered through the existing viewer; raw BGR snapshot preserved alongside.
- User explicitly confirmed: both HDMI and PC show normal camera images that change with movement in front of the lens.
- `protocol_test.txt`: existing PC decoder compatibility, corruption rejection, missing packet rejection, three tests passed.

## Changes and evidence boundaries

Linux PHY is Marvell 88E1510 at 1 Gbps full duplex. Initial 192.168.240.10 ping timeout was an IP mismatch: Linux used 192.168.2.99. Adding the board address restored connectivity; no PHY repair was needed.

PL SCCB and ADV7511 configuration are already implemented in RTL. The new application controls VDMA and manages continuous physical memory using pynq.allocate, with explicit cache invalidation for CPU snapshots and Linux socket sending. It does not use a fixed unreserved physical frame address.

Default CMA returned 0x38100000, outside current interconnect decoding. uEnv.txt reserves CMA inside the proven HP1 window; runtime allocation verified at 0x10100000. Original BOOT.BIN/IMAGE.UB/BOOT.SCR remain unchanged. Board-side configuration backups are retained.

## Restart regression and resolution

The first automatic service start after reboot loaded PL but timed out waiting for the S2MM first frame. `autostart_failure_full.log` preserves the failure. VDMA was stopped and memory released. Manual joint-run PASS must not conceal this autostart failure.

The bare-metal app initializes Ethernet before VDMA, supplying implicit sensor settling time; the Python service did not. A one-second delay between Overlay download and VDMA reset was tested with failure register logging (`camera_sensor_settle.py`). That alone did NOT fix the failure; `sensor_settle_failure_detail.log` shows S2MM 0x15810 with RS still set.

The actual gating defect was waiting for S2MM pointer rotation before the baseline's one-time startup acknowledgement. Restored the main.c sequence: MM2S first, log/acknowledge camera startup framing flags once, then require NEW MM2S and S2MM transitions. Persistent or later errors stop the run; no repeating clears/restarts. The error mask now also checks EOLLateErr (bit 15). Revised source is archived as `camera_startup_ack.py`.

After SD software reboot, service automatically loaded the overlay and allocated 0x10100000. Startup S2MM 0x15810 was recorded and cleared once; both channels then reached 0x11000 with new frame transitions. `full_service_journal_final.log` proves service enabled/active and error-free heartbeats for more than 120 seconds after streaming began.

`pc_final_status.json`: 604 successfully decoded AND GUI-rendered frames after 124.125 seconds, source 192.168.240.10, CRC/lost/duplicate/bad-header/short/bad-geometry counters all zero. `pc_final.png` is the received image; `pc_reboot/pc_stats.jsonl` records progression. Startup CPU contention lowers the initial average; normal transmission is configured to 5 fps. This is software-reboot verification, not a power-cycle test.

Final code hash: camera.py `c2e8a0da0669b19b3bc8e2c656e5ad693e1a0cf8d16b0c3a9b4c68d453600bcb`, matched between PC and board. `baseline_unchanged.json` verifies XSA/main.c unchanged; final boot file hashes match `before_boot_config.log`.

**Result: PYNQ_CAMERA_HDMI_UDP_PASS; SD_REBOOT_AUTOSTART_PASS.** HDMI visual acceptance is the user's explicit observation during the joint run; reboot acceptance combines service/VDMA logs and fresh PC frames. Service and PC viewer are left running.

`board_evidence.tar.gz` preserves board-side first/last frames and results. An attempted unprivileged journal redirect into the root-owned evidence directory failed; the complete service journal was subsequently captured directly to the PC in `full_service_journal_final.log`.

## Tool limitations

Desktop automation backends could not import their runtime packages. Used serial/SSH and the existing PC GUI code with a recording subclass instead. A rejected deletion of the temporary current.hwh was abandoned; the extracted file was retained, and no delete workaround was used.
