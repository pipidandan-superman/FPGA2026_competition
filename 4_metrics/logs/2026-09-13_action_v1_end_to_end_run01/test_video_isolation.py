import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
MAIN = ROOT.parents[2] / '9_pynq/overlays/action_v1_20260913/camera_action_v1.py'

class Tests(unittest.TestCase):
    def run_case(self, failure):
        captured = []
        video = types.ModuleType('camera')
        video.stopping = False
        video.request_stop = lambda *a: None
        video.datagrams = lambda *a: []
        class Camera:
            def __init__(self, *a):
                self.mmio = object()
                self.overlay = object()
                if failure == 'camera_init':
                    raise RuntimeError('init')
            def start(self):
                captured.append('video_start')
            def status(self):
                return {}
            def snapshot(self):
                captured.append('frame')
                return bytes([len(captured)%256])
            def close(self):
                captured.append('video_close')
        video.Camera = Camera
        class Service:
            def __init__(self, *a):
                if failure == 'action_init':
                    raise RuntimeError('action_init')
                self.driver = self
                self.error = 'worker failure' if failure == 'worker' else None
            def start(self):
                if failure == 'action_start':
                    raise RuntimeError('action_start')
            def status(self):
                if failure == 'action_status':
                    raise RuntimeError('action_status')
                return {}
            def close(self):
                captured.append('action_close')
        modules = dict(camera=video, fcntl=types.SimpleNamespace(flock=lambda *a:None, LOCK_EX=1, LOCK_NB=2),
            action_hardware_contract=types.SimpleNamespace(validate_action_hardware_contract=lambda *a:None),
            action_driver=types.SimpleNamespace(ActionDriver=types.SimpleNamespace(from_overlay=lambda *a:object())),
            action_service=types.SimpleNamespace(ActionService=Service))
        spec = importlib.util.spec_from_file_location('isolated_app', MAIN)
        app = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, modules):
            spec.loader.exec_module(app)
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            temp = Path(tmp)
            bit = temp/'test.bit'
            bit.write_bytes(b'test')
            bit.with_suffix('.hwh').write_bytes(b'test')
            manifest = temp/'manifest.json'
            manifest.write_text(json.dumps(dict(marker='ACTION_V1_RELEASE_PASS',files={n:dict(sha256=hashlib.sha256(b'test').hexdigest()) for n in ['test.bit','test.hwh']})))
            real_open = open
            def local_open(name, *a, **kw):
                if str(name).startswith('/run/lock/'):
                    name = temp/Path(name).name
                return real_open(name,*a,**kw)
            ticks=[0]
            def clock():
                ticks[0] += .01
                return ticks[0]
            argv=['test','--bit',str(bit),'--manifest',str(manifest),'--evidence',str(temp/'out'),'--seconds','1']
            with patch.object(sys,'argv',argv), patch.object(app.os,'geteuid',return_value=0,create=True), patch.object(app.signal,'signal'), patch.object(app.time,'monotonic',side_effect=clock), patch.object(app.time,'sleep'), patch.object(app.socket,'socket'), patch('builtins.open',side_effect=local_open), patch('builtins.print'):
                code=app.main()
            result=json.loads((temp/'out/result.json').read_text())
            if failure == 'camera_init':
                self.assertEqual(result['state'],'FAIL')
            else:
                self.assertGreater(captured.count('frame'),1)
                self.assertEqual(result['state'], 'COMPLETE' if failure is None else 'DEGRADED')
                self.assertEqual(code,0 if failure is None else 1)
                self.assertLess(captured.index('video_start'),captured.index('frame'))
            self.assertEqual(captured[-1],'video_close')
    def test_normal(self): self.run_case(None)
    def test_action_init(self): self.run_case('action_init')
    def test_action_start(self): self.run_case('action_start')
    def test_worker(self): self.run_case('worker')
    def test_final_status(self): self.run_case('action_status')
    def test_partial_camera_cleanup(self): self.run_case('camera_init')

if __name__=='__main__': unittest.main(verbosity=2)
