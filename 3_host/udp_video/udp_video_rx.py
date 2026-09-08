#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ************************************************************************
# * File Name       : udp_video_rx.py
# * Developer       : LSL
# * Date            : 2026-09-08
# * Project Name    : AMD embodied sorting / EES-331 XC7Z020
# * Module Name     : udp_video receiver v1 (PC side)
# * Description     : 《OV5640_UDP视频传输数据格式与上位机设计》§6.1 的
# *                   最小可用接收端：解析 32B 帧头、按 frame_id 组包、
# *                   packet_count/EOF/CRC32 三重完整性校验、显示最新
# *                   完整帧，并周期打印 FPS/丢帧/乱序/CRC 错误统计。
# * Dependencies    : numpy, opencv-python
# * Usage           : python udp_video_rx.py [--port 5000] [--show]
# * Revision History:
# *   - V1.0 (2026-09-08) by LSL : Initial release.
# ************************************************************************
import argparse
import socket
import struct
import time
import zlib
from collections import Counter

import cv2
import numpy as np

MAGIC = b"OV56"
HEADER_FMT = ">4sBBH I HHHHHH II"
HEADER_LEN = struct.calcsize(HEADER_FMT)  # 32
FRAME_BYTES = 640 * 480 * 3
SLOT_KEEP = 3  # 同时保有的装配槽（吸收轻度乱序）


class Reassembler:
    def __init__(self):
        self.slots = {}  # frame_id -> {"buf": bytearray, "pids": set, "count": int, "crc": int}
        self.last_complete_fid = -1

    def drop_older(self, newest):
        for fid in [f for f in self.slots if f < newest - (SLOT_KEEP - 1)]:
            del self.slots[fid]

    def feed(self, pkt):
        """输入一个 UDP 载荷；返回 'complete'(完整帧 bytes) / None。"""
        if len(pkt) < HEADER_LEN:
            stats["short"] += 1
            return None
        magic, ver, typ, flags, fid, pid, count, plen, w, h, stride, ts, crc = struct.unpack(
            HEADER_FMT, pkt[:HEADER_LEN]
        )
        if magic != MAGIC or ver != 1 or len(pkt) != HEADER_LEN + plen:
            stats["bad_header"] += 1
            return None

        payload = pkt[HEADER_LEN:]
        slot = self.slots.get(fid)
        if slot is None:
            if count != 640 or w != 640 or h != 480:
                stats["bad_geom"] += 1
                return None
            slot = {"buf": bytearray(FRAME_BYTES), "pids": set(), "count": count, "crc": crc}
            self.slots[fid] = slot
            # 检测丢帧：完整交付或过期丢弃的 frame_id 连续性由统计口径处理
        if pid in slot["pids"]:
            stats["dup"] += 1
            return None
        offset = pid * (len(payload))
        slot["buf"][offset : offset + len(payload)] = payload
        slot["pids"].add(pid)

        if (flags & 0x0002) and len(slot["pids"]) == slot["count"]:
            frame = bytes(slot["buf"])
            del self.slots[fid]
            if (zlib.crc32(frame) & 0xFFFFFFFF) != slot["crc"]:
                stats["crc_err"] += 1
                return None
            stats["ok_frames"] += 1
            self.last_complete_fid = fid
            return frame
        return None


stats = Counter()
delivered = {"fid": -1}


def on_frame(frame, fid):
    """显示策略：只显示最新完整帧。丢帧口径：相邻完整帧 id 的缺口。"""
    if delivered["fid"] >= 0:
        gap = fid - delivered["fid"] - 1
        if gap > 0:
            stats["lost_frames"] += gap
    delivered["fid"] = fid
    img = np.frombuffer(frame, dtype=np.uint8).reshape(480, 640, 3)
    # 数据为 RGB 顺序，OpenCV 显示用 BGR
    img = img[:, :, ::-1]
    show = cv2.resize(img, (960, 720), interpolation=cv2.INTER_NEAREST)
    cv2.imshow("EES-331 UDP RX", show)


def main():
    parser = argparse.ArgumentParser(description="EES-331 UDP 视频接收端 v1")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--no-show", action="store_true", help="无窗口环境只打印统计")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
    sock.bind(("0.0.0.0", args.port))
    sock.settimeout(1.0)
    print(f"listening on 0.0.0.0:{args.port} (UDP), expecting magic OV56")

    reasm = Reassembler()
    last_report = time.time()

    while True:
        try:
            pkt, addr = sock.recvfrom(2048)
        except socket.timeout:
            pkt = None
        now = time.time()
        if pkt:
            frame = reasm.feed(pkt)
            if frame is not None:
                on_frame(frame, reasm.last_complete_fid)
        if now - last_report >= 2.0:
            print(
                f"ok_frames={stats['ok_frames']} lost_frames={stats['lost_frames']} "
                f"crc_err={stats['crc_err']} dup={stats['dup']} bad_header={stats['bad_header']} "
                f"short={stats['short']} bad_geom={stats['bad_geom']}"
            )
            last_report = now
        if not args.no_show and cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cv2.destroyAllWindows()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("bye")
