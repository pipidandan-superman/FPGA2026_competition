# Vivado OOC synthesis error impact analysis

Date: 2026-09-03
Status: IMPLEMENT_AND_BITSTREAM_PASS / OOC_ERRORS_NONBLOCKING

## Observed condition

The Vivado Messages window shows three errors under `Out-of-Context Module Runs`, while `synth_1` reports `synth_design Complete!` and `impl_1` reports `write_bitstream Complete!`. The errors are all `[Common 17-1257] Failed to create directory 'C'.` in OOC IP submodule synthesis logs.

## Detailed evidence

- `display_test_util_vector_logic_0_0_synth_1/runme.log:30` reports the directory error, but the same log reports synthesis success and the run directory contains its generated DCP and `__synthesis_is_complete__` marker.
- `display_test_rst_ps7_0_50M_0_synth_1/runme.log:30` reports the same directory error; the run directory also contains its generated DCP and completion marker.
- `display_test_axi_mem_intercon_imp_xbar_0_synth_1/runme.log:290` reports the directory error; line 15 additionally reports an earlier write error. The run still generated its DCP and completion marker, and its synthesis later completed successfully.
- `display_test_v_tc_0_0_synth_1/runme.log:15` also contains the same directory error in the current project artifacts; the run generated its DCP and completion marker.

The error occurs during the generated OOC run's `create_project -in_memory` setup under Vivado 2025.2. It is therefore a project/tool run-management or path-handling symptom, not an RTL elaboration or synthesis result error.

## Parent-flow result

- Top-level `synth_1` contains `display_test_wrapper.dcp` and `__synthesis_is_complete__`.
- `impl_1` generated placed, phys-opt, routed, and final DCPs.
- `impl_1/runme.log` explicitly reports `place_design completed successfully`, `route_design completed successfully`, and `write_bitstream completed successfully`.
- `impl_1/display_test_wrapper.bit` was generated at 15:05:45 with size 4,045,696 bytes.
- Route status reports 10,921/10,921 routable nets fully routed and zero routing errors.
- Routed timing reports global WNS/TNS = `10.551/0.000 ns`, WHS/THS = `0.023/0.000 ns`.
- `cam_pclk` domain setup WNS is `35.138 ns`; hold WHS is `0.070 ns`.

## Impact decision

These OOC errors do not invalidate the completed implementation or the generated bitstream because every referenced submodule produced a usable DCP, the parent flow completed all stages, all routable nets are routed, and setup/hold timing passes. The GUI error count is not a reliable standalone pass/fail indicator when the affected child run subsequently completed and generated its expected checkpoint.

The condition should still be treated as undesirable project hygiene. If the user wants a clean zero-error synthesis console, the affected OOC runs should later be reset/regenerated after archiving this evidence and confirming no project file is open by another process. This cleanup is optional for the current bitstream and does not block board validation.

PLAN_A_IMPLEMENT_AND_BITSTREAM_PASS
