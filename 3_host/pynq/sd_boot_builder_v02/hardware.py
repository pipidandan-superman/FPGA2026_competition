"""Read a complete XSA and classify changes against the EES-331 profile."""
import hashlib
import json
import struct
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

class BuildError(Exception):
    pass

def digest(data):
    return hashlib.sha256(data).hexdigest()

def ps_parameters(hwh):
    if b'<!DOCTYPE' in hwh or b'<!ENTITY' in hwh:
        raise BuildError('HWH 不允许包含外部实体。')
    root=ET.fromstring(hwh)
    modules=[m for m in root.iter('MODULE') if m.get('MODTYPE')=='processing_system7']
    if len(modules)!=1:
        raise BuildError('XSA 必须包含且仅包含一个 Zynq-7000 processing_system7。')
    values={p.get('NAME'):p.get('VALUE') for p in modules[0].findall('./PARAMETERS/PARAMETER')}
    return root,values

def bit_info(data):
    try:
        n=struct.unpack_from('>H',data,0)[0]
        p=2+n
        if struct.unpack_from('>H',data,p)[0]!=1:
            raise ValueError('header marker')
        p+=2
        result={}
        while p<len(data):
            key=chr(data[p]); p+=1
            if key=='e':
                n=struct.unpack_from('>I',data,p)[0]; p+=4
                if n<=0 or p+n!=len(data): raise ValueError('payload length')
                result['payload_size']=n
                return result
            if key not in 'abcd': raise ValueError('header tag')
            n=struct.unpack_from('>H',data,p)[0]; p+=2
            result[key]=data[p:p+n].rstrip(b'\0').decode('ascii'); p+=n
        raise ValueError('missing payload')
    except (ValueError,IndexError,struct.error,UnicodeError) as exc:
        raise BuildError('XSA 中的 bitstream 不是完整的 Xilinx .bit 文件。') from exc

def read_xsa(path,assets):
    path=Path(path)
    if path.suffix.lower()!='.xsa' or not path.is_file():
        raise BuildError('必须提供 Vivado 导出的 XSA，并勾选 Include bitstream。')
    try:
        raw=path.read_bytes()
        with zipfile.ZipFile(path) as z:
            entries=z.infolist()
            if len({e.filename for e in entries})!=len(entries):
                raise BuildError('XSA 中有重复的归档文件名。')
            if sum(e.file_size for e in entries)>1024**3 or any(e.file_size>512*1024**2 for e in entries):
                raise BuildError('XSA 超出当前 Zynq-7020 配置支持的归档大小。')
            def one(suffix):
                names=[e.filename for e in entries if e.filename.lower().endswith(suffix)]
                if len(names)!=1: raise BuildError(f'XSA 必须恰好包含一个 {suffix} 文件，实际为 {len(names)}。')
                return names[0],z.read(names[0])
            bitname,bit=one('.bit')
            # Vivado also exports hierarchy/SmartConnect HWH files. Select the
            # unique system description containing PS7, never the first ZIP entry.
            hwh_candidates=[]; hwh_names=[]
            for entry in entries:
                if not entry.filename.lower().endswith('.hwh'): continue
                hwh_names.append(entry.filename)
                candidate=z.read(entry.filename)
                if b'<!DOCTYPE' in candidate or b'<!ENTITY' in candidate:
                    raise BuildError('HWH 不允许包含外部实体。')
                tree=ET.fromstring(candidate)
                count=sum(m.get('MODTYPE')=='processing_system7' for m in tree.iter('MODULE'))
                if count>1: raise BuildError('HWH 中存在多个 PS7，无法确定系统描述。')
                if count==1: hwh_candidates.append((entry.filename,candidate))
            if len(hwh_candidates)!=1:
                raise BuildError(f'XSA 必须恰好包含一个有 PS7 的系统 HWH，实际为 {len(hwh_candidates)}。')
            hwhname,hwh=hwh_candidates[0]
            named={Path(e.filename).name:e.filename for e in entries}
            for n in ('ps7_init.c','ps7_init.h','xsa.json'):
                if n not in named: raise BuildError(f'XSA 缺少 {n}，请重新导出完整硬件平台。')
            init=z.read(named['ps7_init.c']); inith=z.read(named['ps7_init.h'])
            metadata=json.loads(z.read(named['xsa.json']))
    except (zipfile.BadZipFile,KeyError,json.JSONDecodeError,ET.ParseError) as exc:
        raise BuildError(f'无法解析 XSA：{exc}') from exc
    root,ps=ps_parameters(hwh)
    version=root.get('VIVADOVERSION','')
    if version!='2025.2': raise BuildError(f'当前版本支持 Vivado 2025.2，当前 XSA 为 {version}。')
    devices=metadata.get('devices',[])
    parts=[d.get('part',{}).get('name') for d in devices]
    if parts!=['xc7z020clg484-1']:
        raise BuildError(f'器件不符合 EES-331：{parts}，需要 xc7z020clg484-1。')
    bi=bit_info(bit)
    if '7z020' not in bi.get('b','').lower() or 'clg484' not in bi.get('b','').lower():
        raise BuildError('位流器件字段与 EES-331 不匹配。')
    required={
        'PCW_UART1_PERIPHERAL_ENABLE':'1','PCW_UART1_UART1_IO':'MIO 48 .. 49',
        'PCW_UART1_BAUD_RATE':'115200','PCW_SD0_PERIPHERAL_ENABLE':'1',
        'PCW_SD0_SD0_IO':'MIO 40 .. 45','PCW_DDR_RAM_HIGHADDR':'0x3FFFFFFF',
        'PCW_CRYSTAL_PERIPHERAL_FREQMHZ':'33.333333',
    }
    bad={k:dict(required=v,actual=ps.get(k)) for k,v in required.items() if ps.get(k)!=v}
    if bad: raise BuildError('当前板级配置不兼容，不能沿用 EES-331 启动基线：\n'+json.dumps(bad,ensure_ascii=False,indent=2))
    _,ref=ps_parameters((assets/'reference.hwh').read_bytes())
    keys=sorted(k for k in set(ps)|set(ref) if k.startswith('PCW_'))
    changes=[dict(parameter=k,before=ref.get(k),after=ps.get(k)) for k in keys if ps.get(k)!=ref.get(k)]
    from board_profile import compatible_board
    board=compatible_board(ps,ref)
    dt_changes=[]  # v0.2 uses concrete topology requirements, not a PCW prefix gate.
    ip=[dict(name=m.get('INSTANCE'),vlnv=m.get('VLNV')) for m in root.iter('MODULE') if m.get('IS_PL')=='TRUE']
    summary=dict(xsa_path=str(path.resolve()),xsa_sha256=digest(raw),vivado_version=version,
                 part=parts[0],bitstream_name=bitname,bitstream_sha256=digest(bit),
                 hwh_name=hwhname,hwh_sha256=digest(hwh),auxiliary_hwh=[n for n in hwh_names if n!=hwhname],bit_header=bi,
                 ps_changes=changes,device_tree_review_changes=dt_changes,pl_ip=ip,
                 requires_fsbl_rebuild=bool(changes) or digest(init)!=digest((assets/'reference_init.c').read_bytes()),
                 board_profile=board,device_tree_mode='AUTO_EES331',
                 status='NEEDS_BOARD_DETAILS' if board['requirements'] else 'AUTO_READY')
    return summary,dict(bit=bit,hwh=hwh,init=init,inith=inith,ps=ps)
