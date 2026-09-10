import hashlib
import json
from pathlib import Path
import shutil
import zipfile

r=Path(__file__).resolve().parent
w=r.parents[2]
app=w/'3_host/pynq/sd_boot_builder'
dist=r/'distribution'
exe=dist/'EES331SDBootBuilder.exe'
assert exe.is_file()
assert json.loads((r/'frozen_self_test.json').read_text())['result']=='FROZEN_GUI_SELF_TEST_PASS'
assert json.loads((r/'frozen_build_config.json.result.json').read_text(encoding='utf-8'))['result']=='SD_PACKAGE_STATIC_PASS'
shutil.copyfile(app/'README.md',dist/'README.md')
payload=[(exe,'EES331SDBootBuilder.exe'),(dist/'README.md','README.md')]
for p in app.iterdir():
    if p.is_file() and (p.suffix=='.py' or p.name=='requirements.txt'):
        payload.append((p,'source/'+p.name))
for p in (app/'assets').iterdir():
    if p.is_file(): payload.append((p,'source/assets/'+p.name))
manifest={name:dict(size=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p,name in payload}
zip_path=dist/'EES331_SD_Builder_v0.1.zip'
with zipfile.ZipFile(zip_path,'x',compression=zipfile.ZIP_DEFLATED) as z:
    for p,name in payload: z.write(p,name)
    z.writestr('checksums.json',json.dumps(manifest,indent=2))
with zipfile.ZipFile(zip_path) as z:
    assert z.testzip() is None
    for name,m in manifest.items(): assert hashlib.sha256(z.read(name)).hexdigest()==m['sha256']
result=dict(result='TOOLKIT_DELIVERY_PASS',exe=manifest['EES331SDBootBuilder.exe'],
            archive=dict(path=str(zip_path),size=zip_path.stat().st_size,sha256=hashlib.sha256(zip_path.read_bytes()).hexdigest()),
            files=manifest,scope='EES-331 / Vivado-Vitis 2025.2 / PYNQ 3.0.1',hardware_validation='NOT_RUN_FOR_NEW_OUTPUTS')
(r/'delivery_manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
(dist/'EES331_SD_Builder_v0.1.zip.sha256').write_text(result['archive']['sha256']+'  '+zip_path.name+'\n')
for name in ('01_daily_plan.md','02_execution_plan.md','03_validation_summary.md','04_next_start_guide.md'):
    assert 'sd_boot_builder' in (w/'7_logs/2026-09-10'/name).read_text(encoding='utf-8-sig') or 'sd_builder' in (w/'7_logs/2026-09-10'/name).read_text(encoding='utf-8-sig')
print(json.dumps(dict(result=result['result'],exe_size=result['exe']['size'],exe_sha256=result['exe']['sha256'],archive=result['archive']),indent=2))
