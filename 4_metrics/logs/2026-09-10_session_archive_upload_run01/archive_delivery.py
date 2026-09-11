"""Explicit, hash-checked archive delivery. Run inspect, copy, then validate/stage."""
import hashlib,json,subprocess,sys,shutil,re
from pathlib import Path
W=Path('E:/competition')
T=Path('E:/competition_worktrees/FPGA2026_competition/pipidandan-superman')
R=Path(__file__).resolve().parent
REL=R.relative_to(W)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git','-c','core.quotepath=false',*args],cwd=T)
def save(name,data):
 (R/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
mode=sys.argv[1]
if mode=='inspect':
 m=json.loads((R/'selected_manifest.json').read_text(encoding='utf-8'))
 for rel in ['README.md','HANDOFF.md','.gitattributes','.gitignore']:
  p=W/rel;m[rel]={'size':p.stat().st_size,'sha256':sha(p),'reason':'Merged current documentation and byte-preserving Git archive policy'}
 for name in ['REPORT.md','prepare_archive.py','archive_delivery.py','source_status.txt','branches.txt','source_tracked_changes.txt','source_staged.txt','worktree_status_before.txt','source_frozen_diff_sha256.txt']:
  p=R/name;m[p.relative_to(W).as_posix()]={'size':p.stat().st_size,'sha256':sha(p),'reason':'Archive scope, reproduction commands and preflight audit'}
 save('selected_manifest.json',m)
 (R/'selected_paths.txt').write_text('\n'.join(sorted(m))+'\n',encoding='utf-8')
 lines=['# Binary and asset provenance','', 'Generated from the explicit reviewed selection. Source paths are relative to E:/competition. Source release/build evidence and reasons are in REPORT.md and selected_manifest.json. No IMG or duplicate ZIP is included.','', '| Source path | Bytes | SHA-256 | Reason |','|---|---:|---|---|']
 for p,v in sorted(m.items()):
  if Path(p).suffix.lower() in {'.exe','.bin','.elf','.xsa','.dtb','.scr','.docx','.pdf','.png','.jpg'}:
   lines.append(f"| `{p}` | {v['size']} | `{v['sha256']}` | {v['reason']} |")
 (R/'binary_manifest.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
 conflicts=[];existing=[]
 for rel,v in m.items():
  dst=T/rel
  if dst.exists():
   existing.append(rel)
   if sha(dst)!=v['sha256']:conflicts.append(rel)
 save('precopy_comparison.json',{'existing':existing,'different_existing':conflicts})
 print(json.dumps({'files':len(m),'bytes':sum(v['size'] for v in m.values()),'different_existing':conflicts,'existing':existing},ensure_ascii=False))
elif mode=='copy':
 m=json.loads((R/'selected_manifest.json').read_text(encoding='utf-8'))
 comparison=json.loads((R/'precopy_comparison.json').read_text(encoding='utf-8'))
 assert comparison['different_existing']==[],comparison
 for name in ['selected_manifest.json','selected_paths.txt','binary_manifest.md','precopy_comparison.json']:
  p=R/name;m[p.relative_to(W).as_posix()]={'sha256':sha(p),'size':p.stat().st_size}
 for rel,v in m.items():
  p=W/rel;dst=T/rel
  assert sha(p)==v['sha256'],rel
  dst.parent.mkdir(parents=True,exist_ok=True)
  if not dst.exists():shutil.copy2(p,dst)
  assert sha(dst)==v['sha256'],rel
 paths=sorted(m)
 (R/'delivery_paths.txt').write_text('\n'.join(paths)+'\n',encoding='utf-8')
 print(json.dumps({'copied_or_identical':len(paths),'mismatches':0}))
elif mode=='validate':
 paths=(R/'delivery_paths.txt').read_text(encoding='utf-8').splitlines()
 assert all(not p.startswith('2_fpga/') and Path(p).suffix.lower() not in {'.img','.zip','.wdb','.wlf'} and '__pycache__' not in p for p in paths)
 mismatches=[p for p in paths if sha(W/p)!=sha(T/p)]
 assert not mismatches,mismatches
 assets=[]
 for ver in ['sd_boot_builder','sd_boot_builder_v02']:
  a=T/'3_host/pynq'/ver/'assets'
  for n,v in json.loads((a/'manifest.json').read_text()).items():
   assert sha(a/n)==v['sha256'] and (a/n).stat().st_size==v['size'],(ver,n)
   assets.append(ver+'/'+n)
 frozen=subprocess.check_output(['git','diff','--binary','--','2_fpga'],cwd=W,stderr=subprocess.DEVNULL)
 assert hashlib.sha256(frozen).hexdigest()==(R/'source_frozen_diff_sha256.txt').read_text().strip()
 assert subprocess.check_output(['git','diff','--cached','--name-status'],cwd=W)==(R/'source_staged.txt').read_bytes()
 scan=[]
 patterns=[rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'github_pat_[A-Za-z0-9_]{40,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9]{32,}']
 for p in paths:
  if Path(p).suffix.lower() in {'.exe','.docx','.pdf','.png','.jpg','.elf','.bin','.xsa','.dtb','.scr'}:continue
  raw=(T/p).read_bytes()
  if any(re.search(pat,raw) for pat in patterns):scan.append(p)
 assert not scan,scan
 audit=subprocess.run(['powershell','-ExecutionPolicy','Bypass','-File',str(W/'4_metrics/scripts/audit_project_skill_paths.ps1')],capture_output=True)
 (R/'skill_path_audit.txt').write_bytes(audit.stdout+audit.stderr)
 assert audit.returncode==0
 result={'result':'ARCHIVE_CONTENT_VALIDATION_PASS','selected_files':len(paths),'bytes':sum((T/p).stat().st_size for p in paths),'hash_mismatches':mismatches,'asset_entries_verified':len(assets),'source_frozen_diff_unchanged':True,'source_index_unchanged':True,'secret_pattern_matches':scan,'skill_path_audit_exit':audit.returncode,'hardware_action':'NONE','large_images_rehashed_this_archive':False}
 save('archive_validation.json',result)
 print(json.dumps(result,ensure_ascii=False))
else:raise SystemExit('Expected inspect, copy, or validate')
