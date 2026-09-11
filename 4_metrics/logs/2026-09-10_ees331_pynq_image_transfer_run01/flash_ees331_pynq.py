#!/usr/bin/env python3
"""EES-331 PYNQ TF-card flasher, v5: pure-ctypes raw disk I/O.

No CRT handle wrapping (open_osfhandle proved unreliable here).
  - FSCTL_LOCK_VOLUME on the mounted volume (path form \\\\.\\Volume{guid})
  - raw WriteFile/ReadFile on \\\\.\\PHYSICALDRIVE<n>
  - step-by-step log + result file + full read-back SHA-256 verify

Usage (elevated):
  python flash_ees331_pynq.py --image <img> --disk 2 --log <log> --result <file>
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import hashlib
import os
import sys
import time

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FSCTL_LOCK_VOLUME = 0x00090018
FSCTL_DISMOUNT_VOLUME = 0x00090020
IOCTL_STORAGE_GET_DEVICE_NUMBER = 0x0002D480
CHUNK = 4 << 20

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
kernel32.CreateFileW.restype = wt.HANDLE
kernel32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, wt.LPVOID,
                                 wt.DWORD, wt.DWORD, wt.HANDLE]
for fn in ("ReadFile", "WriteFile"):
    getattr(kernel32, fn).restype = wt.BOOL
    getattr(kernel32, fn).argtypes = [wt.HANDLE, wt.LPVOID, wt.DWORD,
                                      ctypes.POINTER(wt.DWORD), wt.LPVOID]
kernel32.DeviceIoControl.restype = wt.BOOL
kernel32.DeviceIoControl.argtypes = [wt.HANDLE, wt.DWORD, wt.LPVOID, wt.DWORD,
                                     wt.LPVOID, wt.DWORD, ctypes.POINTER(wt.DWORD), wt.LPVOID]
kernel32.GetVolumeNameForVolumeMountPointW.restype = wt.BOOL
kernel32.GetVolumeNameForVolumeMountPointW.argtypes = [wt.LPCWSTR, wt.LPWSTR, wt.DWORD]
kernel32.CloseHandle.argtypes = [wt.HANDLE]
EXPECTED = "203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a"


class Ctx:
    pass


CTX = Ctx()


def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(CTX.args.log, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def finish(rc, msg):
    with open(CTX.args.result, "w", encoding="utf-8") as f:
        f.write(msg + "\n")
    log(msg)
    sys.exit(rc)


def raw_open(path, access):
    h = kernel32.CreateFileW(path, access, 3, None, OPEN_EXISTING, 0, None)
    if not h or h == wt.HANDLE(-1).value:
        raise OSError(f"CreateFileW({path}) failed: WinError {ctypes.get_last_error()}")
    return h


def read_handle(h, n):
    buf = ctypes.create_string_buffer(n)
    got = wt.DWORD(0)
    if not kernel32.ReadFile(h, buf, n, ctypes.byref(got), None):
        raise OSError(f"ReadFile failed: WinError {ctypes.get_last_error()}")
    return buf.raw[:got.value]


def write_handle(h, data):
    wrote = wt.DWORD(0)
    if not kernel32.WriteFile(h, data, len(data), ctypes.byref(wrote), None):
        raise OSError(f"WriteFile failed: WinError {ctypes.get_last_error()}")
    if wrote.value != len(data):
        raise OSError(f"short write {wrote.value}/{len(data)}")


def ioctl(h, code):
    br = wt.DWORD(0)
    return bool(kernel32.DeviceIoControl(h, code, None, 0, None, 0, ctypes.byref(br), None))


def find_volume_letter(disk_number):
    for ch in "DEFGHIJKLMNOPQRSTUVWXYZ":
        name = ctypes.create_unicode_buffer(260)
        if not kernel32.GetVolumeNameForVolumeMountPointW(ctypes.c_wchar_p(f"{ch}:\\"), name, 260):
            continue
        # '\\?\Volume{guid}\' -> '\\.\Volume{guid}'  (CreateFileW-compatible)
        guid = name.value.rstrip("\\")
        dev_path = guid.replace("\\\\?\\", "\\\\.\\", 1)
        try:
            h = raw_open(dev_path, 0)  # access 0: query device only
        except OSError as e:
            log(f"  {ch}: volume open failed ({e})")
            continue
        class SDN(ctypes.Structure):
            _fields_ = [("DeviceType", wt.DWORD), ("DeviceNumber", wt.DWORD),
                        ("PartitionNumber", wt.DWORD)]
        sdn = SDN()
        br = wt.DWORD(0)
        ok = kernel32.DeviceIoControl(h, IOCTL_STORAGE_GET_DEVICE_NUMBER, None, 0,
                                      ctypes.byref(sdn), ctypes.sizeof(sdn), ctypes.byref(br), None)
        kernel32.CloseHandle(h)
        if ok:
            log(f"  {ch}: -> PHYSICALDRIVE{sdn.DeviceNumber}")
            if sdn.DeviceNumber == disk_number:
                return ch
        else:
            log(f"  {ch}: GET_DEVICE_NUMBER failed (WinError {ctypes.get_last_error()})")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--disk", type=int, required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--result", required=True)
    CTX.args = ap.parse_args()
    with open(CTX.args.result, "w", encoding="utf-8") as f:
        f.write("RUNNING\n")

    try:
        size = os.path.getsize(CTX.args.image)
        log(f"image={CTX.args.image} size={size}")
        h_sha = hashlib.sha256()
        with open(CTX.args.image, "rb") as f:
            for chunk in iter(lambda: f.read(CHUNK), b""):
                h_sha.update(chunk)
        if h_sha.hexdigest() != EXPECTED:
            finish(1, "FAIL: image hash mismatch")
        log("image sha256 verified")

        lock_h = None
        drive = find_volume_letter(CTX.args.disk)
        if drive:
            try:
                log(f"locking volume \\\\.\\{drive}: ...")
                lock_h = raw_open(f"\\\\.\\{drive}:", GENERIC_READ | GENERIC_WRITE)
                if ioctl(lock_h, FSCTL_LOCK_VOLUME):
                    log("volume LOCKED")
                    log("volume dismounted" if ioctl(lock_h, FSCTL_DISMOUNT_VOLUME)
                        else "NOTE: dismount failed - lock still held, ok")
                else:
                    log(f"NOTE: lock failed (WinError {ctypes.get_last_error()}) - continuing")
                    kernel32.CloseHandle(lock_h)
                    lock_h = None
            except OSError as e:
                log(f"NOTE: lock path failed ({e}) - continuing")
                lock_h = None
        else:
            log("no mounted volume letter found - writing without lock")

        dpath = f"\\\\.\\PHYSICALDRIVE{CTX.args.disk}"
        log(f"opening {dpath} raw (read+write) ...")
        dh = raw_open(dpath, GENERIC_READ | GENERIC_WRITE)
        log("disk handle opened - writing raw, progress every 256 MB")
        done, nxt = 0, 256 << 20
        with open(CTX.args.image, "rb") as src:
            while done < size:
                data = src.read(CHUNK)
                if not data:
                    break
                write_handle(dh, data)
                done += len(data)
                if done >= nxt:
                    log(f"  {done / (1 << 30):.2f} / {size / (1 << 30):.2f} GB")
                    nxt += 256 << 20
        if done != size:
            finish(1, f"FAIL: short write {done}/{size}")
        log(f"WRITE_DONE {done} bytes")

        log("verifying read-back (full SHA-256) ...")
        c_sha = hashlib.sha256()
        done, nxt = 0, 1 << 30
        kernel32.SetFilePointer(dh, 0, None, 0)  # FILE_BEGIN
        while done < size:
            data = read_handle(dh, CHUNK)
            if not data:
                break
            c_sha.update(data.encode("latin-1") if isinstance(data, str) else data)
            done += len(data)
            if done >= nxt:
                log(f"  verified {done / (1 << 30):.2f} / {size / (1 << 30):.2f} GB")
                nxt += 1 << 30
        card = c_sha.hexdigest()
        log(f"card sha256={card} ({done} bytes)")
        kernel32.CloseHandle(dh)
        if card == EXPECTED and done == size:
            finish(0, "VERIFY_PASS - card ready for the board (never format it when Windows asks)")
        finish(1, f"FAIL: verify mismatch card={card} done={done}/{size}")
    except Exception as e:
        finish(1, f"FAIL: {type(e).__name__}: {e}")
    finally:
        if lock_h:
            kernel32.CloseHandle(lock_h)


if __name__ == "__main__":
    main()
