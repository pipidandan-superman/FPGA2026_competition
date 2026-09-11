"""Independent binary checks; does not write the SD card."""
import ast
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib
from fdt_reader import parse, be, text

R = Path(__file__).resolve().parent
C = R / 'candidate'
checks = []
def check(name, value):
    if not value:
        raise AssertionError(name)
    checks.append(name)
def sha(data):
    return hashlib.sha256(data).hexdigest()
def u32(b, off):
    return struct.unpack_from('<I', b, off)[0]
def partitions(b):
    p = u32(b, 0x9c)
    count = u32(b, u32(b, 0x98) + 4)
    result = []
    for i in range(count):
        w = struct.unpack_from('<16I', b, p + 64*i)
        check(f'partition {i} header checksum', sum(w) & 0xffffffff == 0xffffffff)
        off, length = w[5]*4, w[1]*4
        check(f'partition {i} bounds', off + w[2]*4 <= len(b) and 0 < length <= w[2]*4)
        result.append(dict(load=w[3], entry=w[4], offset=off, size=length,
                           attributes=w[6], data=b[off:off+length]))
    return result
def elf_segments(b):
    check('ELF ARM executable', b[:6] == b'\x7fELF\x01\x01' and struct.unpack_from('<HH',b,16)==(2,40))
    phoff=u32(b,28)
    phentsize,phnum=struct.unpack_from('<HH',b,42)
    return u32(b,24), [w for i in range(phnum)
        if (w:=struct.unpack_from('<8I',b,phoff+i*phentsize))[0]==1]

boot=(C/'BOOT.BIN').read_bytes()
check('BOOT width and image signature', u32(boot,32)==0xaa995566 and u32(boot,36)==0x584c4e58)
check('BOOT header checksum', sum(struct.unpack_from('<11I',boot,32)) & 0xffffffff == 0xffffffff)
p=partitions(boot)
check('three boot partitions',len(p)==3)
check('FSBL ROM header fields', u32(boot,48)==p[0]['offset'] and u32(boot,52)==p[0]['size'] and u32(boot,64)==p[0]['size'] and u32(boot,56)==0 and u32(boot,60)==0)
check('FSBL low OCM bounds', 0 < p[0]['size'] < 0x30000 and p[0]['load']==0 and p[0]['entry']==0)
check('PS partition attributes', all(x['attributes'] & 0xf0 == 0x10 for x in p))
check('nonoverlapping boot payloads',all(p[i]['offset']+p[i]['size'] <= p[i+1]['offset'] for i in range(2)))
fsbl=(C/'fsbl.elf').read_bytes()
entry,segs=elf_segments(fsbl)
check('FSBL ELF entry',entry==0)
for i,s in enumerate(segs):
    _,off,virt,phys,filesz,memsz,flags,align=s
    check(f'FSBL segment {i} fits OCM',phys+memsz<=0x30000 or (phys>=0xffff0000 and phys+memsz<=0x100000000))
    if filesz:
        check(f'FSBL segment {i} BOOT payload',p[0]['data'][phys:phys+filesz]==fsbl[off:off+filesz])
for marker in (b'Xilinx First Stage Boot Loader',b'Boot mode is SD'):
    check('FSBL banner '+marker.decode(),marker in fsbl and marker in p[0]['data'])
check('unchanged PS initialization',sha((R/'fsbl_build/ps7_init.c').read_bytes())=='353d35f807279393e3f8001922ba7a09a6c77e833b2443b3fb176495cc2b8023')
ub=(C/'u-boot.bin').read_bytes()
oldboot=(R.parent/'2026-09-10_pynq_fsbl_rebuild_run03/BOOT_pynq_z2_orig.BIN').read_bytes()
oldp=partitions(oldboot)
check('U-Boot original binary payload preserved',ub==oldp[1]['data']==p[1]['data'])
check('U-Boot load and entry',p[1]['load']==p[1]['entry']==0x04000000)
ue=(C/'u-boot.elf').read_bytes()
entry,usegs=elf_segments(ue)
check('U-Boot ELF executable payload',entry==0x04000000 and len(usegs)==1 and usegs[0][3]==0x04000000 and ue[usegs[0][1]:usegs[0][1]+usegs[0][4]]==ub)
sys.path.insert(0,str(R/'python_deps'))
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
ins=list(Cs(CS_ARCH_ARM,CS_MODE_ARM).disasm(ub[0x2b24:0x2b44],0x04002b24))
disasm=[f'{i.address:08x}: {i.mnemonic} {i.op_str}' for i in ins]
check('actual U-Boot selects external DTB at 1MiB',ins[2].mnemonic=='mov' and ins[2].op_str=='r0, #0x100000' and ins[3].op_str=='r3, [r0]' and ins[4].op_str=='r2, [pc, #0x38]' and ins[6].mnemonic=='cmp' and ins[7].mnemonic=='bxeq' and u32(ub,0x2b74)==0xd00dfeed)
(R/'uboot_external_dtb_proof.json').write_text(json.dumps(dict(disassembly=disasm,literal_address='0x04002b74',literal='0xd00dfeed',uboot_sha256=sha(ub)),indent=2))
dtb=(C/'system.dtb').read_bytes()
check('BOOT control DTB at 1MiB',p[2]['load']==0x00100000 and p[2]['entry']==0 and p[2]['data'][:len(dtb)]==dtb and len(p[2]['data'])-len(dtb)<4)
d=parse(dtb)
check('RAM 1GiB',struct.unpack('>II',d['/memory@0']['reg'])==(0,0x40000000))
check('UART1 alias and console',text(d['/aliases']['serial0'])=='/axi/serial@e0001000' and text(d['/chosen']['stdout-path'])=='serial0:115200n8' and 'console=ttyPS0,115200' in text(d['/chosen']['bootargs']))
check('UART1 enabled UART0 disabled',text(d['/axi/serial@e0001000']['status'])=='okay' and text(d['/axi/serial@e0000000']['status'])=='disabled')
check('PS 33.333333MHz',be(d['/axi/slcr@f8000000/clkc@100']['ps-clk-frequency'])==33333333)
check('SD0 4bit no voltage switch',be(d['/axi/mmc@e0100000']['bus-width'])==4 and 'no-1-8-v' in d['/axi/mmc@e0100000'])
check('PHY address 0',be(d['/axi/ethernet@e000b000/ethernet-phy@0']['reg'])==0)
check('PHY correctly linked',d['/axi/ethernet@e000b000']['phy-handle']==d['/axi/ethernet@e000b000/ethernet-phy@0']['phandle'])
for path in ('i2c@e0004000','i2c@e0005000','spi@e000d000','usb@e0002000'):
    check(path+' disabled to match XSA',text(d['/axi/'+path]['status'])=='disabled')
ph={be(v['phandle']):k for k,v in d.items() if 'phandle' in v}
check('unique phandles',len(ph)==sum('phandle' in v for v in d.values()))
for path,props in d.items():
    for key,cellkey in [('clocks','#clock-cells'),('resets','#reset-cells'),('dmas','#dma-cells'),('pwms','#pwm-cells')]:
        if key not in props: continue
        cells=list(struct.unpack('>'+'I'*(len(props[key])//4),props[key])); n=0
        while n<len(cells):
            check(f'{path} {key} reference {n}',cells[n] in ph)
            provider=d[ph[cells[n]]]
            n+=1+be(provider[cellkey])
        check(f'{path} {key} cell count',n==len(cells))
    if 'interrupt-parent' in props:
        check(f'{path} interrupt-parent exists',be(props['interrupt-parent']) in ph)
for path in ('/aliases','/__symbols__'):
    for name,val in d[path].items():
        check(f'{path} {name} target exists',text(val) in d)
fit=parse((C/'image.ub').read_bytes())
oldfit=parse((R/'sd_backup/image.ub').read_bytes())
check('FIT default configuration',text(fit['/configurations']['default'])=='conf-1')
check('FIT selected payloads',text(fit['/configurations/conf-1']['kernel'])=='kernel-0' and text(fit['/configurations/conf-1']['fdt'])=='fdt-0')
for name in ('kernel-0','fdt-0'):
    ip='/images/'+name
    check('FIT SHA1 '+name,hashlib.sha1(fit[ip]['data']).digest()==fit[ip+'/hash-1']['value'] and text(fit[ip+'/hash-1']['algo'])=='sha1')
check('FIT kernel unchanged',fit['/images/kernel-0']['data']==oldfit['/images/kernel-0']['data'])
for key in ('type','arch','os','compression','load','entry'):
    check('kernel metadata '+key,fit['/images/kernel-0'][key]==oldfit['/images/kernel-0'][key])
check('BOOT and Linux use identical DTB',fit['/images/fdt-0']['data']==dtb)
script=(R/'sd_backup/boot.scr').read_bytes()
hdr=bytearray(script[:64]); crc=be(hdr,4); hdr[4:8]=b'\0'*4
check('boot.scr header CRC',zlib.crc32(hdr)==crc and be(script)==0x27051956)
check('boot.scr payload CRC',zlib.crc32(script[64:64+be(script,12)])==be(script,24))
check('boot.scr loads FIT',b'bootm 0x10000000' in script)
code=(C/'boot.py').read_text()
tree=ast.parse(code)
check('boot.py only docstring and print calls',all(isinstance(x,ast.Expr) and (isinstance(x.value,ast.Constant) or (isinstance(x.value,ast.Call) and isinstance(x.value.func,ast.Name) and x.value.func.id=='print')) for x in tree.body))
check('native DTC roundtrip no warnings',(R/'dtc_roundtrip_console.txt').stat().st_size==0)
manifest={name:dict(size=(C/name).stat().st_size,sha256=sha((C/name).read_bytes())) for name in ('BOOT.BIN','image.ub','system.dtb','boot.py','BOOT_FSBL_DIAG.BIN','fsbl.elf','u-boot.elf')}
result=dict(result='SD_BOOT_CANDIDATE_STATIC_PASS',checks_passed=len(checks),checks=checks,partitions=[{k:v for k,v in x.items() if k!='data'} for x in p],files=manifest,hardware_status='NOT_TESTED')
(R/'candidate_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(dict(result=result['result'],checks_passed=len(checks),files=manifest),indent=2))
