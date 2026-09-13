"""PC inference -> UDP -> PS AXI control. COM4 is receive-only evidence."""
from pathlib import Path
import queue
import socket
import sys
import threading
import time
from stable_action import StableAction

if not getattr(sys, "frozen", False):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] /
                           "2_fpga/2_axi_lite_test/pynq"))
from action_protocol import command, decode_reply, OK, DUPLICATE, QUERY


class ActionClient:
    def __init__(self, host="192.168.240.10", port=5001, timeout=1.0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.connect((host, port))
        self.sock.settimeout(timeout)
        self.seq = None
        self.failed = False
        self.timeout = timeout

    def synchronize(self):
        self.sock.send(command(0, 0, query=True))
        state = decode_reply(self.sock.recv(2048))
        if state["status"] != QUERY or state["seq"] != state["done_seq"]:
            raise RuntimeError("PS action service not idle/synchronized")
        self.seq = state["seq"]
        return state

    def execute(self, action):
        if self.failed or self.seq is None or self.seq == 0xFFFFFFFF:
            raise RuntimeError("Client requires idle session synchronization")
        self.seq += 1
        self.failed = True
        started = time.monotonic()
        self.sock.send(command(self.seq, action))
        deadline = started + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("PS completion timeout; command is uncertain")
            self.sock.settimeout(remaining)
            observed = decode_reply(self.sock.recv(2048))
            if observed["seq"] != self.seq:
                continue  # A delayed prior response cannot complete this command.
            if (observed["status"] not in (OK, DUPLICATE) or
                    observed["action"] != action or observed["done_seq"] != self.seq):
                raise RuntimeError("PS completion mismatch: " + repr(observed))
            self.failed = False
            self.sock.settimeout(self.timeout)
            return dict(**observed, elapsed_ms=(time.monotonic()-started)*1000)

    def close(self):
        self.sock.close()


class ActionPublisher:
    def __init__(self, emit, host="192.168.240.10", port=5001):
        self.emit = emit
        self.host, self.port = host, port
        self.gate = StableAction()
        self.lock = threading.Lock()
        self.events = queue.Queue(maxsize=8)
        self.stop = threading.Event()
        self.error = None
        self.ready = False
        self.last_result = None
        self.thread = threading.Thread(target=self.run, name="action-publisher", daemon=True)
        self.thread.start()

    def enqueue(self, event):
        if event is None or self.error or self.stop.is_set():
            return
        try:
            self.events.put_nowait(event)
        except queue.Full:
            self.error = "Action queue overflow"
            self.emit("ACTION_LINK_FAILED", error=self.error)

    def feed(self, row):
        if not self.ready or self.error:
            return
        with self.lock:
            self.enqueue(self.gate.feed(row["fid"], row["arrival"], time.monotonic(),
                                       row["detections"]))

    def reset_frames(self):
        # A video receiver restart invalidates frame identity and streak.
        # Preserve the published action so timeout CLEAR can still be sent.
        with self.lock:
            self.gate.last_fid = None
            self.gate.last_arrival = float("-inf")
            self.gate.candidate, self.gate.streak = None, 0

    def run(self):
        client = None
        try:
            client = ActionClient(self.host, self.port)
            state = client.synchronize()
            # Establish a known all-off starting action using the normal AXI path.
            self.last_result = client.execute(0)
            self.emit("ACTION_INITIAL_CLEAR", **self.last_result)
            self.ready = True
            self.emit("ACTION_LINK_READY", prior_state=state)
            while not self.stop.is_set() and not self.error:
                with self.lock:
                    self.enqueue(self.gate.tick(time.monotonic()))
                try:
                    event = self.events.get(timeout=.02)
                except queue.Empty:
                    continue
                self.emit("ACTION_DECISION", **event)
                self.last_result = client.execute(event["action"])
                self.emit("ACTION_CONFIRMED", decision=event, **self.last_result)
            if not self.error and not client.failed:
                self.last_result = client.execute(0)
                self.emit("ACTION_CLOSE_CLEAR", **self.last_result)
        except Exception as exc:
            self.error = repr(exc)
            self.emit("ACTION_LINK_FAILED", error=self.error)
        finally:
            self.ready = False
            if client is not None:
                client.close()

    def close(self):
        self.stop.set()
        self.thread.join(3)
        if self.thread.is_alive():
            self.error = "Action publisher did not stop"
