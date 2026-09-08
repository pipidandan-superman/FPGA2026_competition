#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""End-to-end verification for the UDP camera-frame R/B swap fix (run01).

Sends, over real localhost UDP datagrams:
  1. a type=0x01 camera frame whose pixel bytes replicate the VDMA-packed
     DDR layout ([B,G,R] per pixel) using the true colors of the three
     board-test objects (yellow / blue-violet / lavender), and
  2. a type=0x02 pattern frame with software-packed [R,G,B] bars,
then drives the actual Receiver class from udp_video_gui.py and asserts the
decoded pixels match the true colors (and prints what the pre-fix decoder
would have produced, as the documented "before" evidence).
"""
import queue
import socket
import struct
import sys
import time
import zlib

sys.path.insert(0, r"E:\competition\3_host\udp_video")
from udp_video_gui import Receiver  # noqa: E402

from PIL import Image  # noqa: E402

HEADER_FMT = ">4sBBH I HHHHHH II"
HEADER_LEN = struct.calcsize(HEADER_FMT)
W, H = 640, 480
PAYLOAD = 1440
PACKETS = 640

# true RGB colors of board objects (Apple-photo reference)
TRUE_COLORS = {
    "No.3 yellow (RGB 250,230,150)": (250, 230, 150),
    "No.2 blue-violet (RGB 150,140,230)": (150, 140, 230),
    "No.1 lavender (RGB 210,180,230)": (210, 180, 230),
}


def build_camera_frame_bgr(colors):
    """Camera frames: VDMA packs the 24-bit {R,G,B} AXIS word little-endian,
    so DDR/UDP bytes per pixel are [B,G,R]."""
    buf = bytearray()
    third = W // 3
    for _row in range(H):
        for col in range(W):
            r, g, b = colors[min(col // third, 2)]
            buf += bytes((b, g, r))
    return bytes(buf)


def build_pattern_frame_rgb(colors):
    """Pattern frames (board type 0x02): software-packed [R,G,B]."""
    buf = bytearray()
    third = W // 3
    for _row in range(H):
        for col in range(W):
            r, g, b = colors[min(col // third, 2)]
            buf += bytes((r, g, b))
    return bytes(buf)


def send_frame(sock, addr, typ, frame, fid):
    for pid in range(PACKETS):
        chunk = frame[pid * PAYLOAD : (pid + 1) * PAYLOAD]
        flags = 0x0001 if pid == 0 else (0x0002 if pid == PACKETS - 1 else 0)
        header = struct.pack(
            HEADER_FMT, b"OV56", 1, typ, flags, fid, pid, PACKETS,
            len(chunk), W, H, W * 3, 0, zlib.crc32(frame) & 0xFFFFFFFF,
        )
        sock.sendto(header + chunk, addr)


def probe(img, label):
    """Sample the center pixel of each vertical third."""
    got = []
    for i in range(3):
        got.append(img.getpixel(((W // 3) * i + 50, H // 2)))
    print(f"  decoded thirds for {label}:")
    for name, rgb in TRUE_COLORS.items():
        print(f"    expect {name}")
    print(f"    actual: {got}")
    return got


def wait_frame(q, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            return q.get_nowait()
        except queue.Empty:
            time.sleep(0.05)
    return (None, None, None)


def main():
    port = 5557
    q = queue.Queue()
    rx = Receiver(port, q)
    rx.start()
    time.sleep(0.3)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # --- test 1: camera frame, DDR byte order [B,G,R] ---
    colors = list(TRUE_COLORS.values())
    cam = build_camera_frame_bgr(colors)
    send_frame(sock, ("127.0.0.1", port), 0x01, cam, fid=100)
    frame, src, raw_mode = wait_frame(q)
    assert frame is not None, "camera frame not reassembled"
    print(f"[test1] camera frame reassembled from {src}, receiver raw_mode={raw_mode}")
    assert raw_mode == "BGR", f"expected BGR raw mode, got {raw_mode}"
    img = Image.frombytes("RGB", (W, H), frame, "raw", raw_mode)
    got = probe(img, "fixed decoder")
    old = Image.frombytes("RGB", (W, H), frame)  # pre-fix behavior
    print("[test1] pre-fix decoder would show (documented 'before'):")
    print(f"    {list(old.getdata())[W//2 :: W].__len__() and [old.getpixel((W//2, H//2)), old.getpixel((W//3*2+50, H//2))]}")
    for i, (name, rgb) in enumerate(TRUE_COLORS.items()):
        assert got[i] == rgb, f"FAIL {name}: got {got[i]}"
    print("[test1] PASS: camera BGR bytes decoded to true colors")

    # --- test 2: pattern frame, software [R,G,B] ---
    pat_colors = [(255, 255, 0), (0, 255, 0), (255, 0, 255)]
    pat = build_pattern_frame_rgb(pat_colors)
    send_frame(sock, ("127.0.0.1", port), 0x02, pat, fid=101)
    frame, src, raw_mode = wait_frame(q)
    assert frame is not None, "pattern frame not reassembled"
    print(f"[test2] pattern frame reassembled, receiver raw_mode={raw_mode}")
    assert raw_mode == "RGB", f"expected RGB raw mode, got {raw_mode}"
    img = Image.frombytes("RGB", (W, H), frame, "raw", raw_mode)
    got = [img.getpixel(((W // 3) * i + 50, H // 2)) for i in range(3)]
    print(f"    actual: {got}")
    for i, c in enumerate(pat_colors):
        assert got[i] == c, f"FAIL pattern bar {i}: got {got[i]}"
    print("[test2] PASS: pattern RGB bars unchanged")

    rx.stop()
    sock.close()
    time.sleep(0.2)
    print("ALL_COLOR_SWAP_FIX_TESTS_PASS")


if __name__ == "__main__":
    main()
