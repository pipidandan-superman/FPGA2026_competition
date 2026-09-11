"""Run the existing PC viewer unchanged, recording successful GUI renders."""
import argparse
import importlib.util
import json
from pathlib import Path
import time
import tkinter as tk
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--viewer', required=True, type=Path)
parser.add_argument('--evidence', required=True, type=Path)
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('ees331_existing_viewer', args.viewer)
viewer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(viewer)


class EvidenceApp(viewer.App):
    def __init__(self, root):
        self.render_count = 0
        self.last_saved = 0
        self.first_render = None
        self.last_stats_time = 0
        super().__init__(root)
        root.title('EES-331 PYNQ/Linux - live camera UDP')

    def render(self, frame, src, raw_mode='RGB'):
        super().render(frame, src, raw_mode)
        self.render_count += 1
        now = time.monotonic()
        if self.first_render is None:
            self.first_render = now
        if now - self.last_saved >= 5:
            img = Image.frombytes('RGB', (640, 480), frame, 'raw', raw_mode)
            img.save(args.evidence / 'pc_latest.png')
            if not (args.evidence / 'pc_first.png').exists():
                img.save(args.evidence / 'pc_first.png')
            (args.evidence / 'pc_latest.bgr').write_bytes(frame)
            record = dict(monotonic=now, source=src, renders=self.render_count,
                          seconds=now-self.first_render, raw_mode=raw_mode,
                          stats=dict(viewer.stats))
            with (args.evidence / 'pc_stats.jsonl').open('a', encoding='utf-8') as out:
                out.write(json.dumps(record) + '\n')
            (args.evidence / 'pc_status.json').write_text(json.dumps(record, indent=2))
            self.last_saved = now

    def poll(self):
        super().poll()
        now = time.monotonic()
        if self.first_render is not None and now - self.last_stats_time >= 1:
            record = dict(monotonic=now, renders=self.render_count,
                          source=self.vars['src'].get(), seconds=now-self.first_render,
                          stats={key: viewer.stats[key] for key in
                                 ('pkts', 'ok_frames', 'lost_frames', 'crc_err', 'dup', 'bad_header', 'short', 'bad_geom')})
            (args.evidence / 'pc_status.json').write_text(json.dumps(record, indent=2))
            with (args.evidence / 'pc_stats.jsonl').open('a', encoding='utf-8') as out:
                out.write(json.dumps(record) + '\n')
            self.last_stats_time = now


root = tk.Tk()
app = EvidenceApp(root)
root.mainloop()
