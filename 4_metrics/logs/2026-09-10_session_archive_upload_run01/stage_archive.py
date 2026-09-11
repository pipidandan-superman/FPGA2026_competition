import hashlib,json,os,subprocess
from pathlib import Path
W=Path('E:/competition');T=Path('E:/competition_worktrees/FPGA2026_competition/pipidandan-superman')
R=Path(__file__).resolve().parent;REL=R.relative_to(W)
def run(args):
 p=subprocess.run(args,cwd=T,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 return p.returncode,p.stdout
checks={}
for folder,exe in [('sd_start_tool','EES331SDBootBuilder.exe'),('sd_start_tool_v0.2','EES331SDBootBuilder_v0.2.exe')]:
 dest=R/(folder+'_self_test.json')
 if not dest.is_file():
  rc,out=run([str(T/'8_tools'/folder/exe),'--self-test',str(dest)])
  (R/(folder+'_self_test_console.txt')).write_bytes(out)
  assert rc==0 and dest.is_file(),(folder,rc)
 checks[folder]=json.loads(dest.read_text())
 assert checks[folder]['result']=='FROZEN_GUI_SELF_TEST_PASS'
sources=json.loads((T/'8_tools/sd_start_tool_v0.2/source_hashes.json').read_text())
for name,expected in sources.items():
 p=T/'3_host/pynq/sd_boot_builder_v02'/name
 assert hashlib.sha256(p.read_bytes()).hexdigest()==expected,name
(R/'release_copy_validation.json').write_text(json.dumps({'result':'RELEASE_COPY_PASS','self_tests':checks,'v02_release_source_entries':len(sources)},indent=2),encoding='utf-8')
paths=(R/'delivery_paths.txt').read_text(encoding='utf-8').splitlines()
for name in ['delivery_paths.txt','archive_validation.json','skill_path_audit.txt','release_copy_validation.json','sd_start_tool_self_test.json','sd_start_tool_self_test_console.txt','sd_start_tool_v0.2_self_test.json','sd_start_tool_v0.2_self_test_console.txt','stage_archive.py']:
 src=R/name;dst=T/REL/name;dst.write_bytes(src.read_bytes());paths.append(dst.relative_to(T).as_posix())
paths=sorted(set(paths))
for start in range(0,len(paths),20):
 rc,out=run(['git','add','-f','--',*paths[start:start+20]])
 if rc:raise RuntimeError(out.decode(errors='replace'))
rc,names=run(['git','-c','core.quotepath=false','diff','--cached','--name-only','-z'])
staged=[s for s in names.decode().split('\0') if s]
assert set(staged)==set(paths),(set(staged)-set(paths),set(paths)-set(staged))
assert not any(p.startswith('2_fpga/') for p in staged)
rc,raw=run(['git','diff','--cached','--check'])
(R/'staged_whitespace_check.txt').write_bytes(raw)
editable=['README.md','HANDOFF.md','.gitattributes','.gitignore','7_logs/2026-09-09','7_logs/2026-09-10']
code_rc,code_out=run(['git','diff','--cached','--check','--',*editable])
(R/'editable_whitespace_check.txt').write_bytes(code_out)
# Raw captured evidence is intentionally not whitespace-normalized.
assert code_rc==0,'See editable_whitespace_check.txt; archived release assets keep their original CRLF/whitespace.'
for name,args in [('staged_stat.txt',['git','diff','--cached','--stat']),('staged_names.txt',['git','-c','core.quotepath=false','diff','--cached','--name-status'])]:
 status,content=run(args);assert status==0;(R/name).write_bytes(content)
result={'result':'STAGED_SCOPE_PASS','staged_files':len(staged),'frozen_paths':0,'exact_allowlist':True,'full_whitespace_exit':rc,'editable_whitespace_exit':code_rc,'raw_evidence_whitespace_preserved':bool(rc),'v02_source_hashes_match':True,'exe_selftests':checks}
(R/'staged_validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result))
