import hashlib,json,subprocess,shutil
from pathlib import Path
W=Path('E:/competition');T=Path('E:/competition_worktrees/FPGA2026_competition/pipidandan-superman')
R=Path(__file__).resolve().parent;REL=R.relative_to(W)
def git(*args,cwd=T):return subprocess.check_output(['git',*args],cwd=cwd,stderr=subprocess.STDOUT)
files=['README.md','HANDOFF.md',*[f'7_logs/2026-09-10/{n}' for n in ['01_daily_plan.md','02_execution_plan.md','03_validation_summary.md','04_next_start_guide.md']]]
for name in ['REPORT.md','commit_console.txt','push_console.txt','upload_result.json','pr_result.json','finalize_upload.py']:
 p=R/name;dst=T/REL/name;shutil.copy2(p,dst);files.append(dst.relative_to(T).as_posix())
for rel in files:assert (W/rel).read_bytes()==(T/rel).read_bytes(),rel
git('add','-f','--',*files)
actual=set(git('diff','--cached','--name-only','-z').decode().strip('\0').split('\0'))
assert actual==set(files),actual-set(files)
check=subprocess.run(['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--cached','--check'],cwd=T,capture_output=True)
(R/'receipt_whitespace_check.txt').write_bytes(check.stdout+check.stderr)
assert check.returncode==0,'See receipt_whitespace_check.txt'
frozen=subprocess.check_output(['git','diff','--binary','--','2_fpga'],cwd=W,stderr=subprocess.DEVNULL)
assert hashlib.sha256(frozen).hexdigest()==(R/'source_frozen_diff_sha256.txt').read_text().strip()
assert git('diff','--cached','--name-status',cwd=W)==(R/'source_staged.txt').read_bytes()
git('fetch','--prune','origin')
assert git('rev-parse','HEAD')==git('rev-parse','origin/codex/full/pipidandan-superman')
git('merge-base','--is-ancestor','origin/main','HEAD')
(R/'receipt_commit_console.txt').write_bytes(git('commit','-m','docs: record archive upload receipt and draft PR handoff'))
head=git('rev-parse','HEAD').decode().strip()
(R/'receipt_push_console.txt').write_bytes(git('push','origin','HEAD:refs/heads/codex/full/pipidandan-superman'))
remote=git('ls-remote','origin','refs/heads/codex/full/pipidandan-superman').decode().split()[0]
assert head==remote
status=git('status','--porcelain')
assert not status,status
assert not git('diff','--name-only','origin/main...HEAD','--','2_fpga')
result={'result':'ARCHIVE_UPLOAD_COMPLETE','content_commit':'ae1384aea6f3390fb17ef78562eabf83f4677039','receipt_commit':head,'remote_head':remote,'branch':'codex/full/pipidandan-superman','pr_url':'https://github.com/pipidandan-superman/FPGA2026_competition/pull/3','worktree_clean':True,'frozen_diff_from_main':False,'source_frozen_diff_unchanged':True,'source_index_unchanged':True,'main_merged':False,'receipt_note':'Tracked upload_result.json proves the content commit; this local final receipt proves the follow-up receipt commit without a self-referential Git hash.'}
(R/'final_upload_verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
(R/'final_worktree_status.txt').write_bytes(git('status','--short','--branch'))
print(json.dumps(result))
