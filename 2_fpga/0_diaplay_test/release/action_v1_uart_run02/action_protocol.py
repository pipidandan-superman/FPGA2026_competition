"""ACTL v1 wire codecs; shared by PC, PYNQ and offline verification."""
import struct
import zlib

LABELS = ("Down", "Left", "Right", "Stop", "Thumbs Down", "Thumbs up", "Up")
ACTIONS = {label: index + 1 for index, label in enumerate(LABELS)}
ALLOWED = frozenset(ACTIONS) - {"Left", "Right"}
COMMAND = struct.Struct(">4sBBBBI")
REPLY = struct.Struct(">4sBBBBII")
OK, DUPLICATE, BUSY, BAD_SEQUENCE, FAILED, QUERY = range(6)


def crc8(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return crc


def uart_frame(seq, action):
    if type(seq) is not int or not 0 < seq <= 0xFFFFFFFF:
        raise ValueError("Sequence must be nonzero uint32")
    if type(action) is not int or not 0 <= action <= 7:
        raise ValueError("Action must be 0..7")
    head = bytes((0xA5, 0x5A, seq & 255, action))
    return head + bytes((crc8(head), 13, 10))


def add_crc(data):
    return data + struct.pack(">I", zlib.crc32(data) & 0xFFFFFFFF)


def checked(data, layout):
    if len(data) != layout.size + 4:
        raise ValueError("Wrong packet length")
    if struct.unpack(">I", data[-4:])[0] != zlib.crc32(data[:-4]) & 0xFFFFFFFF:
        raise ValueError("CRC32 mismatch")
    return layout.unpack(data[:-4])


def command(seq, action, query=False):
    if query:
        if seq != 0 or action != 0:
            raise ValueError("Query must have zero seq/action")
    else:
        uart_frame(seq, action)
    return add_crc(COMMAND.pack(b"ACTN", 1, 2 if query else 1, action, 0, seq))


def decode_command(data):
    magic, version, kind, action, flags, seq = checked(data, COMMAND)
    if magic != b"ACTN" or version != 1 or flags or kind not in (1, 2):
        raise ValueError("Command header mismatch")
    command(seq, action, query=kind == 2)
    return kind, seq, action


def reply(status, seq, action, done_seq):
    return add_crc(REPLY.pack(b"ACTA", 1, status, action, 0, seq, done_seq))


def decode_reply(data):
    magic, version, status, action, reserved, seq, done = checked(data, REPLY)
    if magic != b"ACTA" or version != 1 or reserved or status not in range(6):
        raise ValueError("Reply header mismatch")
    if action > 7:
        raise ValueError("Reply action mismatch")
    return dict(status=status, seq=seq, action=action, done_seq=done)


class UartFrames:
    """Recover fixed frames across arbitrary serial/notification chunks."""
    def __init__(self):
        self.buffer = bytearray()
        self.discarded = 0
        self.errors = 0

    def feed(self, chunk):
        self.buffer.extend(chunk)
        frames = []
        while len(self.buffer) >= 7:
            raw = bytes(self.buffer[:7])
            if raw[:2] != b"\xa5\x5a":
                del self.buffer[0]
                self.discarded += 1
            elif raw[-2:] != b"\r\n" or crc8(raw[:4]) != raw[4] or raw[3] > 7:
                del self.buffer[0]
                self.errors += 1
            else:
                frames.append(raw)
                del self.buffer[:7]
        return frames
