#!/usr/bin/env python3
"""Walk a flattened device tree blob (DTB) and dump selected properties.

Usage: python inspect_dtb.py <path/to/system.dtb>

Prints node paths and properties of interest for verifying an EES-331 PYNQ
image adaptation: console/UART, memory size, Ethernet (gem0/PHY), SD controller.
"""
import struct
import sys

FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9

INTERESTING = (
    "bootargs", "stdout-path", "compatible", "reg", "status",
    "serial-number", "model", "phy-mode", "phy-handle", "xlnx,phy-type",
    "clock-frequency", "current-speed", "xlnx,has-mdio", "mdio",
)


def read_prop(data):
    val = data
    # try to render printable ascii
    if all(32 <= b < 127 or b in (0, 10, 13) for b in val.rstrip(b"\x00")) and val:
        txt = val.rstrip(b"\x00").decode("ascii", "replace").replace("\n", "\\n")
        return f'"{txt}"'
    if len(val) % 4 == 0 and len(val) <= 32:
        words = struct.unpack(">" + "I" * (len(val) // 4), val)
        return "0x" + " 0x".join(f"{w:x}" for w in words)
    return val[:24].hex(" ") + ("..." if len(val) > 24 else "")


def main(path):
    blob = open(path, "rb").read()
    magic, totalsize, off_struct, off_strings, off_rsv = struct.unpack(
        ">IIIII", blob[:20])
    assert magic == 0xD00DFEED, f"not a DTB: magic=0x{magic:x}"
    print(f"DTB OK: total={totalsize} struct@{off_struct} strings@{off_strings}")

    pos = off_struct
    path_stack = []
    cur_path = ""
    while pos < len(blob):
        token = struct.unpack(">I", blob[pos:pos + 4])[0]
        pos += 4
        if token == FDT_BEGIN_NODE:
            end = blob.index(b"\x00", pos)
            name = blob[pos:end].decode("ascii", "replace")
            pos = (end + 1 + 3) & ~3
            path_stack.append(name)
            cur_path = "/" + "/".join(p for p in path_stack if p)
            print(f"\nNODE {cur_path}")
        elif token == FDT_END_NODE:
            path_stack.pop()
        elif token == FDT_PROP:
            plen, nameoff = struct.unpack(">II", blob[pos:pos + 8])
            pos += 8
            end = blob.index(b"\x00", off_strings + nameoff)
            pname = blob[off_strings + nameoff:end].decode("ascii", "replace")
            val = blob[pos:pos + plen]
            pos += (plen + 3) & ~3
            if pname in INTERESTING or cur_path.startswith(("/memory", "/chosen", "/cpus")):
                print(f"  {pname} = {read_prop(val)}")
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            print("\nFDT_END")
            break
        else:
            print(f"UNKNOWN token {token} at {pos - 4}")
            break


if __name__ == "__main__":
    main(sys.argv[1])
