#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ************************************************************************
# * File Name       : udp_video_gui.py
# * Developer       : LSL
# * Date            : 2026-09-08
# * Project Name    : AMD embodied sorting / EES-331 XC7Z020
# * Module Name     : udp_video GUI receiver (PC side, packaged as exe)
# * Description     : 《OV5640_UDP视频传输数据格式与上位机设计》§6 的图形
# *                   界面接收端：启动即显示等待界面；按 32B 帧头协议解析、
# *                   frame_id 组包、packet_count/EOF/CRC32 校验；显示最新
# *                   完整帧并在状态栏实时给出帧数/帧率/丢帧/CRC 等指标。
# * Dependencies    : Pillow（打包 exe 由 PyInstaller 完成）
# * Usage           : 双击 EES331_UDP_Viewer.exe，或 python udp_video_gui.py
# * Revision History:
# *   - V1.0 (2026-09-08) by LSL : Initial release (Tkinter + Pillow).
# *   - V1.1 (2026-09-08) by LSL : Fix placeholder PhotoImage being garbage
# *     collected (video area collapsed); auto-start listening on launch.
# *   - V1.2 (2026-09-08) by LSL : Fix R/B channel swap on camera frames.
# *     VDMA S2MM packs the 24-bit AXIS word {R[23:16],G[15:8],B[7:0]}
# *     little-endian, so DDR/UDP camera payload bytes per pixel are
# *     [B,G,R]; type 0x02 pattern frames are software-packed [R,G,B].
# *     Decode is now type-aware: 0x01 -> Pillow raw mode "BGR", else "RGB".
# ************************************************************************
import queue
import socket
import struct
import threading
import time
import zlib
from collections import Counter

import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageDraw, ImageTk

MAGIC = b"OV56"
VERSION = 1
HEADER_FMT = ">4sBBH I HHHHHH II"
HEADER_LEN = struct.calcsize(HEADER_FMT)  # 32
FRAME_BYTES = 921600
SLOT_KEEP = 3
WIDTH, HEIGHT = 640, 480
SHOW_W, SHOW_H = 960, 720
DEFAULT_PORT = 5000

stats = Counter()  # pkts/ok_frames/lost_frames/crc_err/dup/bad_header/short/bad_geom


class Receiver(threading.Thread):
    """后台收包线程：只碰网络、组包缓冲与计数器，不碰任何控件。"""

    def __init__(self, port, frames_q):
        super().__init__(daemon=True)
        self.port = port
        self.frames_q = frames_q
        self.slots = {}
        self.last_complete_fid = -1
        self.last_raw_mode = "RGB"  # camera payload (type 0x01) is VDMA-packed [B,G,R]
        self.alive = threading.Event()
        self.status = "未启动"

    def run(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
            sock.bind(("0.0.0.0", self.port))
            sock.settimeout(0.5)
        except OSError as exc:
            self.status = f"绑定失败：{exc}"
            return
        self.status = "监听中，等待数据…"
        self.alive.set()
        while self.alive.is_set():
            try:
                pkt, addr = sock.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break
            stats["pkts"] += 1
            self.status = f" receiving from {addr[0]}:{addr[1]}"
            frame = self.feed(pkt)
            if frame is not None:
                # 只保留最新完整帧（显示策略：latest-wins）
                try:
                    while True:
                        self.frames_q.get_nowait()
                except queue.Empty:
                    pass
                self.frames_q.put((frame, addr[0], self.last_raw_mode))
        sock.close()
        self.status = "已停止"

    def feed(self, pkt):
        if len(pkt) < HEADER_LEN:
            stats["short"] += 1
            return None
        magic, ver, typ, flags, fid, pid, count, plen, w, h, stride, ts, crc = struct.unpack(
            HEADER_FMT, pkt[:HEADER_LEN]
        )
        if magic != MAGIC or ver != VERSION or len(pkt) != HEADER_LEN + plen:
            stats["bad_header"] += 1
            return None
        # type 0x01 = camera frames copied verbatim from the VDMA-packed DDR
        # framebuffer -> per-pixel byte order [B,G,R]; type 0x02 pattern and
        # any future software-packed types stay [R,G,B].
        self.last_raw_mode = "BGR" if typ == 0x01 else "RGB"
        slot = self.slots.get(fid)
        if slot is None:
            if count != 640 or w != 640 or h != 480:
                stats["bad_geom"] += 1
                return None
            slot = {"buf": bytearray(FRAME_BYTES), "pids": set(), "count": count, "crc": crc}
            self.slots[fid] = slot
            for old in [f for f in self.slots if f < fid - (SLOT_KEEP - 1)]:
                del self.slots[old]
        if pid in slot["pids"]:
            stats["dup"] += 1
            return None
        offset = pid * plen
        slot["buf"][offset : offset + plen] = pkt[HEADER_LEN:]
        slot["pids"].add(pid)
        if (flags & 0x0002) and len(slot["pids"]) == slot["count"]:
            frame = bytes(slot["buf"])
            del self.slots[fid]
            if (zlib.crc32(frame) & 0xFFFFFFFF) != slot["crc"]:
                stats["crc_err"] += 1
                return None
            gap = 0
            if self.last_complete_fid >= 0:
                gap = fid - self.last_complete_fid - 1
                if gap > 0:
                    stats["lost_frames"] += gap
            self.last_complete_fid = fid
            stats["ok_frames"] += 1
            return frame
        return None

    def stop(self):
        self.alive.clear()


class App:
    def __init__(self, root):
        self.root = root
        root.title("EES-331 UDP 视频接收  |  AMD 具身智能分拣")
        root.resizable(False, False)
        # 注意：self.photo 必须先于占位图存在，且此后不可置 None，
        # 否则 ImageTk.PhotoImage 被垃圾回收后视频区会塌陷成空白。
        self.photo = None

        top = ttk.Frame(root, padding=6)
        top.pack(fill="x")
        ttk.Label(top, text="UDP 端口").pack(side="left")
        self.port_var = tk.StringVar(value=str(DEFAULT_PORT))
        ttk.Entry(top, width=8, textvariable=self.port_var).pack(side="left", padx=4)
        self.start_btn = ttk.Button(top, text="启动监听", command=self.start)
        self.start_btn.pack(side="left", padx=4)
        ttk.Label(top, text="（板卡→本机，默认端口 5000）").pack(side="left")

        self.frame_label = ttk.Label(root)
        self.frame_label.pack(padx=8, pady=4)
        self.show_placeholder("等待 UDP 数据…")

        info = ttk.Frame(root, padding=(8, 2, 8, 8))
        info.pack(fill="x")
        self.vars = {}
        for name, key in [
            ("状态", "status"), ("数据源", "src"), ("完整帧", "ok"),
            ("帧率 fps", "fps"), ("丢帧", "lost"), ("CRC 错", "crc"),
            ("重复/坏头", "other"),
        ]:
            box = ttk.LabelFrame(info, text=name, padding=(6, 2))
            var = tk.StringVar(value="-")
            ttk.Label(box, textvariable=var, width=14, anchor="center").pack()
            box.pack(side="left", padx=4)
            self.vars[key] = var

        self.q = queue.Queue()
        self.receiver = None
        self.last_ok = 0
        self.last_t = time.time()
        self.start_t = time.time()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.poll()
        self.start()  # 启动即自动监听默认端口，减少一步手工操作

    def show_placeholder(self, text):
        img = Image.new("RGB", (SHOW_W, SHOW_H), (24, 24, 24))
        draw = ImageDraw.Draw(img)
        draw.text((SHOW_W // 2 - 120, SHOW_H // 2 - 10), text, fill=(200, 200, 200))
        self.photo = ImageTk.PhotoImage(img)
        self.frame_label.config(image=self.photo)

    def start(self):
        if self.receiver is not None:
            self.receiver.stop()
            self.receiver = None
        for key in stats:
            stats[key] = 0
        self.last_ok = 0
        self.last_t = time.time()
        self.start_t = time.time()
        try:
            port = int(self.port_var.get())
        except ValueError:
            self.vars["status"].set("端口无效")
            return
        self.receiver = Receiver(port, self.q)
        self.receiver.start()
        self.start_btn.state(["disabled"])
        self.root.after(800, lambda: self.start_btn.state(["!disabled"]))

    def render(self, frame, src, raw_mode="RGB"):
        img = Image.frombytes("RGB", (WIDTH, HEIGHT), frame, "raw", raw_mode).resize(
            (SHOW_W, SHOW_H), Image.NEAREST
        )
        self.photo = ImageTk.PhotoImage(img)
        self.frame_label.config(image=self.photo)
        self.vars["src"].set(src)

    def poll(self):
        try:
            frame, src, raw_mode = self.q.get_nowait()
            self.render(frame, src, raw_mode)
        except queue.Empty:
            pass
        now = time.time()
        # 累计均值帧率：对低帧率流（如 1 fps）也保持读数稳定
        if now - self.last_t >= 0.5:
            ok = stats["ok_frames"]
            elapsed = now - self.start_t
            fps = ok / elapsed if elapsed > 0 else 0.0
            self.vars["status"].set(self.receiver.status if self.receiver else "未启动")
            self.vars["ok"].set(str(ok))
            self.vars["fps"].set(f"{fps:.2f}")
            self.vars["lost"].set(str(stats["lost_frames"]))
            self.vars["crc"].set(str(stats["crc_err"]))
            self.vars["other"].set(f"{stats['dup']}/{stats['bad_header']}")
            self.last_ok = ok
            self.last_t = now
        self.root.after(30, self.poll)

    def close(self):
        if self.receiver is not None:
            self.receiver.stop()
        self.root.destroy()


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
