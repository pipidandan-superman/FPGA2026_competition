import hashlib,json,subprocess,shutil
from pathlib import Path
W=Path('E:/competition');R=Path(__file__).resolve().parent
T=Path('E:/competition_worktrees/FPGA2026_competition/pipidandan-superman')
def git(args,cwd=W):return subprocess.check_output(['git','-c','core.quotepath=false',*args],cwd=cwd)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(8*1024*1024):h.update(b)
 return h.hexdigest()
for name,args in {'source_status.txt':['status','--short','--branch'],'branches.txt':['branch','-avv'],'source_tracked_changes.txt':['diff','--name-status'],'source_staged.txt':['diff','--cached','--name-status'],'worktree_status_before.txt':['-C',str(T),'status','--short','--branch']}.items():
 if not (R/name).exists():(R/name).write_bytes(git(args))
if not (R/'source_frozen_diff_sha256.txt').exists():
 (R/'source_frozen_diff_sha256.txt').write_text(hashlib.sha256(git(['diff','--binary','--','2_fpga'])).hexdigest())
selected={}
def add(p,reason):
 p=W/p if not Path(p).is_absolute() else Path(p)
 assert p.is_file(),p
 rel=p.relative_to(W).as_posix()
 assert not rel.startswith('2_fpga/') and '__pycache__' not in rel and p.suffix.lower() not in {'.img','.zip','.mp4','.wdb','.wlf'},rel
 assert p.stat().st_size<50*1024*1024,(rel,p.stat().st_size)
 selected[rel]={'size':p.stat().st_size,'sha256':sha(p),'reason':reason}
def names(run,names,reason):
 for name in names.split('|'):add('4_metrics/logs/'+run+'/'+name,reason)
for ver in ['sd_boot_builder','sd_boot_builder_v02']:
 for p in (W/'3_host/pynq'/ver).iterdir():
  if p.is_file():add(p,'Versioned SD builder source and usage')
 for p in (W/'3_host/pynq'/ver/'assets').iterdir():
  if p.is_file():add(p,'Required embedded EES-331 boot assets; original source and SHA manifest retained')
for p in ['8_tools/sd_start_tool/EES331SDBootBuilder.exe','8_tools/sd_start_tool/README.md','8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe','8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe.sha256','8_tools/sd_start_tool_v0.2/README.md','8_tools/sd_start_tool_v0.2/source_hashes.json','8_tools/sd_start_tool_v0.2/example_build_config.json']:
 add(p,'User-facing Windows application; preserve v0.1 and deliver independently tested v0.2; no duplicate ZIP')
for p in ['AMD AIPC 借用报告 - 模板.docx','AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx','EES-331_PYNQ从零部署计划_2026-09-09.md']:
 add('1_docs/doc/'+p,'Requested report/template and PYNQ deployment plan')
for date in ['2026-09-09','2026-09-10']:
 for p in (W/'7_logs'/date).glob('*.md'):add(p,'Dated engineering plan, execution, validation and next-start records')
names('2026-09-10_pynq_v301_baseline_boot_run02','uart_pynq_log.txt','Raw board UART proves SD-to-Linux-shell boot only')
names('2026-09-10_sd_boot_static_audit_run01','DIAGNOSIS.md|audit.ps1|audit_console.txt|fsbl_readelf.txt','Original boot-header defect diagnosis and raw audit')
names('2026-09-10_sd_card_g_audit_run01','REPORT.md|check_sd.ps1|console.txt|file_hashes.json','Actual SD-card file identity before repair')
names('2026-09-10_sd_card_full_audit_run01','REPORT.md|final_result.json|scan_result.json|scan_console.txt|boot_and_file_comparison.json|partition_table.json|chkdsk_readonly.txt|fit_hash_checks.json|original_boot_dtb_comparison.json|evidence_sha256.json','Full-card read audit and original-image comparison')
names('2026-09-10_sd_boot_fix_run01','REPORT.md|candidate_validation.json|deploy_result.json|final_result.json|chkdsk_after_deploy.txt|deploy_20260910_160957_console.txt|bootgen_read_console.txt|bootgen_build_console.txt|fsbl_build_console.txt|uboot_external_dtb_proof.json|uboot_external_dtb_disassembly.json|ees331.dts|boot.bif|build_fsbl.ps1|make_fit_source.py|validate_candidate.py|fdt_reader.py|fit_inputs.json','Selected fix/deployment result, raw tools and reproduction sources')
names('2026-09-10_ees331_img_package_run01','REPORT.md|package_result.json|package_console.txt|fat_validation.json|block_verification.json|package_image.py|ees331_pynq_v3.0.1_ps_sd_20260910.img.sha256|uart_user_pasted.txt|uart_pasted_review.json','Full-image readback and hashes; multi-GB IMG stays local')
names('2026-09-10_sd_builder_toolkit_run01','REPORT.md|delivery_manifest.json|tests_console.txt|test_builder.py|frozen_self_test.json|frozen_build_config.json.result.json|full_rebuild_console.txt|fsbl_mode_console.txt|pyinstaller_console.txt|prepare_assets.py|package_delivery.py','Archived v0.1 implementation and raw verification')
v='2026-09-10_sd_builder_v02_run01'
names(v,'REPORT.md|test_v02.py|tests_release_console.txt|frozen_self_test_final.json|frozen_build_config.json|frozen_build_config.json.result.json|frozen_fsbl_config.json|frozen_fsbl_config.json.result.json|full_build_result.json|full_build_console_v2.txt|pyinstaller_final_console.txt|v01_preservation_result.json|v01_preserved_hashes.json|v01_tools_preserved_hashes.json|release_result.json|final_audit_result.json|mineru_reuse.json|gui_default.png|gui_advanced.png|alternate_xsa_rejection.txt|full_build.py|package_release.py|final_audit.py|ethernet_phy_binding.yaml|usb_nop_binding.yaml','v0.2 rules, release and retained raw verification; synthetic tests distinct from board proof')
for p in (W/'4_metrics/logs'/v/'dt_tests').rglob('*'):
 if p.is_file() and p.suffix in {'.dts','.dtb','.log'}:add(p,'Native DTC rule case input/output and raw compile messages')
for run in ['2026-09-10_sd_builder_v02_175423_0bb6c6','2026-09-10_sd_builder_v02_175742_16fccb','2026-09-10_sd_builder_v02_180104_171c99']:
 names(run,'result.json|hardware_analysis.json|device_tree_generation.json|fsbl_provenance.json|boot_validation.json|build.log','Real source/frozen application build provenance and raw log')
 for p in (W/'4_metrics/logs'/run).glob('command_*.log'):add(p,'Exact build command and tool output')
names('2026-09-10_sd_builder_v02_175423_0bb6c6','base_image_verification.json|output/image_validation.json|output/image_block_checks.json|output/ees331_pynq_sd.img.sha256','IMG identity and full readback evidence; IMG intentionally not committed')
names('2026-09-10_aipc_loan_report_run01','REPORT.md|artifact.md|create_report.py|authored_text.txt|package_audit.json|final_validation.json|fidelity_console.txt|fidelity_final/summary.json|final_sections.txt|template_sections.txt|final_styles.json|template_styles.json|mineru_result_marker.txt|mineru_results.json|input_manifest.json|mineru_runner_console.txt|mineru_api_stdout.txt|mineru_api_stderr.txt|fidelity_final/b_render/page-1.png|fidelity_final/b_render/page-2.png|template_render/AMD AIPC 借用报告 - 模板.pdf','Loan report source, template parsing failure disclosure and two-page final QA')
pbase=W/'4_metrics/logs/2026-09-10_aipc_template_pdf_run01'
for p in pbase.iterdir():
 if p.is_file() and p.suffix in {'.txt','.json'}:add(p,'MinerU PDF conversion fallback evidence and source hashes')
for p in (pbase/'AMD AIPC 借用报告 - 模板/auto').rglob('*'):
 if p.is_file() and p.suffix in {'.md','.json','.jpg','.png'}:add(p,'Complete selected template semantic parse and illustrations')
# Retain the actual source XSA outside the frozen tree as a small regression input.
input_copy=R/'reference_pynq_test_wrapper.xsa'
shutil.copy2(W/'2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa',input_copy)
add(input_copy,'313220-byte actual XSA used in the archived builds; read-only copy, frozen tree unchanged')
manual_run='2026-09-08_eth_zynq_psw_check_mineru_run01'
names(manual_run,'input_manifest.json|mineru_result_marker.txt|mineru_results.json|mineru_runner_console.txt','Board-template MinerU source identity and prior parse status')
manual=W/'4_metrics/logs'/manual_run/'EES-331 User Guide/auto'
for n in ['EES-331 User Guide.md','EES-331 User Guide_content_list.json']:add(manual/n,'Board manual parsed content used by EES-331 profile')
for p in (manual/'images').iterdir():
 if p.name.startswith(('6d100','8fc00','0ffe','a7dfa','0dcff')):add(p,'Selected UART/USB/QSPI board wiring images cited during profile checks')
# Keep the relevant competition parse, without bulk PDF/model outputs.
for run,stem in [('2026-09-09_amd_sait_pynq_mineru_run01','AMD赛题')]:
 for name in ['mineru_result_marker.txt','input_manifest.json','mineru_results.json']:
  p=W/'4_metrics/logs'/run/name
  if p.is_file():add(p,'PYNQ plan referenced competition-document parse metadata')
 for name in [stem+'.md',stem+'_content_list.json']:
  p=W/'4_metrics/logs'/run/stem/'auto'/name
  if p.is_file():add(p,'PYNQ plan referenced competition-document parsed content')
(R/'selected_manifest.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2),encoding='utf-8')
(R/'selected_paths.txt').write_text('\n'.join(sorted(selected))+'\n',encoding='utf-8')
print(json.dumps({'files':len(selected),'bytes':sum(m['size'] for m in selected.values()),'largest':sorted(selected.items(),key=lambda x:-x[1]['size'])[:6]},ensure_ascii=False,indent=2))
