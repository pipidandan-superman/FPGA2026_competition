import hashlib,json,time
from pathlib import Path
from fdt_reader import parse
root=Path(__file__).resolve().parent
original=parse((root/'sd_backup/image.ub').read_bytes())
kernel=original['/images/kernel-0']['data']
dtb=(root/'candidate/system.dtb').read_bytes()
(root/'candidate/kernel.bin').write_bytes(kernel)
kernel_hash=hashlib.sha1(kernel).digest(); dtb_hash=hashlib.sha1(dtb).digest()
hexbytes=lambda b:' '.join(f'{x:02x}' for x in b)
source='''/dts-v1/;
/ {
    description = "EES-331 PYNQ 3.0.1 ARM kernel and board device tree";
    #address-cells = <1>;
    timestamp = <TIMESTAMP>;
    images {
        kernel-0 {
            description = "Original PYNQ 3.0.1 Linux kernel";
            data = /incbin/("kernel.bin");
            type = "kernel";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0x00080000>;
            entry = <0x00080000>;
            hash-1 { algo = "sha1"; value = [KERNEL_HASH]; };
        };
        fdt-0 {
            description = "EES-331 PS-only device tree";
            data = /incbin/("system.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash-1 { algo = "sha1"; value = [DTB_HASH]; };
        };
    };
    configurations {
        default = "conf-1";
        conf-1 {
            description = "EES-331 Linux with UART1 and 1GiB DDR";
            kernel = "kernel-0";
            fdt = "fdt-0";
        };
    };
};
'''.replace('TIMESTAMP',str(int(time.time()))).replace('KERNEL_HASH',hexbytes(kernel_hash)).replace('DTB_HASH',hexbytes(dtb_hash))
(root/'candidate/image.its').write_text(source,encoding='utf-8')
result=dict(kernel_sha256=hashlib.sha256(kernel).hexdigest(),kernel_unchanged=True,dtb_sha256=hashlib.sha256(dtb).hexdigest())
(root/'fit_inputs.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
