"""Read-only independent release and real-model evidence verification."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

tree = Path(sys.argv[1]).resolve()
run = tree / '4_metrics/logs/2026-09-13_action_v1_end_to_end_run01'
release = tree / '9_pynq/overlays/action_v1_20260913'
manifest = json.loads((release / 'release_manifest.json').read_text(encoding='utf-8'))
for name, expected in manifest['files'].items():
    data = (release / name).read_bytes()
    assert len(data) == expected['bytes'], name
    assert hashlib.sha256(data).hexdigest() == expected['sha256'], name
print('RELEASE_MANIFEST_HASH_PASS', len(manifest['files']))
sys.path.insert(0, str(tree / '2_fpga/2_axi_lite_test/pynq'))
from action_protocol import uart_frame
actions = set()
for case in ('real_model', 'real_model_up_down'):
    folder = run / case
    events = [json.loads(x) for x in (folder/'events.jsonl').read_text(encoding='utf-8').splitlines()]
    predictions = [json.loads(x) for x in (folder/'predictions.jsonl').read_text(encoding='utf-8').splitlines()]
    result = json.loads((folder/'result.json').read_text(encoding='utf-8'))
    assert result['state'] == 'PASS'
    completed = [x for x in events if x['event'] in ('ACTION_INITIAL_CLEAR', 'ACTION_CONFIRMED', 'ACTION_CLOSE_CLEAR')]
    assert (folder/'uart_capture.bin').read_bytes() == b''.join(uart_frame(x['seq'], x['action']) for x in completed)
    assert len({x['seq'] for x in completed}) == len(completed)
    for event in completed:
        decision = event.get('decision', {})
        if decision.get('reason') != 'stable':
            continue
        i = next(i for i, p in enumerate(predictions) if p['fid'] == decision['fid'])
        triple = predictions[i-2:i+1]
        assert len(triple) == 3 and len({p['fid'] for p in triple}) == 3
        for prediction in triple:
            assert {d['label'] for d in prediction['detections']} == {decision['label']}
            assert max(d['confidence'] for d in prediction['detections']) >= .75
            assert 0 <= prediction['inference_finished'] - prediction['arrival'] < 1
        actions.add(event['action'])
    print('REAL_MODEL_WIRE_THREE_FRAME_PASS', case, len(completed))
assert actions == {1, 4, 5, 6, 7}, actions
physical = json.loads((run/'physical_gui_manual.json').read_text(encoding='utf-8'))
assert set(physical['confirmed_actions']) == actions
known = run/'known_commands'
assert (known/'uart_capture.bin').read_bytes() == (known/'expected.bin').read_bytes()
assert len((known/'uart_capture.bin').read_bytes()) == 7007
print('FIVE_PHYSICAL_ACTIONS_AND_1000_COMMAND_CAPTURE_PASS')
for relative in ('4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/test_video_isolation.py', '2_fpga/2_axi_lite_test/pynq/test_action_v1.py', '3_host/model_env/test_gesture_viewer.py'):
    subprocess.run([sys.executable, '-B', str(tree/relative)], check=True)
print('DELIVERY_OFFLINE_AUDIT_PASS; hot reload remains unresolved; no board accessed')
