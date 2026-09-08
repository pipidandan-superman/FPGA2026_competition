#!/usr/bin/env python3
"""Continuously send a type=0x01 camera frame whose bytes replicate the
VDMA-packed DDR order ([B,G,R]) with the three true object colors, for the
GUI exe visual verification. Bars: yellow | blue-violet | lavender."""
import socket
import struct
import sys
import time
import zlib

HEADER_FMT = ">4sBBH I HHHHHH II"
W, H = 640, 480
PAYLOAD = 1440
PACKETS = (W * H * 3) // PAYLOAD
TRUE = [(250, 230, 150), (150, 140, 230), (210, 180, 230)]  # No.3, No.2, No.1

buf = bytearray()
third = W // 3
for _row in range(H):
    for col in range(W):
        r, g, b = TRUE[min(col // third, 2)]
        buf += bytes((b, g, r))  # DDR/UDP camera byte order
frame = bytes(buf)
crc = zlib.crc32(frame) & 0xFFFFFFFF

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dst = ("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 5000)
print(f"sending camera-type BGR bars to {dst} at ~5 fps, Ctrl+C to stop")
fid = 0
while True:
    for pid in range(PACKETS):
        chunk = frame[pid * PAYLOAD : (pid + 1) * PAYLOAD]
        flags = 0x0001 if pid == 0 else (0x0002 if pid == PACKETS - 1 else 0)
        header = struct.pack(
            HEADER_FMT, b"OV56", 1, 0x01, flags, fid, pid, PACKETS,
            len(chunk), W, H, W * 3, 0, crc)
        sock.sendto(header + chunk, dst)
    fid += 1
    time.sleep(0.2)
