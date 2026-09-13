"""Single-owner UDP-to-AXI service, running alongside the camera."""
import socket
import threading
import time
from action_protocol import (decode_command, reply, OK, DUPLICATE, BUSY,
                             BAD_SEQUENCE, FAILED, QUERY)


class ActionService:
    def __init__(self, driver, peer, emit, bind=("0.0.0.0", 5001)):
        self.driver, self.peer, self.emit = driver, peer, emit
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.socket.bind(bind)
            self.socket.settimeout(.001)
        except Exception:
            self.socket.close()
            raise
        self.stop = threading.Event()
        self.thread = None
        self.error = None
        self.pending_address = None
        self.last_completed = None

    def start(self):
        state = self.driver.status()
        # A service restart with unknown in-flight work requires operator recovery.
        if state["status"] != 1:
            self.socket.close()
            raise RuntimeError("Action service needs idle ACTL hardware")
        self.emit("ACTION_SERVICE_READY", **state, peer=self.peer,
                  bind=self.socket.getsockname())
        self.thread = threading.Thread(target=self.run, name="action-service", daemon=True)
        self.thread.start()

    def send(self, address, status, seq, action, done_seq):
        self.socket.sendto(reply(status, seq, action, done_seq), address)

    def handle(self, raw, address):
        if address[0] != self.peer:
            self.emit("ACTION_PEER_REJECTED", address=address)
            return
        try:
            kind, seq, action = decode_command(raw)
        except ValueError as exc:
            self.emit("ACTION_PACKET_REJECTED", error=str(exc), hex=raw.hex())
            return
        state = self.driver.status()
        if kind == 2:
            status = FAILED if self.driver.failed else (BUSY if self.driver.pending else QUERY)
            self.send(address, status, state["accept_seq"], state["action"], state["done_seq"])
            return
        if self.driver.failed:
            self.send(address, FAILED, seq, action, state["done_seq"])
            return
        if self.driver.pending is not None:
            self.send(address, BUSY, seq, action, state["done_seq"])
            return
        # Hardware persists the most recent result even after ACK. This also
        # deduplicates that result across a PS service restart without a reload.
        if seq == state["done_seq"] and action == state["action"]:
            self.send(address, DUPLICATE, seq, action, state["done_seq"])
            self.emit("ACTION_DUPLICATE", seq=seq, action=action)
            return
        if seq <= state["accept_seq"]:
            self.send(address, BAD_SEQUENCE, seq, action, state["done_seq"])
            return
        self.emit("ACTION_SUBMIT", seq=seq, action=action)
        self.driver.begin(seq, action)
        self.pending_address = address

    def run(self):
        try:
            while not self.stop.is_set() or self.driver.pending is not None:
                if not self.stop.is_set():
                    try:
                        raw, address = self.socket.recvfrom(2048)
                    except socket.timeout:
                        pass
                    else:
                        self.handle(raw, address)
                else:
                    time.sleep(.001)
                completed = self.driver.poll()
                if completed is not None:
                    self.last_completed = completed
                    self.emit("ACTION_DONE", **completed)
                    self.send(self.pending_address, OK, completed["seq"],
                              completed["action"], completed["done_seq"])
                    self.pending_address = None
        except Exception as exc:
            self.error = repr(exc)
            self.driver.failed = True
            self.emit("ACTION_SERVICE_FAILED", error=self.error)

    def close(self):
        self.stop.set()
        if self.thread is not None:
            self.thread.join(2)
            if self.thread.is_alive():
                raise RuntimeError("Action service did not quiesce")
        self.socket.close()
