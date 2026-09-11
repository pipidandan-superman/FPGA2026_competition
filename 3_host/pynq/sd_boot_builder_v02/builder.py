"""EES-331 XSA-to-SD builder. All new builds are isolated, never written to a card."""
import argparse
import ctypes
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import traceback
import uuid
import zipfile

from hardware import BuildError,digest,read_xsa
from fdt_reader import parse,be,text
from images import build_image,verify_base,BASE_NAME
from rootfs import prepare_application_bundle
from board_profile import dts_rules,validate_generated

APP=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parent))
ASSETS=APP/'assets'
WORKSPACE=Path('E:/competition')
DEFAULT_VITIS='F:/vivado2025/2025.2/Vitis'
DEFAULT_BASE='E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/'+BASE_NAME
near_exe=Path(sys.executable).parent/BASE_NAME
if near_exe.is_file(): DEFAULT_BASE=str(near_exe)

def save(path,value):
    Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

def verify_assets():
    manifest=json.loads((ASSETS/'manifest.json').read_text())
    for name,m in manifest.items():
        data=(ASSETS/name).read_bytes()
        if len(data)!=m['size'] or digest(data)!=m['sha256']:
            raise BuildError('基线资源损坏：'+name)
    application=json.loads((ASSETS/'pynq_app/manifest.json').read_text(encoding='utf-8'))
    for name,m in application['files'].items():
        data=(ASSETS/'pynq_app'/name).read_bytes()
        if len(data)!=m['size'] or digest(data)!=m['sha256']:
            raise BuildError('PYNQ 应用资源损坏：'+name)

def inspect(xsa):
    verify_assets()
    return read_xsa(xsa,ASSETS)[0]

def validate_dtb(data,ps):
    try:
        d=parse(data)
        uart=text(d['/aliases']['serial0'])
        if uart!='/axi/serial@e0001000' or text(d[uart]['status'])!='okay':
            raise BuildError('设备树必须启用 EES-331 UART1 并将其设为 serial0。')
        mem=[v for v in d.values() if v.get('device_type')==b'memory\0']
        if len(mem)!=1 or struct.unpack('>II',mem[0]['reg'])!=(0,0x40000000):
            raise BuildError('设备树的 DDR 必须为地址 0、1GiB。')
        if be(d['/axi/slcr@f8000000/clkc@100']['ps-clk-frequency'])!=33333333:
            raise BuildError('设备树 PS 晶振与 EES-331 不符。')
        mappings={'PCW_UART0_PERIPHERAL_ENABLE':'serial@e0000000',
                  'PCW_SD0_PERIPHERAL_ENABLE':'mmc@e0100000',
                  'PCW_USB0_PERIPHERAL_ENABLE':'usb@e0002000',
                  'PCW_ENET0_PERIPHERAL_ENABLE':'ethernet@e000b000',
                  'PCW_I2C0_PERIPHERAL_ENABLE':'i2c@e0004000',
                  'PCW_I2C1_PERIPHERAL_ENABLE':'i2c@e0005000',
                  'PCW_QSPI_PERIPHERAL_ENABLE':'spi@e000d000'}
        for param,node in mappings.items():
            if param not in ps: continue
            props=d.get('/axi/'+node,{})
            enabled=bool(props) and props.get('status',b'okay\0') not in (b'disabled\0',b'fail\0')
            if enabled!=(ps[param]=='1'): raise BuildError(f'DTB 与 XSA 外设状态不一致：{param}')
        ph={be(v['phandle']):k for k,v in d.items() if 'phandle' in v}
        for path,props in d.items():
            if 'interrupt-parent' in props and be(props['interrupt-parent']) not in ph:
                raise BuildError(f'DTB interrupt-parent 无效：{path}')
        return d
    except (KeyError,ValueError,struct.error,TypeError) as exc:
        raise BuildError(f'设备树结构或当前板级路径不匹配：{exc}') from exc

class Builder:
    def __init__(self,xsa,vitis=DEFAULT_VITIS,base=DEFAULT_BASE,dtb='',mode='manual',full_image=False,rebuild_fsbl=False,log=print,usb_role='otg',integrate_pynq=False,debugfs=''):
        if mode not in ('manual','linux','fsbl'): raise BuildError('未知 PL 加载方式。')
        self.xsa=Path(xsa); self.vitis=Path(vitis); self.base=Path(base)
        self.custom_dtb=Path(dtb) if dtb else None
        self.mode=mode; self.full_image=full_image; self.force=rebuild_fsbl
        self.usb_role=usb_role; self.integrate_pynq=integrate_pynq; self.debugfs=debugfs
        self.callback=log; self.command_index=0
        self.run=WORKSPACE/'4_metrics/logs'/(''+datetime.now().strftime('%Y-%m-%d_sd_builder_v02_%H%M%S_')+uuid.uuid4().hex[:6])
        self.work=self.run/'work'; self.boot=self.run/'boot'; self.out=self.run/'.pending-output'

    def log(self,line):
        line=str(line)
        self.callback(line)
        with (self.run/'build.log').open('a',encoding='utf-8') as f: f.write(line+'\n')

    def command(self,args,cwd=None,env=None):
        self.command_index+=1
        args=[str(a) for a in args]
        if any(any(c in a for c in '\r\n&|<>^%') for a in args):
            raise BuildError('工具路径含不支持的命令解释字符。')
        logfile=self.run/f'command_{self.command_index:03d}.log'
        self.log('运行 '+Path(args[0]).name)
        with logfile.open('w',encoding='utf-8') as capture:
            capture.write(json.dumps(args,ensure_ascii=False)+'\n'); capture.flush()
            restore_dll_dir=str(APP) if os.name=='nt' and getattr(sys,'frozen',False) else None
            if restore_dll_dir:
                ctypes.windll.kernel32.SetDllDirectoryW(None)
            try:
                result=subprocess.run(args,cwd=str(cwd or self.work),env=env,stdout=capture,stderr=subprocess.STDOUT,timeout=1200,
                                      creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            finally:
                if restore_dll_dir:
                    ctypes.windll.kernel32.SetDllDirectoryW(restore_dll_dir)
        if result.returncode:
            tail='\n'.join(logfile.read_text(encoding='utf-8',errors='replace').splitlines()[-14:])
            raise BuildError(f'{Path(args[0]).name} 失败，见 {logfile}\n{tail}')

    def build_fsbl(self,inputs):
        self.log('从当前 XSA 生成新的 FSBL/BSP。')
        script=self.work/'generate_fsbl.tcl'
        script.write_text('setws $::env(SD_BUILDER_WS)\nplatform create -name sd_platform -hw $::env(SD_BUILDER_XSA) -proc ps7_cortexa9_0 -os standalone\nplatform generate\nputs "SD_BUILDER_PLATFORM_GENERATED"\nexit\n')
        env=os.environ.copy()
        for key in ('TCL_LIBRARY','TCLLIBPATH','TCLLIBRARY','TCLLIB'):
            env.pop(key,None)
        env['SD_BUILDER_WS']=str(self.work/'vitis_workspace').replace('\\','/')
        env['SD_BUILDER_XSA']=str(self.work/'input.xsa').replace('\\','/')
        self.command([self.vitis/'bin/xsct.bat',script],env=env)
        generated=self.work/'vitis_workspace/sd_platform/zynq_fsbl'
        bsp=generated/'zynq_fsbl_bsp/ps7_cortexa9_0'
        if not (bsp/'lib/libxil.a').is_file(): raise BuildError('工具链未生成当前 XSA 的 FSBL BSP。')
        build=self.work/'fsbl_build'; build.mkdir()
        for p in generated.iterdir():
            if p.is_file() and (p.suffix in ('.c','.h','.S') or p.name in ('lscript.ld','Xilinx.spec')):
                shutil.copyfile(p,build/p.name)
        shutil.copytree(bsp/'include',build/'include'); shutil.copytree(bsp/'lib',build/'lib')
        (build/'ps7_init.c').write_bytes(inputs['init']); (build/'ps7_init.h').write_bytes(inputs['inith'])
        arm=self.vitis/'gnu/aarch32/nt/gcc-arm-none-eabi/bin'
        gcc=arm/'arm-none-eabi-gcc.exe'
        flags=['-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-DFSBL_DEBUG_INFO','-O2','-g3','-Iinclude','-I.']
        objects=[]
        for source in sorted(build.iterdir()):
            if source.suffix in ('.c','.S'):
                obj=source.stem+'.o'
                self.command([gcc,*flags,'-c',source.name,'-o',obj],cwd=build); objects.append(obj)
        link=['-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-Wl,--build-id=none','-specs=Xilinx.spec',
              '-Wl,--gc-sections','-Wl,-Map=fsbl.map','-Llib','-L.','-Tlscript.ld','-Wl,--start-group',
              '-lxilffs','-lrsa','-lxil','-lgcc','-lc','-Wl,--end-group']
        self.command([gcc,'-o','fsbl.elf',*objects,*link],cwd=build)
        elf=(build/'fsbl.elf').read_bytes()
        if b'Xilinx First Stage Boot Loader' not in elf: raise BuildError('新 FSBL 未包含调试横幅。')
        shutil.copyfile(build/'fsbl.elf',self.work/'fsbl.elf')
        save(self.run/'fsbl_provenance.json',dict(source='REGENERATED_FROM_INPUT_XSA',ps7_init_sha256=digest(inputs['init']),elf_sha256=digest(elf)))

    def device_tree(self,summary,inputs):
        requirements=summary['board_profile']['requirements']
        if requirements and not self.custom_dtb:
            raise BuildError('需要补充以下具体板级信息：\n'+'\n'.join(requirements)+'\n常规板载 PS 配置已自动处理；这些扩展可通过高级 DTB 覆盖。')
        dtb=self.custom_dtb.read_bytes() if self.custom_dtb else (ASSETS/'system.dtb').read_bytes()
        # A custom DTB is a complete advanced override, not silently overwritten.
        if self.custom_dtb:
            validate_dtb(dtb,inputs['ps']); validation=validate_generated(dtb,inputs['ps'])
            (self.work/'system.dtb').write_bytes(dtb)
            self.command([self.vitis/'bin/dtc.exe','-I','dtb','-O','dts','-o','board-expanded.dts','system.dtb'])
            save(self.run/'device_tree_generation.json',dict(mode='EXPLICIT_ADVANCED_OVERRIDE',requirements=requirements,validation=validation,sha256=digest(dtb)))
            shutil.copyfile(self.work/'system.dtb',self.boot/'system.dtb')
            return
        (self.work/'base.dtb').write_bytes(dtb)
        dtc=self.vitis/'bin/dtc.exe'
        self.command([dtc,'-I','dtb','-O','dts','-o','base.dts','base.dtb'])
        from hardware import ps_parameters
        ref=ps_parameters((ASSETS/'reference.hwh').read_bytes())[1]
        override=dts_rules(inputs['ps'],ref,dtb,self.usb_role)
        (self.work/'board.dts').write_text(override,encoding='utf-8')
        self.command([dtc,'-I','dts','-O','dtb','-o','system.dtb','board.dts'])
        self.command([dtc,'-I','dtb','-O','dts','-o','board-expanded.dts','system.dtb'])
        validate_dtb((self.work/'system.dtb').read_bytes(),inputs['ps'])
        validation=validate_generated((self.work/'system.dtb').read_bytes(),inputs['ps'])
        save(self.run/'device_tree_generation.json',dict(mode='AUTO_XSA_PLUS_EES331_PROFILE',profile='EES331_PS_0.2',usb_role=self.usb_role,validation=validation,controllers=summary['board_profile']['controllers'],warnings=summary['board_profile']['warnings']))
        shutil.copyfile(self.work/'system.dtb',self.boot/'system.dtb')

    def fit(self):
        shutil.copyfile(ASSETS/'kernel.bin',self.work/'kernel.bin')
        kernel=(self.work/'kernel.bin').read_bytes(); dtb=(self.work/'system.dtb').read_bytes()
        hexhash=lambda b:' '.join(f'{x:02x}' for x in hashlib.sha1(b).digest())
        its='''/dts-v1/;
/ {
 description = "EES-331 PYNQ 3.0.1"; #address-cells = <1>;
 images {
  kernel-0 { data = /incbin/("kernel.bin"); type = "kernel"; arch = "arm"; os = "linux"; compression = "none"; load = <0x80000>; entry = <0x80000>;
   hash-1 { algo = "sha1"; value = [KERNEL_HASH]; }; };
  fdt-0 { data = /incbin/("system.dtb"); type = "flat_dt"; arch = "arm"; compression = "none";
   hash-1 { algo = "sha1"; value = [DTB_HASH]; }; };
 };
 configurations { default = "conf-1"; conf-1 { kernel = "kernel-0"; fdt = "fdt-0"; }; };
};
'''.replace('KERNEL_HASH',hexhash(kernel)).replace('DTB_HASH',hexhash(dtb))
        (self.work/'image.its').write_text(its)
        self.command([self.vitis/'bin/dtc.exe','-I','dts','-O','dtb','-p','1024','-o','image.ub','image.its'])
        fit=parse((self.work/'image.ub').read_bytes())
        for name,payload in [('kernel-0',kernel),('fdt-0',dtb)]:
            if fit['/images/'+name]['data']!=payload or fit['/images/'+name+'/hash-1']['value']!=hashlib.sha1(payload).digest():
                raise BuildError('FIT 校验失败。')
        shutil.copyfile(self.work/'image.ub',self.boot/'image.ub')

    def bootgen(self):
        shutil.copyfile(ASSETS/'u-boot.elf',self.work/'u-boot.elf')
        entries=['[bootloader] fsbl.elf']
        if self.mode=='fsbl': entries.append('overlay.bit')
        entries+=['u-boot.elf','[load=0x00100000] system.dtb']
        (self.work/'boot.bif').write_text('the_ROM_image:\n{\n '+'\n '.join(entries)+'\n}\n')
        self.command([self.vitis/'bin/bootgen.bat','-arch','zynq','-image','boot.bif','-o','BOOT.BIN','-w','on'])
        self.command([self.vitis/'bin/bootgen.bat','-arch','zynq','-read','BOOT.BIN'])
        b=(self.work/'BOOT.BIN').read_bytes(); word=lambda off:struct.unpack_from('<I',b,off)[0]
        if word(32)!=0xaa995566 or word(36)!=0x584c4e58 or sum(struct.unpack_from('<11I',b,32))&0xffffffff!=0xffffffff:
            raise BuildError('BOOT 启动头校验失败。')
        count=word(word(0x98)+4)
        if count!=(4 if self.mode=='fsbl' else 3) or not 0<word(0x34)<0x30000:
            raise BuildError('BOOT 分区数或 FSBL 长度不正确。')
        parts=[]
        for i in range(count):
            w=struct.unpack_from('<16I',b,word(0x9c)+i*64)
            if sum(w)&0xffffffff!=0xffffffff or w[5]*4+w[2]*4>len(b):
                raise BuildError('BOOT 分区头/范围校验失败。')
            parts.append((w,b[w[5]*4:(w[5]+w[1])*4]))
        if word(0x30)!=parts[0][0][5]*4 or word(0x34)!=parts[0][0][1]*4 or word(0x40)!=word(0x34):
            raise BuildError('BootROM 的 FSBL 字段与实际分区不一致。')
        if any(parts[i][0][5]*4+parts[i][0][2]*4>parts[i+1][0][5]*4 for i in range(count-1)):
            raise BuildError('BOOT 文件分区发生重叠。')
        if self.mode=='fsbl':
            bit=(self.work/'overlay.bit').read_bytes()
            from hardware import bit_info
            size=bit_info(bit)['payload_size']; payload=bit[-size:]
            swapped=b''.join(payload[i:i+4][::-1] for i in range(0,len(payload),4))
            if parts[1][1][:size] not in (payload,swapped):
                raise BuildError('BOOT 中的 PL 载荷与 XSA 位流不一致。')
        if parts[-2][0][3:5]!=(0x04000000,0x04000000) or parts[-1][0][3]!=0x100000:
            raise BuildError('BOOT 的 U-Boot/DTB 加载地址不正确。')
        dtb=(self.work/'system.dtb').read_bytes()
        if parts[-1][1][:len(dtb)]!=dtb: raise BuildError('BOOT 控制 DTB 载荷不匹配。')
        for name,part in [('fsbl.elf',parts[0]),('u-boot.elf',parts[-2])]:
            elf=(self.work/name).read_bytes()
            if elf[:6]!=b'\x7fELF\x01\x01': raise BuildError('ELF 格式不正确。')
            phoff=struct.unpack_from('<I',elf,28)[0]; ents,n=struct.unpack_from('<HH',elf,42)
            for i in range(n):
                s=struct.unpack_from('<8I',elf,phoff+i*ents)
                if s[0]==1 and s[4]:
                    off=s[3]-part[0][3]
                    if off<0 or part[1][off:off+s[4]]!=elf[s[1]:s[1]+s[4]]: raise BuildError(name+' LOAD 载荷不匹配。')
        save(self.run/'boot_validation.json',dict(result='PASS',fsbl_source=word(0x30),fsbl_length=word(0x34),partition_count=count,partitions=[list(p[0]) for p in parts],hardware_status='NOT_TESTED'))
        shutil.copyfile(self.work/'BOOT.BIN',self.boot/'BOOT.BIN')

    def execute(self):
        for d in (self.work,self.boot,self.out): d.mkdir(parents=True,exist_ok=False)
        try:
            self.log('检查输入 XSA 与基线资源。')
            if self.integrate_pynq and not self.full_image:
                raise BuildError('整合 EES-331 摄像头 PYNQ 应用必须同时输出完整 IMG。')
            if self.integrate_pynq and self.mode!='manual':
                raise BuildError('整合摄像头服务时 PL 加载方式必须为“手动加载”；systemd 服务负责唯一一次 Overlay 加载。')
            verify_assets()
            summary,inputs=read_xsa(self.xsa,ASSETS)
            save(self.run/'hardware_analysis.json',summary)
            if not (self.vitis/'bin/bootgen.bat').is_file() or not (self.vitis/'bin/dtc.exe').is_file():
                raise BuildError('找不到 Vitis 2025.2 Bootgen/DTC，请检查工具目录。')
            if self.full_image:
                save(self.run/'base_image_verification.json',verify_base(self.base,self.log))
            shutil.copyfile(self.xsa,self.work/'input.xsa')
            if digest((self.work/'input.xsa').read_bytes())!=summary['xsa_sha256']: raise BuildError('输入 XSA 在读取期间发生变化。')
            (self.work/'overlay.bit').write_bytes(inputs['bit'])
            (self.boot/'overlay.bit').write_bytes(inputs['bit']); (self.boot/'overlay.hwh').write_bytes(inputs['hwh'])
            self.device_tree(summary,inputs)
            if summary['requires_fsbl_rebuild'] or self.force: self.build_fsbl(inputs)
            else:
                self.log('PS 初始化与已验证基线相同，复用已验证 FSBL。')
                shutil.copyfile(ASSETS/'fsbl.elf',self.work/'fsbl.elf')
                save(self.run/'fsbl_provenance.json',dict(source='BOARD_VALIDATED_BASELINE',elf_sha256=digest((ASSETS/'fsbl.elf').read_bytes())))
            self.bootgen(); self.fit()
            for name in ('boot.scr','REVISION'): shutil.copyfile(ASSETS/name,self.boot/name)
            hook='#!/usr/bin/env python3\n'
            if self.mode=='linux':
                hook+='from pynq import Overlay\nprint("EES-331: loading XSA overlay")\noverlay = Overlay("/boot/overlay.bit")\nprint("EES-331: overlay loaded")\n'
            else:
                hook+='print("EES-331: PL loading mode '+self.mode+'")\n'
            (self.boot/'boot.py').write_text(hook,encoding='utf-8',newline='\n')
            application=None
            application_manifest=None
            if self.integrate_pynq:
                self.log('准备经过板测的 EES-331 摄像头 PYNQ 应用。')
                shutil.copyfile(ASSETS/'pynq_app/uEnv.txt',self.boot/'uEnv.txt')
                application=self.work/'pynq_application'
                application_manifest=prepare_application_bundle(
                    ASSETS/'pynq_app',self.boot,summary['xsa_sha256'],application)
            files={p.name:dict(size=p.stat().st_size,sha256=digest(p.read_bytes())) for p in self.boot.iterdir()}
            manifest=dict(result='SD_PACKAGE_STATIC_PASS',tool_version='0.2.1',created=datetime.now().isoformat(),
                          xsa=summary,pl_loading=self.mode,files=files,hardware_status='NOT_TESTED',
                          usb_role=self.usb_role,device_tree_generation=json.loads((self.run/'device_tree_generation.json').read_text(encoding='utf-8')),
                          pynq_application=application_manifest,
                          baseline_status=('PYNQ_APPLICATION_IMAGE_INTEGRATED; REQUIRES_COLD_BOOT_VALIDATION'
                                           if application_manifest else
                                           'SD_LINUX_SHELL_PASS; NETWORK_AND_PL_APPLICATION_NOT_ACCEPTED'))
            save(self.out/'manifest.json',manifest)
            note='EES-331 SD boot package\nCopy every file in boot/ to the SD boot partition together.\nPL mode: '+self.mode+'\nXSA SHA256: '+summary['xsa_sha256']+'\nPYNQ camera application: '+('integrated in full IMG' if application_manifest else 'not integrated')+'\nNew hardware configuration requires cold-boot and application validation.\n'
            (self.out/'README.txt').write_text(note,encoding='utf-8')
            archive=self.out/'sd_boot_package.zip'
            with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
                for p in sorted(self.boot.iterdir()): z.write(p,'boot/'+p.name)
                z.write(self.out/'manifest.json','manifest.json'); z.write(self.out/'README.txt','README.txt')
            with zipfile.ZipFile(archive) as z:
                if z.testzip(): raise BuildError('ZIP CRC 校验失败。')
                for name,m in files.items():
                    if digest(z.read('boot/'+name))!=m['sha256']: raise BuildError('ZIP 文件哈希不匹配。')
            if self.full_image:
                self.log('生成完整 IMG 并进行全文件读回。')
                image=self.out/'ees331_pynq_sd.img'
                validation=build_image(self.base,self.boot,image,self.log,application,self.debugfs)
                manifest['image']=validation
                (self.out/'ees331_pynq_sd.img.sha256').write_text(validation['sha256']+'  '+image.name+'\n')
            final_output=self.run/'output'
            manifest['output']=str(final_output)
            save(self.out/'result.json',manifest)
            self.out.rename(final_output)
            self.out=final_output
            save(self.run/'result.json',manifest)
            self.log('导出完成：'+str(self.out))
            return manifest
        except Exception as exc:
            save(self.run/'result.json',dict(result='BUILD_FAILED',error=str(exc),hardware_status='NOT_TESTED'))
            (self.run/'exception.txt').write_text(traceback.format_exc(),encoding='utf-8')
            self.log('构建停止：'+str(exc))
            # Outputs remain for diagnosis; only result.json with PASS is releasable.
            raise

def main():
    parser=argparse.ArgumentParser(description='EES-331 XSA SD Builder')
    parser.add_argument('--xsa',required=True); parser.add_argument('--inspect',action='store_true')
    parser.add_argument('--vitis',default=DEFAULT_VITIS); parser.add_argument('--base-img',default=DEFAULT_BASE)
    parser.add_argument('--dtb',default=''); parser.add_argument('--mode',choices=['manual','linux','fsbl'],default='manual')
    parser.add_argument('--full-image',action='store_true'); parser.add_argument('--rebuild-fsbl',action='store_true')
    parser.add_argument('--usb-role',choices=['otg','host','peripheral'],default='otg')
    parser.add_argument('--integrate-pynq-app',action='store_true')
    parser.add_argument('--debugfs',default='')
    args=parser.parse_args()
    try:
        if args.inspect: print(json.dumps(inspect(args.xsa),ensure_ascii=False,indent=2))
        else: Builder(args.xsa,args.vitis,args.base_img,args.dtb,args.mode,args.full_image,args.rebuild_fsbl,
                      usb_role=args.usb_role,integrate_pynq=args.integrate_pynq_app,debugfs=args.debugfs).execute()
    except Exception as exc:
        print(str(exc),file=sys.stderr); return 1
    return 0

if __name__=='__main__':
    raise SystemExit(main())
