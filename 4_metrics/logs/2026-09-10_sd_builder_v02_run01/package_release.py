import hashlib,json,shutil,zipfile
from pathlib import Path
R=Path(__file__).resolve().parent; W=R.parents[2]
SOURCE=W/'3_host/pynq/sd_boot_builder_v02'; DIST=R/'distribution'
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        while b:=f.read(8*1024*1024): h.update(b)
    return h.hexdigest()
def save(p,obj): p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')
original=json.loads((R/'v01_preserved_hashes.json').read_text(encoding='utf-8'))
changed=[p for p,h in original.items() if not Path(p).is_file() or sha(Path(p))!=h]
assert not changed,changed
save(R/'v01_preservation_result.json',{'result':'V01_PRESERVATION_PASS','files_checked':len(original),'changed':changed})
old_tools=W/'8_tools/sd_start_tool'
save(R/'v01_tools_preserved_hashes.json',{str(p):sha(p) for p in old_tools.rglob('*') if p.is_file()})
shutil.copy2(SOURCE/'README.md',DIST/'README.md')
exe=DIST/'EES331SDBootBuilder_v0.2.exe'
shutil.copy2(R/'frozen_build_config.json',DIST/'example_build_config.json')
save(DIST/'source_hashes.json',{str(p.relative_to(SOURCE)):sha(p) for p in SOURCE.rglob('*') if p.is_file() and '__pycache__' not in p.parts})
archive=DIST/'EES331_SD_Builder_v0.2.zip'
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
    for name in (exe.name,'README.md','example_build_config.json','source_hashes.json'): z.write(DIST/name,name)
    for p in SOURCE.rglob('*'):
        if p.is_file() and '__pycache__' not in p.parts: z.write(p,'source/'+p.relative_to(SOURCE).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read(exe.name)).hexdigest()==sha(exe)
for p in (exe,archive): (DIST/(p.name+'.sha256')).write_text(sha(p)+'  '+p.name+'\n',encoding='ascii')
delivery=W/'8_tools/sd_start_tool_v0.2'
delivery.mkdir(exist_ok=False)
for p in DIST.iterdir():
    if p.is_file(): shutil.copy2(p,delivery/p.name)
assert all(sha(p)==sha(delivery/p.name) for p in DIST.iterdir() if p.is_file())
old_check=json.loads((R/'v01_tools_preserved_hashes.json').read_text(encoding='utf-8'))
assert all(sha(Path(p))==h for p,h in old_check.items())
save(R/'release_result.json',{'result':'V02_RELEASE_PACKAGE_PASS','delivery':str(delivery),'zip_crc':'PASS',
  'old_tools_unchanged':True,'v01_unchanged':True,'files':{p.name:{'size':p.stat().st_size,'sha256':sha(p)} for p in DIST.iterdir() if p.is_file()}})
print(json.dumps(json.loads((R/'release_result.json').read_text(encoding='utf-8')),ensure_ascii=False,indent=2))
