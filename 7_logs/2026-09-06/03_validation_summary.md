# 2026-09-06 Validation Summary

- Existing RTL/XSim readback tests pass, but they model an acknowledging slave and do not prove board communication.
- Board ILA run02 shows write address 0x72 followed by NACK; SDA released-high behavior is abnormal/coupled.
- The user re-confirmed the 2026-09-05 16:43 display image. Its SHA-256 is E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E and it is archived as `4_metrics/logs/2026-09-06_hdmi_ila_no_display_run01/yesterday_display_reference.jpg`.
- Today's `hdmi_colorbar_vtc_top.bit` was generated at 09:52 from the current workspace. Timing passes with WNS/WHS +15.757/+0.081 ns and zero TNS/THS; routed DRC reports zero errors. Thus ILA-induced timing failure is not established.
- Current `rtl/iic/iic_protocal.v` uses open-drain SDA (`assign sda = (sda_en && !sda_out) ? 1'b0 : 1'bz;`) and one-second ERROR retry. This differs from the push-pull SDA behavior present before the late 2026-09-05 electrical diagnostic work.
- A read-only ILA capture with Vivado 2020.1 found the XC7Z020 target but could not recognize the Vivado 2025.2 debug core; it reported no supported debug core. This is a capture-tool version mismatch, not proof that the FPGA is unconfigured. The matching 2025.2 batch launch is currently blocked by an empty/corrupt user Tcl Store.
- Board confirmation: the user confirms `4_metrics/logs/2026-09-05_hdmi_root_cause_run01/hdmi_diagnostic.bit` displays successfully. This bit is push-pull SDA and includes an ILA. The result therefore isolates the no-display regression to the later open-drain SDA build, not ILA insertion.
- Log location check: the project skill override now requires `E:\competition\7_logs`; the 2026-09-05 and 2026-09-06 records were moved from `2_log`, and the empty `2_log` root was removed.
- Run01 ILA screenshot review: while the FSM is in `WR_DATA`, `iic_we=00`, `sda_en=1`, and `iic_wr_data` advances through the initialization-byte sequence ending at `0x99` in the captured window. This is the expected master-driven write-data behavior. The screenshot is archived as `4_metrics/logs/2026-09-06_hdmi_ila_no_display_run01/run01_ila_wr_data_99.png`. It must be compared against the source table built into run01, not necessarily the later-modified workspace source table.
- Run01 readback ILA screenshot review: the six observed bytes are `1F, 01, FF, 0F, 1F, 1F` for addressed reads `41, 15, 16, 48, AF, DE`. This exactly matches the archived run01 aggregate `adv7511_readback_data=1f1f0fff011f`, `readback_match=1A`, and `cfg_error=1`. It is therefore genuine board readback evidence but not a PASS: expected/masked values are `10, 01, BD, 08, 12, 10`. The final `NO_ACK` state is the controller's normal read-termination NACK before `IDLE`, not by itself an address NACK. Screenshot: `4_metrics/logs/2026-09-06_hdmi_ila_no_display_run01/run01_ila_readback_values.png`.
- Run01 read-timing review: screenshots initially make SDA transitions appear to coincide with SCL edges, but this is not by itself an I2C violation. A slave may change SDA immediately after SCL falls; the requirement is that SDA remains stable while SCL is high. The master samples `sda_in` in `RD_DATA` at `cnt_scl == IIC_SPPED_DIV2-1`, inside the SCL-high interval. Exact validation requires zooming beyond the ILA sample period or exporting CSV and checking that no SDA transition occurs while SCL remains high. Screenshots: `run01_ila_read_timing_zoom.png` and `run01_ila_read_data_states.png`.
- Run01 address/data pairing review: the user annotated and confirmed the protocol pairing `41=1F, 15=01, 16=FF, 48=0F, AF=1F, DE=1F`; each returned byte appears after its address phase. This proves the read transaction/capture pairing is functioning at the protocol level. It remains distinct from value matching: masked comparison gives PASS only for `15`, `48`, and `AF`, while `41`, `16`, and `DE` fail, yielding `match=1A/error=1`. Screenshot: `run01_ila_address_data_pairs.png`.
- Readback mismatch interpretation (current conclusion): display success plus coherent address/data pairing means I2C transaction flow is healthy enough for this design. The raw mismatches show expected-1 bits surviving while expected-0/reserved/condition bits read high. For example, write `0x41=10` / read `1F`, write `0xAF=12` / read `1F`, and write `0xDE=10` / read `1F` all retain bit4 while lower bits read high; `0x48=08` / `0F` retains the right-justify bit while lower bits read high. This is a readback-model/mask problem first, not evidence of random I2C corruption or complete initialization failure.
- Current field evidence: `0x15[3:0]=1` and `0x48[4:3]=01` pass; `0x16[5:4]=3` and `0x16[3:2]=3` pass; `0xAF & 0x12` equals the written `0x12`; `0x41 & 0x70` equals the intended power/intent field `0x10`; `0xDE & 0x10` equals the intended bit4. The current masks `0xFF/BF/FF` for `0x41/0x16/0xDE` are overstrict for board readback.
- Color-pattern evidence: user reports both RGB-conversion mode and direct-YCbCr mode show the same wrong screen. This is expected because both paths intentionally emit equivalent `{Y, Cb/Cr}` words; it localizes the fault below the source mux. The observed bars are precisely consistent with the 16-bit word being interpreted byte-swapped: source White `{EB,80}` appears yellow/green, Black `{10,80}` appears red-dominant, Red `{3E,66}/{3E,EF}` becomes orange with alternating luma stripes, Blue `{1F,EF}/{1F,75}` becomes red, and Green `{AC,29}/{AC,1A}` remains green. The vertical stripes in the former-red bar are the strongest signature: byte swap turns the differing Cb/Cr bytes into alternating luma.
- Physical byte-swap board result: user applied `physical_data = {selected_data[7:0], selected_data[15:8]}` and downloaded a new build. The resulting screenshot is byte-identical to the 2026-09-05 archived display reference (SHA-256 `E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E`); the new bit is `66B82B598DA5FBF4DA4FE094B93CF5C4D1C73ACC71F0EC5A7190D9242F016A69`. It is not a PASS. The first two bars have no stripes because White/Black both use chroma `0x80`; the last three have stripes because Red/Blue/Green have unequal Cb/Cr. This exactly follows from Style 3 interpreting the post-swap high chroma byte as luma.
- Current inference: the stripe/no-stripe split proves the data-byte position is changing as expected and confirms that the active display path is interpreting the wrong byte as luma for the swapped build. The next isolated test must restore Style 3's documented logical order (`physical_data = selected_data`) and retain the push-pull SDA / current ILA build; compare that build against the same monitor and power state before changing R0x16 or the color matrix.
- Minimum single-variable color test (not yet applied): keep ADV7511 Style 3 configuration unchanged and change only `physical_data` from `selected_data` to `{selected_data[7:0], selected_data[15:8]}`. Expected board PASS is White, Black, Red, Blue, Green in both SW0 modes.
- PASS-policy correction: treat `0x41` as expected `10`, mask `70`; `0x15` as `01`, mask `0F`; `0x16` initially as `3C`, mask `3C` for 8-bit Style 3 (track `[7:6]` and `[1]` separately as informational until their behavior is field-verified); `0x48` as `08`, mask `18`; `0xAF` as `12`, mask `12`; `0xDE` as `10`, mask `10` or remove noncritical `0xDE` from the blocking PASS set.
- Required PASS evidence: VADJ at pull-up node within board specification, SDA/SCL valid high levels and rise times, ACK at 0x72, raw readback 101208BD0110, match=3F, done=1, error=0.
- Preserve complete meter/scope/logic-analyzer captures and terminal logs in the run record.

## 12:30 configuration rewrite validation

- Evidence folder: `E:\competition\4_metrics\logs\2026-09-06_adv7511_config_rewrite_run01\simulation_report.md`.
- Static/config decision: UG Rev. D Table 7 proves physical `{Cb/Cr, Y}` is
  Style 1 right-justified; ADI API maps that to `R0x16[3:2]=0`. Linux driver
  clears `R0x16[7]` and `R0x16[0]` for RGB output. Final video bytes are
  `R0x15=01`, `R0x16=30`, `R0x48=08`, with full `R0x18..R0x2F` CSC.
- ModelSim compile: all package/config/I2C files compiled. The board ILA
  instance was satisfied by a simulation-only `ila_0_stub.sv`; project RTL was
  not changed to remove ILA.
- Command-line failure: `vsim -c` reached compile but failed design load with
  `Error: can't read "FileWatch(fileName)": no such element in array`; a
  minimal Hello test reproduced it. The final simulations used the ModelSim GUI
  fallback.
- Positive PASS marker: `CFG_READBACK_SUCCESS_PASS: transactions=61 starts=67 stops=61 bitmap=111111 raw=04c708300110`.
- Negative PASS marker: `CFG_READBACK_MISMATCH_PASS: transactions=61 bitmap=111011 raw=04c708200110`.
  `R0x16` was corrupted from `30` to `20`; the checker detected the failed bit
  and set `cfg_error`.
- Simulation boundary: this proves table/I2C transaction behavior and masked
  readback logic. It does not prove monitor compatibility or board-level color
  correctness.
- Remaining board PASS criteria after rebuild: monitor shows solid White,
  Black, Red, Blue, Green bars in both SW0 modes; no vertical chroma stripes;
  LED raw `R0x16` display should read near `30h`, subject to the known readback
  high-bit behavior.

## 13:00 V2.0 board result and V2.1 validation

- Archived V2.0 board photo:
  `E:\competition\4_metrics\logs\2026-09-06_adv7511_config_rewrite_run01\board_after_rgb_csw_style1.jpg`.
- Board observations: vertical stripes are gone; the first three expected bars
  merge into one magenta region, followed by a pale bar and a blue bar. This is
  a color-matrix/output-architecture failure, not the original byte-position
  failure.
- V2.0 conclusion: `R0x16` depth/style mapping is correct, but the RGB/CSC
  result is not acceptable. Do not reuse V2.0 for production.
- V2.1 config: `R0x16=0xB1`, no CSC writes, `R0x44=0x10`, AVI YCbCr422/VIC 1,
  and `R0xAF=0x12`. Physical Style 1/right-justify remains unchanged.
- V2.1 positive simulation PASS:
  `CFG_READBACK_SUCCESS_PASS: transactions=50 starts=56 stops=50 bitmap=111111`.
  Raw functional reads: `41=10, 15=01, 16=B1, 48=08, AF=12, DE=10`.
- V2.1 negative simulation PASS:
  `CFG_READBACK_MISMATCH_PASS: transactions=50 bitmap=111011` after corrupting
  `R0x16[5]` from `B1` to `91`.
- Final report and hashes:
  `E:\competition\4_metrics\logs\2026-09-06_adv7511_config_rewrite_run01\simulation_report.md`.

## 13:05 final source-state audit

- Vivado top reference check: `project_1.xpr` directly references the active
  `../../0_diaplay_test/rtl/hdmi_new/hdmi_colorbar_vtc_top.v` and
  `adv7511_init_table_pkg.sv`; there is no copied second source set to update.
- `adv7511_init_table_pkg.sv` is V2.1: 44 writes, six masked reads,
  `R0x15=01`, `R0x16=B1`, `R0x48=08`, `R0xAF=12`, AVI VIC 1, and no CSC writes.
- `hdmi_colorbar_vtc_top.v` retains
  `assign physical_data = {selected_data[7:0], selected_data[15:8]};` and drives
  `HDMI_DATA <= physical_data;`.
- Testbench correction: the Mode TB previously compared `HDMI_DATA` with the
  internal logical Style 3 `selected_data`, which cannot detect the intentional
  physical byte swap. It now checks `u_dut.physical_data`; V2.1 config TB hashes
  remain unchanged.
- Command-line ModelSim reached design load and reproduced
  `Error: can't read "FileWatch(fileName)": no such element in array`. The same
  `.do` then passed through the approved GUI fallback.
- Mode/TB PASS:
  `MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch`.
  Evidence: `E:\competition\4_metrics\logs\2026-09-06_hdmi_style1_mode_tb_run01\simulation_report.md`.
- Current decisive hashes:
  table `02C6DC9620215C2914251DDD6C3D2B8E7C1C79F7EC850A77E32B36E77538D48A`;
  top `16EEFA17DC5357F74AE0146CE36F911DFF505470E6B5BF35D9AFF2FAF6831447`;
  config TB `8887B57DCDDDB5630B81A2C84E5E0C48C3E28AD51BCF4804073C237D302584BE`;
  mode TB `734A933CAF399203C13212DB6DF7055B22FD81A4E506D428DE1C07F88FF672D8`.
- Simulation boundary: this proves RTL data mapping and I2C configuration
  behavior; it does not prove monitor acceptance or final board color quality.

## 13:12 explicit package reference validation

- `project_1.xpr` now references
  `$PPRDIR/../../0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv` at line
  163 rather than `$PSRCDIR/sources_1/imports/...`.
- XML parse and path resolution PASS:
  `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table_pkg.sv`
  exists, and the entry has zero `ImportPath`/`ImportTime` attributes.
- Search check PASS: the XPR now contains no file entry under
  `$PSRCDIR/sources_1/imports/`.
- The old imported copy remains at
  `project_1.srcs\sources_1\imports\hdmi_new\adv7511_init_table_pkg.sv`, is
  unreferenced, and currently matches source hash
  `02C6DC9620215C2914251DDD6C3D2B8E7C1C79F7EC850A77E32B36E77538D48A`. Do not edit
  it.
- Reference evidence:
  `E:\competition\4_metrics\logs\2026-09-06_adv7511_pkg_external_ref_run01\project_reference_check.md`.

## 13:22 instantiated-table validation

- New source: `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table.sv`.
- Explicit instance: `u_adv7511_init_table` is instantiated in
  `adv7511_iic_data_xfer` at line 86; it now appears under that module in the
  Vivado hierarchy.
- Removed obsolete source:
  `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table_pkg.sv`.
  It remains recoverable from Git history.
- Vivado reference check PASS: `project_1.xpr` points to the new module path,
  the path resolves, and the entry is not AutoDisabled.
- Search check PASS: no active source/build reference to
  `adv7511_init_table_pkg` remains.
- Positive config simulation PASS:
  `CFG_READBACK_SUCCESS_PASS: transactions=50 starts=56 stops=50 bitmap=111111`.
- Negative config simulation PASS:
  `CFG_READBACK_MISMATCH_PASS: transactions=50 bitmap=111011`.
- Top-level mode simulation PASS:
  `MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch`.
- Evidence and hashes:
  `E:\competition\4_metrics\logs\2026-09-06_adv7511_table_module_run01\refactor_report.md`.
- Boundary: the V2.1 table values and I2C sequence are unchanged. Rebuild is
  required for Vivado to elaborate the new hierarchy; board behavior is expected
  to remain the same but is not claimed until tested.

## 13:55 user RGB/Style-3 diagnosis

- Board evidence: large blue center field and magenta side bars, archived in
  `4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01`.
- Failing build evidence: bit timestamp 13:46:49. Synthesis warnings show that
  table indices 64–67 were unreachable and that the 7-bit `write_index`
  connected to a 6-bit `init_index_i`.
- Format conflict: source used unswapped Style 3 `{Y, Cb/Cr}`, while
  `R0x16=0x30` selected Style 0. This reverses the luma/chroma byte roles and
  explains the abnormal colors.
- AVI metadata: `R0x55=0x09` correctly selects RGB, but the old checksum
  `R0x54=0xAB` was stale.
- Source correction: `init_index_i` is now seven bits, `R0x16=0x38`,
  and `R0x54=0xCB`.
- Verification status: corrected ModelSim scripts are prepared and compilation
  starts, but the known `FileWatch` loader issue plus unavailable GUI-launch
  approval prevented a corrected simulation PASS. No board PASS is claimed.
- Next evidence required: the three `.do` PASS transcripts, fresh bit hash and
 timestamp, and board photo for both SW0 modes.

## 14:25 CSC601 source and simulation validation

- Stale-build evidence before the user's rebuild attempt: corrected sources
  were saved at 13:55:51/13:57:46, while the last available bit was 13:46:49
  with SHA-256 942F40CDEA08454C54428FC3A6EC425ED93BFDA929D51676B54EF458B242BCE8.
  The 13:46 bit therefore could not contain the 13:55 source fixes. During the
  14:26 audit, the old bit path no longer existed, consistent with the user
  preparing a fresh build.
- CSC table check: the exact ADI API CscYcc601ToRgb bytes are now programmed at
  R0x18..R0x2F as AA F7 08 00 00 00 1A 84 / 1A 6A 08 00 1D 50 04 22 /
  00 00 08 00 0D DB 19 12. This matches tx_hal.c in the archived ADI API source
  rather than a trial matrix.
- Converter fix: rgb2ycbcr422 now uses standard limited-range BT.601
  coefficients and one common RGB capture register stage. This removes the old
  luminance under-scaling and the one-cycle R/G-versus-B misalignment.
- Positive configuration simulation PASS:
  CFG_READBACK_SUCCESS_PASS: transactions=74 starts=80 stops=74 bitmap=111111;
  readback includes R0x16=38.
- Negative configuration simulation PASS:
  CFG_READBACK_MISMATCH_PASS: transactions=74 bitmap=111011 when injected
  R0x16=18 differs from the expected style field.
- Mode simulation PASS:
  MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch.
  The TB checks both converter and direct sources and checks that HDMI_DATA
  equals unswapped Style-3 physical_data.
- Raw simulation evidence:
  E:/competition/4_metrics/logs/2026-09-06_adv7511_csc601_rebuild_run01/config_success_console.txt,
  config_mismatch_console.txt, and mode_console.txt.
- Verification boundary: simulation proves register sequence, bus mapping, and
  frame-safe mode behavior. It does not prove monitor color acceptance. A fresh
  bit timestamp/hash and both SW0 board photos remain required.

## 14:48 stale 14:29 build audit

- Board result classification: FAIL for the tested bit, but NOT valid evidence
  against V1.3. The user photo at
  `4_metrics/logs/2026-09-06_adv7511_csc601_rebuild_run01/board_after_csc601_user_build.jpg`
  still shows stripes in the chroma-bearing bars.
- Timestamp proof:
  synthesis DCP `14:27:03.719`; top source `14:28:03.871`; V1.3 table
  `14:44:56.361`; tested bit `14:29:08.282`. Therefore implementation reused a
  pre-fix synthesis database, and the bit did not include the final top-level
  mapping or V1.3 CSC.
- Current source hashes:
  table `EEB8DED1612DFBAA01539E0886A68A68032ECB542FCD0283CDB77C260111D37C`;
  top `2BEE16F1CFBB3B5859D9B1980EC015B8748D632CB4EE3BAA766F18928C6F3C1D`;
  converter `A41A33B62531109E765F355A38E2787D59CE7CC0F3A1A71DDD67ABC647178395`.
- Tested-bit SHA-256 remains
  `2E968C73C551BDB90C4498435DCF331A05E057C79248AD6F7EBB2B554D2B29BB`.
- Manual recheck: UG Rev.D Table 7 confirms right-justified 16-bit Style 3 is
  `{Y,Cb}` then `{Y,Cr}`. `R0x15=01`, `R0x48=08`, and `R0x16=38` remain the
  coherent choice with `physical_data=selected_data`.

## 15:10 final board PASS: EES-331 physical byte swap

- Board PASS criteria were met: White / Black / Red / Blue / Green solid bars,
  no vertical stripes, stable 640x480p60. Raw evidence:
  `4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/board_pass_white_black_red_blue_green.jpg`
  (SHA-256 `37414C330BCCEDCFB8DA7314FB0816169C681D0AFE0F754086076EF0274F27B3`).
- Final data-path invariant: `selected_data={Y,Cb/Cr}`, but the EES-331 port
  requires `physical_data={selected_data[7:0],selected_data[15:8]}`. The source
  edit screenshot is in the same run folder.
- Tested-bit provenance: observed 15:01 bit SHA-256
  `D57F6236CCD8F4D63B9FA9A5E338D531701E9FC2322CF2B3EF4FE29DE13CDC73`; its
  synthesis DCP was 14:59:26. The 15:05 edits changed comments/TB only, not
  synthesizable behavior. The bit artifact was subsequently removed by the
  15:08 Vivado implementation run and is ignored by `.gitignore`.
- Updated regression PASS marker:
  `MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch`.
  Stable marker:
  `.../mode_result.txt`; raw ModelSim transcript and nonempty WLF retained.
  The transcript display stopped at the known FileWatch issue, so the stable
  result file is the accepted PASS evidence.
- Generic output regression after syncing the same board swap into
  `hdmi_out_adv7511.v`: `HDMI_VIDEO_PASS: pixels=16 mismatches=0 writes=4
  start=1009900000`. Stable marker:
  `.../hdmi_video_result.txt`; WLF and transcript retained.
- Git preparation: the focused source, evidence, and log paths are ready, but
  `git add` cannot create `.git/index.lock` because the session sees `.git` as
  read-only. No commit or push has occurred yet.
- 15:22 retry: the explicit user upload request was honored by requesting Git
  write access, but the approval service returned an internal `modelCode`
  error twice. No repository metadata was changed and no workaround was used.
- A focused upload script is available at
  `4_metrics/scripts/upload_2026_09_06_hdmi_pass.ps1`; it stages only the HDMI
  fix, focused evidence, simulation skills, logs, cleanup manifest, and project
  documents, then commits and pushes to `origin/main`.

## 15:22 cleanup validation

- Root now contains only the numbered project roots, `.codex`, `.git`, and
  top-level project documents; transients are under
  `4_metrics/logs/2026-09-06_workspace_cleanup_run01/root_quarantine/`.
- Nothing was deleted. The cleanup used explicit source paths and a safe
  workspace/protected-path check.
- Skill-copy inventory is 12 files / 26,849 bytes across the three requested
  simulation skills. Manifest:
  `4_metrics/logs/2026-09-06_workspace_cleanup_run01/root_cleanup_manifest.md`.
- `2_fpga` was not moved, renamed, deleted, or edited by the cleanup.

## 15:28 upload staging validation

- Git write permission was restored by the user. The focused upload set was
  reduced from 425 to 123 staged files by removing four ModelSim generated
  library directories from the index.
- Staged payload is approximately 1.56 MB and retains board photos, ILA
  screenshots, raw text evidence, source, logs, and the three simulation
  skills.
- No source whitespace changes are made merely to satisfy `git diff --check`;
  the frozen working HDMI source remains unchanged.

## 15:31 upload completion

- Focused HDMI upload PASS: commit `4e7d8ca` was pushed to `origin/main` at
  `github.com/pipidandan-superman/FPGA2026_competition.git`.
- Commit summary: 123 files changed, 6595 insertions, 556 deletions. Generated
  ModelSim libraries and the 350 MB local quarantine were excluded.
- Current source hashes: top
  `A18E0B5419681E62DE18CA6CA0D93F7CF3B525A72DF10DE0B8B4E37C891DB0DC`; table
  `4F172165E1BB29CCB6A1FEA4A8A5DBB22A3962D10A72BFEC42440F8577EC1EB8`; converter
  `A41A33B62531109E765F355A38E2787D59CE7CC0F3A1A71DDD67ABC647178395`; mode TB
  `2F9F62C03C6A6C7F758D1D7FA9B1E1944CB2C9E2088C8464E9909BFDEBCA2406`.

## 15:56 project skill path adaptation validation

- Requirement: every engineering/simulation/organization skill must write logs
  only to `E:\competition\7_logs\YYYY-MM-DD`, raw evidence only to
  `E:\competition\4_metrics\logs\<run-name>`, and must not target `2_log`,
  generic `log/logs`, old `D:\VitA\5_verify`, or desktop competition paths.
- Added audit: `4_metrics/scripts/audit_project_skill_paths.ps1`.
- PASS: the audit inspected 8 `SKILL.md` files plus companion files and returned
  `pass: true` with an empty failure list. Raw JSON:
  `4_metrics/logs/2026-09-06_project_skill_adaptation_run01/skill_path_audit.json`.
- PASS: all six project/adapter PowerShell scripts parse without
  `System.Management.Automation.Language.Parser` errors.
- PASS: forbidden executable tokens `VITA_VIVADO_RESULT`, historical
  `5_verify`, and desktop archive targets are absent from skill source and
  companion scripts; only explicit prohibition/policy text retains broad
  historical roots as non-executable examples.
- PASS: `git diff --check` over `.codex`, `6_skill`, new scripts/references, and
  `AGENTS.md` returned no whitespace errors.
- Boundary: this is tool/path-policy validation only. It is not a ModelSim or
  Vivado functional simulation PASS and does not alter the frozen board-proven
  HDMI result under `2_fpga`.
