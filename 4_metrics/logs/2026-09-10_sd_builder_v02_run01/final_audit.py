import hashlib,json,zipfile
from pathlib import Path
R=Path(__file__).resolve().parent; W=R.parents[2]
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        while b:=f.read(8*1024*1024): h.update(b)
    return h.hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
for mapping in ('v01_preserved_hashes.json','v01_tools_preserved_hashes.json'):
    assert all(sha(Path(p))==h for p,h in read(R/mapping).items())
release=read(R/'release_result.json'); delivery=Path(release['delivery'])
for n,m in release['files'].items():
    assert sha(R/'distribution'/n)==m['sha256']==sha(delivery/n)
for n,h in read(R/'distribution/source_hashes.json').items():
    assert sha(W/'3_host/pynq/sd_boot_builder_v02'/n)==h
assert read(R/'frozen_self_test_final.json')['result']=='FROZEN_GUI_SELF_TEST_PASS'
assert 'Ran 22 tests' in (R/'tests_release_console.txt').read_text(encoding='utf-8-sig')
for name in ('full_build_result.json','frozen_build_config.json.result.json','frozen_fsbl_config.json.result.json'):
    result=read(R/name); assert result['result']=='SD_PACKAGE_STATIC_PASS'
    out=Path(result['output'])
    with zipfile.ZipFile(out/'sd_boot_package.zip') as z:
        assert z.testzip() is None
        for n,m in result['files'].items():assert hashlib.sha256(z.read('boot/'+n)).hexdigest()==m['sha256']
    if 'image' in result:
        assert result['image']['full_readback']=='PASS' and result['image']['rootfs_unchanged']
        assert not (out/'boot_partition.img').exists()
daily=W/'7_logs/2026-09-10'
assert {p.name for p in daily.iterdir() if p.is_file()}=={'01_daily_plan.md','02_execution_plan.md','03_validation_summary.md','04_next_start_guide.md'}
paths=[p for p in R.iterdir() if p.is_file() and p.name!='final_audit_result.json']
paths+=list(daily.glob('*.md'))+[W/'HANDOFF.md']
result={'result':'V02_FINAL_AUDIT_PASS','source_matches_release':True,'delivery_matches_distribution':True,
        'v01_unchanged':True,'daily_logs_complete':True,'hardware_status':'NOT_TESTED',
        'evidence_sha256':{str(p):sha(p) for p in paths}}
(R/'final_audit_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(result['result'])
