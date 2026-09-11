#!/usr/bin/env python3
"""Extract the FAT16 boot-partition files from an EES-331 PYNQ SD image.

Usage: python extract_boot_files.py <img> <outdir>
Extracts every boot-partition file into <outdir>/boot_files/ and prints hashes.
"""
import hashlib
import os
import struct
import sys


def main(img, outdir):
    bd = os.path.join(outdir, "boot_files")
    os.makedirs(bd, exist_ok=True)
    with open(img, "rb") as f:
        m = f.read(512)
        assert m[510:512] == b"\x55\xaa", "not MBR"
        part_lba = struct.unpack("<I", m[446 + 8:446 + 12])[0]
        f.seek(part_lba * 512)
        bs = f.read(512)
        bps = struct.unpack("<H", bs[11:13])[0]
        spc = bs[13]
        rsvd = struct.unpack("<H", bs[14:16])[0]
        nfats = bs[16]
        roote = struct.unpack("<H", bs[17:19])[0]
        spf = struct.unpack("<H", bs[22:24])[0]
        print(f"FAT16: bps={bps} spc={spc} rsvd={rsvd} nfats={nfats} roote={roote} spf={spf}")

        fat_off = part_lba * 512 + rsvd * bps
        f.seek(fat_off)
        fat = f.read(spf * bps)

        def next_clus(c):
            return struct.unpack("<H", fat[c * 2:c * 2 + 2])[0]

        root_off = fat_off + nfats * spf * bps
        data_start = root_off + roote * 32
        f.seek(root_off)
        rd = f.read(roote * 32)
        for i in range(0, len(rd), 32):
            e = rd[i:i + 32]
            if e[0] == 0x00:
                break
            if e[0] == 0xE5 or e[11] & 0x08 or e[11] & 0x10:
                continue
            name = e[0:8].decode("ascii", "replace").strip()
            ext = e[8:11].decode("ascii", "replace").strip()
            size = struct.unpack("<I", e[28:32])[0]
            clus = struct.unpack("<H", e[26:28])[0]
            out = bytearray()
            c = clus
            while size > 0 and c < 0xFFF8:
                f.seek(data_start + (c - 2) * bps * spc)
                out += f.read(bps * spc)
                c = next_clus(c)
            data = bytes(out[:size])
            fn = f"{name}.{ext}".lower()
            with open(os.path.join(bd, fn), "wb") as w:
                w.write(data)
            print(f"{fn:16} {size:>12}  sha256={hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
