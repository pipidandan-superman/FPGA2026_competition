"""Bounded OV56 receiver for frame validation and latest-frame inference."""
from collections import Counter
from dataclasses import dataclass
import queue
import socket
import struct
import threading
import time
import zlib

HEADER = struct.Struct('>4sBBHIHHHHHHII')
FRAME_BYTES = 640*480*3


@dataclass
class Frame:
    fid: int
    timestamp: int
    crc: int
    received_at: float
    data: bytes


class Reassembler:
    def __init__(self):
        self.stats = Counter()
        self.slots = {}
        self.last_fid = None

    def expire(self, now):
        for fid in list(self.slots):
            if now-self.slots[fid]['time'] > 1.0:
                del self.slots[fid]
                self.stats['incomplete_frames'] += 1

    def feed(self, packet, now):
        self.stats['packets'] += 1
        self.expire(now)
        if len(packet) != HEADER.size+1440:
            self.stats['bad_packet'] += 1
            return None
        magic,ver,typ,flags,fid,pid,count,plen,w,h,stride,ts,crc = HEADER.unpack_from(packet)
        if (magic,ver,typ,count,plen,w,h,stride) != (b'OV56',1,1,640,1440,640,480,1920):
            self.stats['bad_header'] += 1
            return None
        if pid >= 640 or flags != ((1 if pid==0 else 0)|(2 if pid==639 else 0)):
            self.stats['bad_header'] += 1
            return None
        if self.last_fid is not None and ((fid-self.last_fid)&0xffffffff) >= 0x80000000:
            self.stats['late_packet'] += 1
            return None
        if fid == self.last_fid:
            self.stats['late_packet'] += 1
            return None
        slot=self.slots.get(fid)
        if slot is None:
            if len(self.slots)>=3:
                oldest=min(self.slots,key=lambda x:self.slots[x]['time'])
                del self.slots[oldest]
                self.stats['incomplete_frames'] += 1
            slot=dict(buf=bytearray(FRAME_BYTES),pids=set(),ts=ts,crc=crc,time=now)
            self.slots[fid]=slot
        if (slot['ts'],slot['crc']) != (ts,crc):
            self.stats['inconsistent_header'] += 1
            return None
        if pid in slot['pids']:
            self.stats['duplicate_packet'] += 1
            return None
        slot['buf'][pid*1440:(pid+1)*1440]=packet[HEADER.size:]
        slot['pids'].add(pid)
        # EOF may arrive first. All 640 unique packets suffice regardless of order.
        if len(slot['pids']) != 640:
            return None
        del self.slots[fid]
        raw=bytes(slot['buf'])
        if zlib.crc32(raw)&0xffffffff != crc:
            self.stats['crc_error'] += 1
            return None
        if self.last_fid is not None:
            gap=((fid-self.last_fid)&0xffffffff)-1
            self.stats['lost_frames'] += gap
        self.last_fid=fid
        self.stats['complete_frames'] += 1
        return Frame(fid,ts,crc,now,raw)


class Receiver(threading.Thread):
    def __init__(self, port=5000, source='192.168.240.10', on_frame=None):
        super().__init__(daemon=True)
        self.port,self.source,self.on_frame=port,source,on_frame
        self.parser=Reassembler()
        self.frames=queue.Queue(maxsize=1)
        self.stop_event=threading.Event()
        self.ready=threading.Event()
        self.error=None

    def run(self):
        try:
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
                sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4<<20)
                sock.bind(('0.0.0.0',self.port))
                self.bound_address=sock.getsockname()
                sock.settimeout(.2)
                self.ready.set()
                while not self.stop_event.is_set():
                    try:
                        packet,addr=sock.recvfrom(2048)
                    except socket.timeout:
                        self.parser.expire(time.monotonic())
                        continue
                    if addr[0]!=self.source:
                        self.parser.stats['other_source_packets']+=1
                        continue
                    frame=self.parser.feed(packet,time.monotonic())
                    if frame:
                        if self.on_frame:
                            self.on_frame(frame)
                        try:
                            self.frames.put_nowait(frame)
                        except queue.Full:
                            try:
                                self.frames.get_nowait()
                                self.parser.stats['consumer_skipped_frames']+=1
                            except queue.Empty:
                                pass
                            self.frames.put_nowait(frame)
        except Exception as exc:
            self.error=repr(exc)
            self.ready.set()

    def stop(self):
        self.stop_event.set()
        self.join(timeout=2)
