"""Build a full disk image from the original IMG and verified boot files.

Only a standalone FAT partition is edited. Independent FAT parsing plus a
streamed comparison verifies that every byte outside that partition is retained.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import sys

R=Path(__file__).resolve().parent
W=R.parents[2]
F=R.parent/'2026-09-10_sd_boot_fix_run01'
SRC=W/'3_host/pynq/download/pynq_z2_v3.0.1.img'
OUT=R/'ees331_pynq_v3.0.1_ps_sd_20260910.img'
PART=R/'boot_partition.img'
OFFSET=4096
LENGTH=136314880
SIZE=7858807808
CHUNK=8*1024*1024
EXPECTED='f17405d25298a2c5ea23ccf95f868b42b18f819ff9d7fe5d079ac9ef53415861'
sys.path.insert(0,str(R/'python_deps'))
from pyfatfs.PyFatFS import PyFatFS
def sha(b): return hashlib.sha256(b).hexdigest()
def u16(b,o): return struct.unpack_from('<H',b,o)[0]
def u32(b,o): return struct.unpack_from('<I',b,o)[0]
def save(n,v): (R/n).write_text(json.dumps(v,indent=2),encoding='utf-8')
def inspect_fat(b):
    bps=u16(b,11); spc=b[13]; reserved=u16(b,14); copies=b[16]
    roots=u16(b,17); sectors=u16(b,19) or u32(b,32); fatsectors=u16(b,22)
    rootsectors=(roots*32+bps-1)//bps
    clusters=(sectors-reserved-copies*fatsectors-rootsectors)//spc
    assert b[510:512]==b'\x55\xaa' and 4085<=clusters<65525
    fatstart=reserved*bps; fatlen=fatsectors*bps
    assert copies==2 and b[fatstart:fatstart+fatlen]==b[fatstart+fatlen:fatstart+2*fatlen]
    rootstart=(reserved+copies*fatsectors)*bps
    datastart=rootstart+rootsectors*bps
    files={}; occupied=set(); allocations={}
    for p in range(rootstart,rootstart+roots*32,32):
        e=b[p:p+32]
        if e[0]==0: break
        if e[0]==0xe5 or e[11]==0x0f or e[11]&0x18: continue
        name=e[:8].decode('ascii').strip(); ext=e[8:11].decode('ascii').strip()
        name+=(('.'+ext) if ext else '')
        c=u16(e,26); size=u32(e,28); content=bytearray(); chain=[]
        while c<0xfff8 and size:
            assert 2<=c<=clusters+1 and c not in occupied
            occupied.add(c); chain.append(c)
            a=datastart+(c-2)*spc*bps
            content.extend(b[a:a+spc*bps]); c=u16(b,fatstart+c*2)
        assert len(content)>=size
        files[name.upper()]=bytes(content[:size]); allocations[name]=chain
    return files,dict(fat_bits=16,fat_copies_equal=True,cluster_crosslinks=False,allocations=allocations)

assert SRC.stat().st_size==SIZE
assert not OUT.exists() and not PART.exists(), 'Refusing to overwrite earlier image evidence'
deployment=json.loads((F/'deploy_result.json').read_text(encoding='utf-8-sig'))
assert deployment['result']=='SD_DEPLOY_READBACK_PASS'
expected={}
for f in deployment['files']:
    source=F/('candidate' if f['name'] in ('BOOT.BIN','image.ub','system.dtb','boot.py') else 'sd_backup')/f['name']
    data=source.read_bytes()
    assert len(data)==f['size'] and sha(data)==f['sha256']
    expected[f['name'].upper()]=data
with SRC.open('rb') as stream:
    mbr=stream.read(512)
    assert mbr[510:512]==b'\x55\xaa'
    assert u32(mbr,446+8)*512==OFFSET and u32(mbr,446+12)*512==LENGTH
    assert u32(mbr,462+8)*512==137363456 and u32(mbr,462+12)*512==7721444352
    stream.seek(OFFSET); original_part=stream.read(LENGTH)
assert len(original_part)==LENGTH
PART.write_bytes(original_part)
with PyFatFS(str(PART),preserve_case=False) as fs:
    for name in ('image.ub','boot.py','system.dtb','BOOT.BIN'):
        # Avoid the library's truncate-and-reuse path for existing chains.
        # The complete original partition is retained by SRC and attempt logs.
        # PyFatFS lookups are case-sensitive even on FAT. Match original 8.3
        # names explicitly so an old IMAGE.UB cannot survive beside IMAGE~1.UB.
        fatname='/'+name.upper()
        if fs.exists(fatname): fs.remove(fatname)
        fs.writebytes(fatname,(F/'candidate'/name).read_bytes())
newpart=PART.read_bytes()
assert len(newpart)==LENGTH
files,fatinfo=inspect_fat(newpart)
assert files==expected, 'Independent FAT file comparison failed'
save('fat_validation.json',dict(**fatinfo,files={n:dict(size=len(b),sha256=sha(b)) for n,b in files.items()}))
with PyFatFS(str(PART),read_only=True) as fs:
    for name,b in expected.items(): assert fs.readbytes('/'+name)==b
print('FAT_PARTITION_EDIT_AND_INDEPENDENT_READBACK_PASS',flush=True)

source_hash=hashlib.sha256(); block_records=[]
with SRC.open('rb') as src, OUT.open('xb') as dest:
    for begin,end,replace in ((0,OFFSET,False),(OFFSET,OFFSET+LENGTH,True),(OFFSET+LENGTH,SIZE,False)):
        pos=begin
        while pos<end:
            data=src.read(min(CHUNK,end-pos)); assert data
            source_hash.update(data)
            payload=newpart[pos-OFFSET:pos-OFFSET+len(data)] if replace else data
            dest.write(payload)
            block_records.append(dict(offset=pos,size=len(data),original_sha256=sha(data),output_sha256=sha(payload),inside_boot_partition=replace))
            pos+=len(data)
            if len(block_records)%128==0: print(f'WRITE {pos}/{SIZE}',flush=True)
    dest.flush(); os.fsync(dest.fileno())
assert source_hash.hexdigest()==EXPECTED, 'Source IMG differs from approved archive'
assert OUT.stat().st_size==SIZE
output_hash=hashlib.sha256()
with OUT.open('rb') as stream:
    for i,rec in enumerate(block_records):
        data=stream.read(rec['size'])
        assert len(data)==rec['size'] and sha(data)==rec['output_sha256']
        if not rec['inside_boot_partition']: assert sha(data)==rec['original_sha256']
        output_hash.update(data)
        if i and i%128==0: print(f'READBACK {stream.tell()}/{SIZE}',flush=True)
    assert not stream.read(1)
with OUT.open('rb') as stream:
    stream.seek(OFFSET); final_files,final_fat=inspect_fat(stream.read(LENGTH))
assert final_files==expected
uart=W/'4_metrics/logs/2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt'
uartbytes=uart.read_bytes(); uarttext=uartbytes.decode('utf-8',errors='replace')
for marker in ('Xilinx First Stage Boot Loader','SUCCESSFUL_HANDOFF','U-Boot 2022.01','Machine model: EES-331','xilinx@pynq:~$'):
    assert marker in uarttext
shutil.copyfile(uart,R/'uart_boot_evidence.txt')
save('block_verification.json',block_records)
result=dict(result='FULL_IMG_PACKAGE_READBACK_PASS',image=str(OUT),size=SIZE,sha256=output_hash.hexdigest(),source_image_sha256=source_hash.hexdigest(),boot_files_match_deployed=True,all_bytes_outside_boot_partition_unchanged=True,rootfs_unchanged=True,full_image_readback_verified=True,board_evidence=dict(source=str(uart),sha256=sha(uartbytes),result='SD_BOOT_TO_LINUX_SHELL_PASS',new_img_reflash_test='NOT_RUN'),known_limits=['Not a snapshot of the card after first boot','U-Boot PHY and environment warnings remain in the accepted UART baseline','Networking, Jupyter and application overlays not accepted by this packaging step'])
save('package_result.json',result)
(R/(OUT.name+'.sha256')).write_text(output_hash.hexdigest()+'  '+OUT.name+'\n',encoding='ascii')
print(json.dumps(result,indent=2),flush=True)
