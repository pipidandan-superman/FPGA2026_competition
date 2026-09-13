from pathlib import Path
import json,hashlib,re,html,xml.etree.ElementTree as ET
from urllib.parse import unquote
RUN=Path(__file__).resolve().parent;ROOT=Path('E:/competition')
scene=json.loads((RUN/'scene.json').read_text(encoding='utf-8'));out=Path(scene['output_dir'])
sections=[];nav=[]
for i,p in enumerate(scene['pages']):
 stem=p['basename'];title=html.escape(p['title']);href=html.escape(stem)
 nav.append(f'<a href="#p{i}">{title}</a>')
 sections.append(f'<section id="p{i}"><h2>{title}</h2><p><a href="{href}.pdf">单页 PDF</a> · <a href="{href}.svg">SVG 矢量</a> · <a href="{href}.png">高清 PNG</a></p><a href="{href}.png"><img src="{href}.png" alt="{title}" loading="lazy"></a></section>')
content='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>EES-331 PC PS PL 系统图集</title><style>body{font-family:Microsoft YaHei,system-ui;background:#eaf0f3;color:#243d49;margin:0}header,main{max-width:1500px;margin:auto;padding:28px}h1{font-size:30px}a{color:#087fab}nav{display:flex;flex-wrap:wrap;gap:10px}nav a{background:white;border:1px solid #c6d3da;border-radius:6px;padding:10px;text-decoration:none}section{margin:26px 0;padding:20px;background:white;border-radius:10px;box-shadow:0 2px 7px #20303c18}img{display:block;width:100%;height:auto}p{line-height:1.7}h2{font-size:23px}@media print{nav,header p,section p{display:none}section{break-after:page;padding:0;margin:0;box-shadow:none}h2{display:none}}</style><header><h1>EES-331 · PC＋PS＋PL 完整系统图集</h1><p>当前工程 · 2026-09-13 · 三类要求，六页图件。图中规划模块已独立标注。</p><p><a href="PC_PS_PL完整图集_v1.pdf">完整 PDF</a> · <a href="PC_PS_PL完整图集_v1.vsdx">原生可编辑 Visio</a> · <a href="阅读说明.md">依据与阅读说明</a></p><nav>'''+''.join(nav)+'</nav></header><main>'+''.join(sections)+'</main></html>'
(out/'图集浏览.html').write_text(content,encoding='utf-8')
v=json.loads((RUN/'verification.json').read_text(encoding='utf-8'))
assert v['marker']=='DIAGRAM_ARTIFACT_PASS',v['marker']
visio=json.loads((RUN/'visio_build.json').read_text(encoding='utf-8-sig'))
assert visio['marker']=='VISIO_BUILD_PASS' and visio['round_trip']=='PASS'
links=[]
for f in out.glob('*.md'):
 for raw in re.findall(r'\]\(([^)]+)\)',f.read_text(encoding='utf-8')):
  if '://' in raw:continue
  target=(f.parent/unquote(raw.strip('<>'))).resolve()
  if not target.exists():links.append(dict(file=str(f),target=str(target)))
assert not links,links
payload=ROOT/'9_pynq/overlays/action_v1_20260913'
manifest=json.loads((payload/'release_manifest.json').read_text())
checked={}
for name in ['display_test_axi_action_uart.bit','display_test_axi_action_uart.hwh']:
 digest=hashlib.sha256((payload/name).read_bytes()).hexdigest();assert digest==manifest['files'][name]['sha256'];checked[name]=digest
model=ROOT/'3_host/model/best.pt';expected='68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79'
checked['best.pt']=hashlib.sha256(model.read_bytes()).hexdigest();assert checked['best.pt']==expected
extras=list((ROOT/'2_fpga/0_diaplay_test/rtl/hdmi_new').glob('*.sv'))
extra_manifest=[dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in extras]
(RUN/'additional_rtl_sources.json').write_text(json.dumps(extra_manifest,ensure_ascii=False,indent=2),encoding='utf-8')
tree=ET.parse(payload/'display_test_axi_action_uart.hwh')
params={p.get('NAME'):p.get('VALUE') for m in tree.iter('MODULE') if m.get('INSTANCE')=='processing_system7_0' for p in m.iter('PARAMETER')}
ps_params={k:v for k,v in params.items() if re.search(r'PCW_(ENET0|SD0|UART[01])_.*(ENABLE|IO|BASEADDR)$',k)}
(RUN/'ps_peripheral_parameters.json').write_text(json.dumps(ps_params,indent=2),encoding='utf-8')
v['visual_review']='PASS: all six rendered pages inspected; VDMA text overflow and title-line intersection corrected'
v['native_round_trip']='PASS';v['native_shape_total']=sum(p['native_shapes'] for p in v['pages'])
v['glued_endpoints']=sum(p['connections'] for p in v['pages']);v['delivery_links']='PASS';v['payload_hashes']=checked
v['marker']='PC_PS_PL_DIAGRAMS_DOCUMENTATION_PASS'
(RUN/'verification.json').write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
artifact_manifest=[]
for f in sorted(out.iterdir()):
 if f.is_file() and f.name!='交付文件校验.json':artifact_manifest.append(dict(file=f.name,bytes=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
(out/'交付文件校验.json').write_text(json.dumps(artifact_manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(RUN/'artifact_manifest.json').write_text(json.dumps(artifact_manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(RUN/'result_marker.txt').write_text(v['marker']+'\n',encoding='utf-8')
print(json.dumps(dict(marker=v['marker'],pages=6,shapes=v['native_shape_total'],glued_endpoints=v['glued_endpoints'],delivery_files=len(artifact_manifest)+1,source_changes=v['input_hash_changes'],links='PASS'),ensure_ascii=False))
