#!/usr/bin/python3
"""M13 run02: poll CSR STATUS (busy[0], ldone_cnt[31:16]) every 2s, 20 min cap.
Read-only /dev/mem mmap (this board rejects lseek+read with EFAULT)."""
import os, struct, mmap, time

fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, offset=0x43C10000, flags=mmap.MAP_SHARED, prot=mmap.PROT_READ)
t0 = time.monotonic()
for i in range(600):
    v = struct.unpack("<I", m[12:16])[0]
    print("%8.1f STATUS=0x%08X busy=%d ldone=%d" % (
        time.monotonic() - t0, v, v & 1, (v >> 16) & 0xFFFF), flush=True)
    time.sleep(2)
print("POLL_TIMEOUT", flush=True)
