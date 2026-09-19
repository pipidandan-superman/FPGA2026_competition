import sys
import time
import json
import queue
from pathlib import Path
sys.path.insert(0, 'E:/competition/3_host/udp_video')
from validated_receiver import Receiver, Reassembler, HEADER
class SynchronizedReassembler(Reassembler):
    def __init__(self):
        super().__init__()
        self.synced = False
    def feed(self, packet, now):
        if not self.synced:
            if len(packet) == HEADER.size + 1440 and HEADER.unpack_from(packet)[5] == 0:
                self.synced = True
            else:
                self.stats['startup_packets_discarded'] += 1
                return None
        return super().feed(packet, now)
path = Path(__file__).with_name(sys.argv[1] + '.json')
if path.exists():
    raise RuntimeError('Evidence exists')
rx = Receiver()
rx.parser = SynchronizedReassembler()
rx.start()
rx.ready.wait(3)
crcs = set()
ids = []
start = time.monotonic()
while not rx.error and time.monotonic() - start < 12:
    try:
        frame = rx.frames.get(timeout=.5)
        crcs.add(frame.crc)
        ids.append(frame.fid)
    except queue.Empty:
        pass
rx.stop()
result = dict(seconds=time.monotonic()-start, stats=dict(rx.parser.stats),
              error=rx.error, unique_crc=len(crcs), first_id=ids[0] if ids else None,
              last_id=ids[-1] if ids else None, hdmi='USER_CONFIRMATION_REQUIRED')
result['pass'] = (not rx.error and len(ids) >= 20 and len(crcs)>1 and
                  all(rx.parser.stats[k] == 0 for k in ('bad_header','bad_packet','crc_error','lost_frames','inconsistent_header','incomplete_frames')))
path.write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
sys.exit(0 if result['pass'] else 1)
