#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ************************************************************************
# * File Name       : mock_sender.py
# * Developer       : LSL
# * Date            : 2026-09-08
# * Project Name    : AMD embodied sorting / EES-331 XC7Z020
# * Module Name     : udp_video mock sender (PC side)
# * Description     : 按《OV5640_UDP视频传输数据格式与上位机设计》§4 的
# *                   32 字节帧头格式，向目标地址发送合成图案帧（5 竖彩条
# *                   + 移动竖列），用于在没有板卡的情况下验收上位机
# *                   udp_video_rx.py 的解析/组包/CRC/显示逻辑。
# * Dependencies    : numpy（pip install numpy）
# * Usage           : python mock_sender.py --ip 127.0.0.1 --fps 30
# * Revision History:
# *   - V1.0 (2026-09-08) by LSL : Initial release.
# ************************************************************************
import argparse
import socket
import struct
import time
import zlib

import numpy as np

MAGIC = b"OV56"
VERSION = 1
TYPE_TEST_PATTERN = 2
FLAG_SOF = 0x0001
FLAG_EOF = 0x0002

WIDTH, HEIGHT = 640, 480
STRIDE = WIDTH * 3
PAYLOAD = 1440
PACKET_COUNT = WIDTH * HEIGHT * 3 // PAYLOAD  # 640
HEADER_FMT = ">4sBBH I HHHHHH II"
HEADER_LEN = struct.calcsize(HEADER_FMT)  # 32


def build_frame(frame_id: int) -> np.ndarray:
    """5 竖彩条（白/黄/青/绿/品红，同 HDMI 彩条测试传统）+ 随帧移动的白色竖列。"""
    colors = np.array(
        [[255, 255, 255], [255, 255, 0], [0, 255, 0], [0, 255, 255], [255, 0, 255]],
        dtype=np.uint8,
    )
    bar_index = np.arange(WIDTH) // (WIDTH // len(colors))
    img = colors[bar_index]
    img = np.broadcast_to(img, (HEIGHT, WIDTH, 3)).copy()

    moving_x = (frame_id * 16) % WIDTH
    img[:, moving_x : moving_x + 8] = (255, 0, 0)  # 红色移动列（RGB）：肉眼可验帧推进
    return img


def packetize(frame: np.ndarray, frame_id: int, ts_us: int, target: socket):
    raw = frame.tobytes()
    crc = zlib.crc32(raw) & 0xFFFFFFFF
    for pid in range(PACKET_COUNT):
        payload = raw[pid * PAYLOAD : (pid + 1) * PAYLOAD]
        flags = 0
        if pid == 0:
            flags |= FLAG_SOF
        if pid == PACKET_COUNT - 1:
            flags |= FLAG_EOF
        header = struct.pack(
            HEADER_FMT,
            MAGIC,
            VERSION,
            TYPE_TEST_PATTERN,
            flags,
            frame_id & 0xFFFFFFFF,
            pid,
            PACKET_COUNT,
            len(payload),
            WIDTH,
            HEIGHT,
            STRIDE,
            ts_us & 0xFFFFFFFF,
            crc,
        )
        target.sendto(header + payload, (args.ip, args.port))


def main():
    global args
    parser = argparse.ArgumentParser(description="EES-331 UDP 视频协议模拟发送器")
    parser.add_argument("--ip", default="127.0.0.1", help="目的 IP（板卡为 192.168.240.10）")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--fps", type=int, default=30)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    interval = 1.0 / args.fps
    frame_id = 0
    print(f"mock_sender -> {args.ip}:{args.port} @ {args.fps} fps, {PACKET_COUNT} pkt/frame")

    while True:
        start = time.perf_counter()
        frame = build_frame(frame_id)
        packetize(frame, frame_id, int(start * 1e6) & 0xFFFFFFFF, sock)
        frame_id += 1
        elapsed = time.perf_counter() - start
        delay = interval - elapsed
        if delay > 0:
            time.sleep(delay)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("bye")
