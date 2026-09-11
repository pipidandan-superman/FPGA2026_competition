"""Use an existing Git Credential Manager credential without logging secrets."""
import json,os,subprocess,urllib.request,urllib.error
from pathlib import Path
R=Path(__file__).resolve().parent
env=dict(os.environ,GCM_INTERACTIVE='Never',GIT_TERMINAL_PROMPT='0')
res={}
try:
 p=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',text=True,capture_output=True,env=env,timeout=25)
 cred=dict(line.split('=',1) for line in p.stdout.splitlines() if '=' in line)
 token=cred.get('password')
 if p.returncode or not token:
  res={'result':'PR_AUTH_UNAVAILABLE','reason':'No existing noninteractive HTTPS GitHub credential; SSH branch push is separate.'}
 else:
  def api(path,data=None):
   req=urllib.request.Request('https://api.github.com/repos/pipidandan-superman/FPGA2026_competition/'+path,data=json.dumps(data).encode() if data else None,headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','User-Agent':'project-archive'})
   with urllib.request.urlopen(req,timeout=30) as r:return json.load(r)
  prs=api('pulls?state=open&head=pipidandan-superman:codex/full/pipidandan-superman&base=main')
  if prs:pr=prs[0];action='EXISTING_PR'
  else:
   body=(R/'PR_BODY.md').read_text(encoding='utf-8')
   pr=api('pulls',{'title':'feat: archive EES-331 SD boot builder releases and validation evidence','head':'codex/full/pipidandan-superman','base':'main','body':body,'draft':True});action='DRAFT_PR_CREATED'
  res={'result':action,'number':pr['number'],'url':pr['html_url'],'base':pr['base']['ref'],'head':pr['head']['ref']}
except urllib.error.HTTPError as e:res={'result':'PR_API_ERROR','http_status':e.code}
except Exception as e:res={'result':'PR_UNAVAILABLE','error_type':type(e).__name__}
(R/'pr_result.json').write_text(json.dumps(res,indent=2)+'\n',encoding='utf-8')
print(json.dumps(res))
