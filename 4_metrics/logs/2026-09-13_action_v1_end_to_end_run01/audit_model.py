"""Audit actual predictions, network completions and wire bytes by sequence."""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parents[2]/'2_fpga/2_axi_lite_test/pynq'))
from action_protocol import uart_frame
rows=[]
for name in sys.argv[1:]:
    folder=ROOT/name
    events=[json.loads(x) for x in (folder/'events.jsonl').read_text().splitlines()]
    predictions=[json.loads(x) for x in (folder/'predictions.jsonl').read_text().splitlines()]
    result=json.loads((folder/'result.json').read_text())
    assert result['state']=='PASS',name
    confirmed=[e for e in events if e['event'] in ('ACTION_INITIAL_CLEAR','ACTION_CONFIRMED','ACTION_CLOSE_CLEAR')]
    capture = folder/'uart_capture.bin'
    if not capture.exists():
        capture = folder/'com4.bin'
    assert capture.read_bytes()==b''.join(uart_frame(e['seq'],e['action']) for e in confirmed)
    assert len({e['seq'] for e in confirmed})==len(confirmed)
    for e in confirmed:
        d=e.get('decision',{})
        if d.get('reason')!='stable': continue
        i=next(i for i,p in enumerate(predictions) if p['fid']==d['fid'])
        triple=predictions[i-2:i+1]
        assert len(triple)==3 and len({p['fid'] for p in triple})==3
        for p in triple:
            assert {x['label'] for x in p['detections']}=={d['label']}
            assert max(x['confidence'] for x in p['detections'])>=.75
            assert 0<=p['inference_finished']-p['arrival']<1
        rows.append(dict(run=name,seq=e['seq'],action=e['action'],label=d['label'],fids=[p['fid'] for p in triple],confidence=[max(x['confidence'] for x in p['detections']) for p in triple],uart_hex=uart_frame(e['seq'],e['action']).hex()))
out=dict(marker='REAL_PREDICTION_THREE_FRAME_WIRE_AUDIT_PASS',stable_actions=sorted(set(x['action'] for x in rows)),rows=rows)
with (ROOT/('model_audit_'+str(len(sys.argv)-1)+'.json')).open('x') as f: json.dump(out,f,indent=2)
print(json.dumps(out,indent=2))
