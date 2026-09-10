import hashlib
import json
from pathlib import Path
import shutil
import zipfile

r=Path(__file__).resolve().parent
w=r.parents[2]
app=w/'3_host/pynq/sd_boot_builder'
assets=app/'assets'
assets.mkdir(parents=True,exist_ok=True)
fix=r.parent/'2026-09-10_sd_boot_fix_run01'
manifest={}
for name in ('fsbl.elf','u-boot.elf','system.dtb','kernel.bin'):
    shutil.copyfile(fix/'candidate'/name,assets/name)
for name in ('boot.scr','REVISION'):
    shutil.copyfile(fix/'sd_backup'/name,assets/name)
shutil.copyfile(fix/'fdt_reader.py',app/'fdt_reader.py')
xsa=w/'2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa'
with zipfile.ZipFile(xsa) as z:
    for src,dst in [('pynq_test.hwh','reference.hwh'),('ps7_init.c','reference_init.c'),('xsa.json','reference_xsa.json')]:
        (assets/dst).write_bytes(z.read(src))
for p in assets.iterdir():
    if p.name=='manifest.json': continue
    manifest[p.name]=dict(size=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
(assets/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(dict(assets=str(assets),files=len(manifest))))
