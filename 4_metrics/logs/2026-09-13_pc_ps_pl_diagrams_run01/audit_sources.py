from pathlib import Path
import json, hashlib, re, sys, xml.etree.ElementTree as ET
ROOT=Path('E:/competition'); RUN=Path(__file__).resolve().parent
P=ROOT/'9_pynq/overlays/action_v1_20260913'
sys.path.insert(0,str(P))
from action_hardware_contract import validate_action_hardware_contract
hwh=P/'display_test_axi_action_uart.hwh'
tree=ET.parse(hwh).getroot()
modules=[]
for m in tree.iter('MODULE'):
    modules.append(dict(instance=m.get('INSTANCE'), type=m.get('MODTYPE'),
        buses=[dict(b.attrib, connections=[c.attrib for c in b.findall('./CONNECTIONS/CONNECTION')]) for b in m.findall('./BUSINTERFACES/BUSINTERFACE')],
        timing=[p.attrib for p in m.findall('./PORTS/PORT') if re.search('clk|clock|reset|locked|irq|intr',p.get('NAME',''),re.I)]))
files=[hwh,P/'release_manifest.json']+list(P.glob('*.py'))+[P/'mmio_ordered.c']
for sub in ['3_host/model_env','3_host/udp_video','3_host/pynq/pl_reloader','2_fpga/2_axi_lite_test/rtl','2_fpga/0_diaplay_test/rtl']:
    files += list((ROOT/sub).rglob('*.v')) if 'rtl' in sub else list((ROOT/sub).glob('*.py'))
files += [ROOT/'1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md',ROOT/'1_docs/doc/amd_dual_model_arm_design_2026-09-12.md']
files += list((ROOT/'4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run01').glob('REPORT.md'))+list((ROOT/'4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run02').glob('REPORT.md'))
ref=Path('E:/post_student/2_doc/12_PC_PS_PL完整框图_参考硬件组PPT_20260913')
files+=list(ref.iterdir())
snapshot=[dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(set(files)) if p.is_file()]
(RUN/'source_manifest.json').write_text(json.dumps(snapshot,ensure_ascii=False,indent=2),encoding='utf-8')
result=dict(contract=validate_action_hardware_contract(hwh),modules=modules,
    external=[p.attrib for p in tree.findall('./EXTERNALPORTS/PORT')],
    addresses=[p.attrib for p in tree.iter('MEMRANGE')])
(RUN/'hardware_inventory.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
for m in modules:
    if '/' not in m['instance']:
        print(m['instance'], m['type'])
        for b in m['buses']: print(' BUS',b)
        for p in m['timing']: print(' TIMING',{k:v for k,v in p.items() if k in ['NAME','SIGNAME','CLKFREQUENCY','DIR']})
print('ADDRESSES',result['addresses'])
print('CONTRACT',result['contract'])
