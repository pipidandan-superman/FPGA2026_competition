"""FAT image packaging with independent readback; never opens a physical disk."""
import hashlib
import json
import os
import struct
from pathlib import Path
from hardware import BuildError,digest

BASE_SIZE=7858807808
BASE_HASH='203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a'
BASE_NAME='ees331_pynq_v3.0.1_ps_sd_20260910.img'
OFFSET=4096
LENGTH=136314880
CHUNK=8*1024*1024

def u16(b,o): return struct.unpack_from('<H',b,o)[0]
def u32(b,o): return struct.unpack_from('<I',b,o)[0]

def fat_read(data):
    bps=u16(data,11); spc=data[13]; reserved=u16(data,14); copies=data[16]
    roots=u16(data,17); total=u16(data,19) or u32(data,32); fatsz=u16(data,22)
    rootsectors=(roots*32+bps-1)//bps
    clusters=(total-reserved-copies*fatsz-rootsectors)//spc
    if not(4085<=clusters<65525) or data[510:512]!=b'\x55\xaa':
        raise BuildError('当前镜像配置要求基线 FAT16 分区。')
    fatstart=reserved*bps; fatlen=fatsz*bps
    if copies!=2 or data[fatstart:fatstart+fatlen]!=data[fatstart+fatlen:fatstart+2*fatlen]:
        raise BuildError('FAT 双副本不一致。')
    rootstart=(reserved+copies*fatsz)*bps; datastart=rootstart+rootsectors*bps
    files={}; used=set()
    for p in range(rootstart,rootstart+roots*32,32):
        e=data[p:p+32]
        if e[0]==0: break
        if e[0]==0xe5 or e[11]==0x0f or e[11]&0x18: continue
        name=e[:8].decode('ascii').strip(); ext=e[8:11].decode('ascii').strip()
        name+=(('.'+ext) if ext else '')
        c=u16(e,26); size=u32(e,28); payload=bytearray()
        while c<0xfff8 and size:
            if not 2<=c<=clusters+1 or c in used: raise BuildError('FAT 文件链无效/交叉。')
            used.add(c); a=datastart+(c-2)*spc*bps
            payload.extend(data[a:a+spc*bps]); c=u16(data,fatstart+2*c)
        if len(payload)<size or name in files: raise BuildError('FAT 文件长度或目录无效。')
        files[name]=bytes(payload[:size])
    return files

def verify_base(base,log=lambda line:None):
    base=Path(base)
    if not base.is_file() or base.stat().st_size!=BASE_SIZE:
        raise BuildError('需要 EES-331 基础系统镜像 '+BASE_NAME+'（7858807808 字节），请在高级设置中定位。')
    with base.open('rb') as f:
        mbr=f.read(512)
        if mbr[510:512]!=b'\x55\xaa' or u32(mbr,454)*512!=OFFSET or u32(mbr,458)*512!=LENGTH:
            raise BuildError('基础镜像分区布局不匹配。')
        f.seek(OFFSET); files=fat_read(f.read(LENGTH))
        from fdt_reader import parse,text
        if 'SYSTEM.DTB' not in files or 'EES-331' not in text(parse(files['SYSTEM.DTB'])['/']['model']):
            raise BuildError('这不是适配后的 EES-331 基础镜像。原版 PYNQ-Z2 镜像不能用于 v0.2。')
        f.seek(0); h=hashlib.sha256()
        while chunk:=f.read(CHUNK): h.update(chunk)
    if h.hexdigest()!=BASE_HASH: raise BuildError('EES-331 基础镜像 SHA256 不匹配，不接受未登记版本。')
    log('EES-331 基础镜像身份与 SHA256 校验通过。')
    return dict(name=BASE_NAME,path=str(base.resolve()),size=BASE_SIZE,sha256=BASE_HASH,board='EES-331')

def build_image(base,boot,out,log):
    from pyfatfs.PyFatFS import PyFatFS
    base=Path(base); out=Path(out)
    if not base.is_file() or base.stat().st_size!=BASE_SIZE:
        raise BuildError('完整 IMG 需要已适配 EES-331 的基础镜像（7858807808 字节）。')
    files={p.name.upper():p.read_bytes() for p in Path(boot).iterdir() if p.is_file()}
    # Keep the temporary FAT image beside the run workspace, never inside the
    # user-facing output directory (it can be hundreds of MiB).
    part=out.parent.parent/'work'/'boot_partition.img'
    part.parent.mkdir(parents=True,exist_ok=True)
    with base.open('rb') as f:
        mbr=f.read(512)
        if u32(mbr,454)*512!=OFFSET or u32(mbr,458)*512!=LENGTH:
            raise BuildError('基础镜像分区布局不匹配。')
        f.seek(OFFSET); part.write_bytes(f.read(LENGTH))
    with PyFatFS(str(part),preserve_case=False) as fs:
        for name in list(fs.listdir('/')):
            if fs.isfile('/'+name): fs.remove('/'+name)
        for name,payload in files.items():
            if len(name.split('.')[0])>8 or ('.' in name and len(name.split('.')[1])>3):
                raise BuildError('内部启动文件名必须符合当前 8.3 配置。')
            fs.writebytes('/'+name,payload)
    edited=part.read_bytes()
    if len(edited)!=LENGTH or fat_read(edited)!=files: raise BuildError('启动分区独立校验失败。')
    with PyFatFS(str(part),read_only=True) as fs:
        for name,payload in files.items():
            if fs.readbytes('/'+name)!=payload: raise BuildError('文件系统读回失败：'+name)
    original_hash=hashlib.sha256(); blocks=[]
    with base.open('rb') as src,out.open('xb') as dest:
        for begin,end,patch in ((0,OFFSET,False),(OFFSET,OFFSET+LENGTH,True),(OFFSET+LENGTH,BASE_SIZE,False)):
            pos=begin
            while pos<end:
                data=src.read(min(CHUNK,end-pos))
                if not data: raise BuildError('基础镜像意外结束。')
                original_hash.update(data)
                payload=edited[pos-OFFSET:pos-OFFSET+len(data)] if patch else data
                dest.write(payload)
                blocks.append(dict(offset=pos,size=len(data),original=digest(data),output=digest(payload),patched=patch))
                pos+=len(data)
                if len(blocks)%128==0: log(f'写入 IMG {pos/BASE_SIZE:.0%}')
        dest.flush(); os.fsync(dest.fileno())
    if original_hash.hexdigest()!=BASE_HASH: raise BuildError('基础镜像 SHA256 不匹配，输出不可发布。')
    total=hashlib.sha256()
    with out.open('rb') as f:
        for i,b in enumerate(blocks):
            data=f.read(b['size']); actual=digest(data)
            if actual!=b['output'] or (not b['patched'] and actual!=b['original']):
                raise BuildError('IMG 全文件读回失败。')
            total.update(data)
            if i and i%128==0: log(f'校验 IMG {f.tell()/BASE_SIZE:.0%}')
        if f.read(1): raise BuildError('IMG 尾部长度异常。')
    with out.open('rb') as f:
        f.seek(OFFSET)
        if fat_read(f.read(LENGTH))!=files: raise BuildError('IMG 中启动文件不一致。')
    (out.parent/'image_block_checks.json').write_text(json.dumps(blocks,indent=2))
    result=dict(size=out.stat().st_size,sha256=total.hexdigest(),base_sha256=BASE_HASH,
                rootfs_unchanged=True,full_readback='PASS',boot_files='PASS')
    (out.parent/'image_validation.json').write_text(json.dumps(result,indent=2))
    return result
