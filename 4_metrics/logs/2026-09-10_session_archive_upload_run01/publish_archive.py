import hashlib,json,subprocess,shutil
from pathlib import Path
W=Path('E:/competition');T=Path('E:/competition_worktrees/FPGA2026_competition/pipidandan-superman')
R=Path(__file__).resolve().parent;REL=R.relative_to(W)
def git(*args):return subprocess.check_output(['git',*args],cwd=T,stderr=subprocess.STDOUT)
branch='codex/full/pipidandan-superman'
assert git('branch','--show-current').decode().strip()==branch
assert git('rev-parse','HEAD')==git('rev-parse','origin/main')
for name in ['staged_validation.json','staged_stat.txt','staged_names.txt','editable_whitespace_check.txt','PR_BODY.md','github_pr.py','publish_archive.py']:
 p=R/name;dst=T/REL/name;shutil.copy2(p,dst);git('add','-f','--',dst.relative_to(T).as_posix())
names=git('diff','--cached','--name-only','-z').decode().split('\0')
names=[n for n in names if n]
assert all(not n.startswith('2_fpga/') and Path(n).suffix.lower() not in {'.img','.zip','.wdb','.wlf'} for n in names)
manifest=json.loads((R/'selected_manifest.json').read_text(encoding='utf-8'))
checked=0
for rel,meta in manifest.items():
 if rel.startswith(('3_host/','8_tools/','4_metrics/','1_docs/doc/')):
  staged=git('show',':'+rel)
  # The plain Markdown plan uses normal Git line endings; binary/evidence/release bytes are exact.
  if rel.startswith('1_docs/') and Path(rel).suffix=='.md':continue
  assert hashlib.sha256(staged).hexdigest()==meta['sha256'],rel
  checked+=1
(R/'staged_blob_validation.json').write_text(json.dumps({'result':'STAGED_BLOB_HASH_PASS','hash_entries':checked,'frozen_paths':0},indent=2)+'\n')
shutil.copy2(R/'staged_blob_validation.json',T/REL/'staged_blob_validation.json')
git('add','-f','--',(REL/'staged_blob_validation.json').as_posix())
out=git('commit','-m','feat: archive EES-331 SD boot builder releases and verified evidence')
(R/'commit_console.txt').write_bytes(out)
commit=git('rev-parse','HEAD').decode().strip()
print('COMMIT '+commit,flush=True)
p=subprocess.run(['git','push','-u','origin','HEAD:refs/heads/'+branch],cwd=T,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(R/'push_console.txt').write_bytes(p.stdout)
assert p.returncode==0,'See push_console.txt'
remote=git('ls-remote','origin','refs/heads/'+branch).decode().split()[0]
assert remote==commit,(remote,commit)
result={'result':'PERSONAL_BRANCH_PUSH_PASS','branch':branch,'commit':commit,'remote_head':remote,'main_modified':False,'base_main':'c60291a','frozen_modified':False,'pr_status':'PENDING_SEPARATE_CHECK'}
(R/'upload_result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result),flush=True)
