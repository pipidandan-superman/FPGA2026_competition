"""Analytical sizing from the locked model audit, not a hardware benchmark."""
import csv
import hashlib
import json
from pathlib import Path

run=Path(__file__).resolve().parent
p=json.loads((run/'profile.json').read_text(encoding='utf-8'))
assert p['result']=='MODEL_STATIC_PROFILE_PASS'
records=[]
for size,entry in p['profiles'].items():
    work=entry['network_conv_macs']
    traffic=entry['naive_conv_input_output_int8_bytes']+entry['conv_weight_elements']
    for lanes in (64,128):
        for mhz in (100,150):
            for efficiency in (0.4,0.6,0.8):
                ideal=work/(lanes*mhz*1e6)
                for bandwidth in (100,250,500):
                    compute=ideal/efficiency
                    memory=traffic/(bandwidth*1e6)
                    records.append({'size':int(size),'mac_lanes':lanes,'clock_mhz':mhz,
                        'compute_efficiency_assumed':efficiency,'ddr_MBps_assumed':bandwidth,
                        'conv_ideal_ms':ideal*1000,'conv_efficiency_ms':compute*1000,
                        'reference_traffic_MB':traffic/1e6,'reference_memory_ms':memory*1000,
                        'perfect_overlap_reference_ms':max(compute,memory)*1000,
                        'no_overlap_reference_ms':(compute+memory)*1000})
with (run/'throughput_sensitivity.csv').open('w',newline='',encoding='utf-8-sig') as f:
    w=csv.DictWriter(f,fieldnames=list(records[0])); w.writeheader();w.writerows(records)
base={'LUT':5093,'FF':7850,'BRAM36':20.5,'DSP':9}
limits={'LUT':53200,'FF':106400,'BRAM36':140,'DSP':220}
budgets={'LUT':[18000,28000],'FF':[14000,24000],'BRAM36':[72,88],'DSP':[136,152]}
resources={k:{'device':limits[k],'baseline':base[k],'new_design_budget':v,
               'integrated_budget':[base[k]+v[0],base[k]+v[1]],
               'integrated_percent':[100*(base[k]+v[0])/limits[k],100*(base[k]+v[1])/limits[k]]}
           for k,v in budgets.items()}
summary={'status':'ANALYTICAL_BUDGET_ONLY','resources':resources,
         'interpretation':'Efficiency is compute delivery only; traffic is naive conv input/output plus one weight read, excludes nonconv and tile reloads. max and sum are illustrative overlap cases, not bounds on actual inference. PS, preprocessing and scheduling not included.',
         'reference_cases':[r for r in records if r['mac_lanes']==128 and r['clock_mhz']==100 and r['ddr_MBps_assumed']==250],
         'head_conv_share':{},'baseline_evidence':[]}
for size,entry in p['profiles'].items():
    head=sum(r['macs'] for r in entry['conv_rows'] if r['name'].startswith('model.22.') and not r['is_dfl'])
    summary['head_conv_share'][size]={'macs':head,'fraction':head/entry['network_conv_macs']}
root=Path('E:/competition')
for rel in ['4_metrics/logs/2026-09-13_action_v1_main_build_run03/utilization.rpt',
            '2_fpga/0_diaplay_test/release/action_v1_uart_run02/release_manifest.json']:
    path=root/rel
    summary['baseline_evidence'].append({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
summary['script_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
(run/'resource_estimate.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
