import hashlib
import json
import os
import sys
import shutil
from pathlib import Path
RUN=Path(__file__).resolve().parent
ROOT=Path('E:/competition/2_fpga/2_axi_lite_test')
PRIOR=Path('E:/competition/4_metrics/logs/2026-09-11_pynq_camera_run01')
sys.path.insert(0,str(PRIOR/'deps'))
import paramiko
remote='/home/xilinx/axilt_test_20260913_run01'
manifest=json.loads((ROOT/'proj/release/artifact_manifest.json').read_text())
paths=[ROOT/'proj/release'/name for name in manifest['files']]
paths += [ROOT/'proj/release/artifact_manifest.json']
paths += [ROOT/'pynq'/name for name in ('axilt.py','board_test.py','mmio_ordered.c')]
records=[]
(RUN/'delivery').mkdir()
for path in paths:
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    if path.name in manifest['files']:
        assert digest==manifest['files'][path.name]['sha256']
    shutil.copy2(path,RUN/'delivery'/path.name)
    records.append(dict(name=path.name,sha256=digest,size=path.stat().st_size))
(RUN/'delivery_hashes.json').write_text(json.dumps(records,indent=2))
c=paramiko.SSHClient()
c.load_host_keys(str(PRIOR/'known_hosts'))
c.set_missing_host_key_policy(paramiko.RejectPolicy())
try:
    c.connect('192.168.240.10',username='xilinx',password=os.environ.get('PYNQ_PASSWORD','xilinx'),look_for_keys=False,allow_agent=False,timeout=8)
    with c.open_sftp() as s:
        s.mkdir(remote)
        for path in paths:
            if path.suffix=='.xsa':
                continue
            s.put(str(RUN/'delivery'/path.name),remote+'/'+path.name)
            with s.open(remote+'/'+path.name,'rb') as uploaded:
                assert hashlib.sha256(uploaded.read()).hexdigest()==hashlib.sha256(path.read_bytes()).hexdigest()
    print('UPLOAD_HASHES_PASS',remote)
finally:
    c.close()
