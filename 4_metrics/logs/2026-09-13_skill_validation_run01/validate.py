import os
import sys
import json
import hashlib
import subprocess
from pathlib import Path
RUN=Path(__file__).resolve().parent
roots=[Path('E:/competition/6_skill'),Path('E:/competition/.codex/skills'),Path('C:/Users/Administrator/.codex/skills')]
name='zynq-pynq-overlay-workflow'
env=dict(os.environ,PYTHONPATH=str(RUN/'deps'))
results=[]
for index,root in enumerate(roots):
    p=subprocess.run([sys.executable,'-B','C:/Users/Administrator/.codex/skills/.system/skill-creator/scripts/quick_validate.py',str(root/name)],env=env,text=True,capture_output=True)
    (RUN/f'validator_{index}.log').write_text(p.stdout+p.stderr)
    assert p.returncode==0
    results.append(dict(path=str(root/name),exit=p.returncode))
for rel in ('SKILL.md','references/ees331.md'):
    contents=[(r/name/rel).read_bytes() for r in roots]
    assert contents[0]==contents[1]==contents[2]
    results.append(dict(file=rel,sha256=hashlib.sha256(contents[0]).hexdigest(),copies_equal=True))
text=(roots[0]/name/'SKILL.md').read_text()
assert (roots[0]/name/'references/ees331.md').is_file()
result=dict(marker='ZYNQ_PYNQ_SKILL_VALIDATION_PASS',checks=results,behavioral_boundary='No independent hardware execution by validator; based on cited runs',dependency='PyYAML==6.0.2 installed only in run-local deps')
(RUN/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
