from pathlib import Path
from zipfile import ZipFile
import json,hashlib,xml.etree.ElementTree as ET
import pypdfium2 as pdfium
from pypdf import PdfReader,PdfWriter
from PIL import Image,ImageDraw,ImageFont
RUN=Path(__file__).resolve().parent
scene=json.loads((RUN/'scene.json').read_text(encoding='utf-8'))
out=Path(scene['output_dir']);base=out/scene['basename']
ns={'v':'http://schemas.microsoft.com/office/visio/2012/main'}
results=[]
pdf=pdfium.PdfDocument(base.with_suffix('.pdf'));reader=PdfReader(base.with_suffix('.pdf'))
assert len(pdf)==6
with ZipFile(base.with_suffix('.vsdx')) as z:
 assert z.testzip() is None
 media=[n for n in z.namelist() if n.startswith('visio/media/')]
 assert not media,media
 for i,sc in enumerate(scene['pages']):
  nativepage=ET.fromstring(z.read(f'visio/pages/page{i+1}.xml'))
  native={s.attrib.get('NameU'):s for s in nativepage.findall('.//v:Shape',ns)}
  for s in sc['shapes']:
   e=native[s['id']].find('v:Text',ns)
   actual=''.join(e.itertext()).rstrip('\n') if e is not None else ''
   assert actual==s['text'],(i,s['id'],actual,s['text'])
  page=pdf[i];w,h=page.get_size();tp=page.get_textpage();txt=tp.get_text_range();scale=w/sc['width']
  norm='';indices=[]
  for j,ch in enumerate(txt):
   if not ch.isspace():norm+=ch;indices.append(j)
  missing=[];overflow=[]
  for s in sc['shapes']:
   if not s['text']:continue
   charids=[]
   for line in s['text'].splitlines():
    needle=''.join(line.split());start=norm.find(needle);found=False
    while start>=0:
     ids=[indices[j] for j in range(start,start+len(needle))]
     b=tp.get_charbox(ids[0]);cx=(b[0]+b[2])/2/scale;cy=(h-(b[1]+b[3])/2)/scale
     if s['x']-8<=cx<=s['x']+s['w']+8 and s['y']-8<=cy<=s['y']+s['h']+8:
      charids+=ids;found=True;break
     start=norm.find(needle,start+1)
    if not found:missing.append(dict(id=s['id'],line=line))
   boxes=[tp.get_charbox(j) for j in charids]
   boxes=[b for b in boxes if b[2]>b[0] and b[3]>b[1]]
   if boxes:
    bounds=[min(b[0] for b in boxes)/scale,(h-max(b[3] for b in boxes))/scale,max(b[2] for b in boxes)/scale,(h-min(b[1] for b in boxes))/scale]
    if bounds[0]<s['x']-3 or bounds[1]<s['y']-3 or bounds[2]>s['x']+s['w']+3 or bounds[3]>s['y']+s['h']+3:
     overflow.append(dict(id=s['id'],actual=bounds,box=[s['x'],s['y'],s['w'],s['h']]))
  img=page.render(scale=3).to_pil();img.save(out/(sc['basename']+'.png'))
  img.thumbnail((2000,1414));img.save(RUN/(sc['basename']+'_preview.png'))
  writer=PdfWriter();writer.add_page(reader.pages[i]);writer.write(str(out/(sc['basename']+'.pdf')))
  fonts=[]
  for fref in reader.pages[i]['/Resources']['/Font'].values():
   f=fref.get_object();fd=f.get('/FontDescriptor')
   if fd is None and f.get('/DescendantFonts'):fd=f['/DescendantFonts'][0].get_object().get('/FontDescriptor')
   d=fd.get_object() if fd else {};fonts.append(dict(name=str(f.get('/BaseFont')),embedded=any(k in d for k in ['/FontFile','/FontFile2','/FontFile3'])))
  results.append(dict(page=sc['name'],native_shapes=len(native),connections=len(nativepage.findall('.//v:Connect',ns)),text_missing=missing,text_overflow=overflow,fonts=fonts))
hash_changes=[];excluded_transient=[]
for src in json.loads((RUN/'source_manifest.json').read_text(encoding='utf-8')):
 p=Path(src['path'])
 if p.name.startswith('~'):
  excluded_transient.append(str(p));continue
 if hashlib.sha256(p.read_bytes()).hexdigest()!=src['sha256']:hash_changes.append(str(p))
thumb=Image.new('RGB',(1800,2010),'#dce3e8');draw=ImageDraw.Draw(thumb)
for i,sc in enumerate(scene['pages']):
 im=Image.open(RUN/(sc['basename']+'_preview.png'));im.thumbnail((880,623));x=10+(i%2)*900;y=10+(i//2)*670;thumb.paste(im,(x,y))
thumb.save(RUN/'contact_sheet.png')
status='PASS' if not hash_changes and all(not r['text_missing'] and not r['text_overflow'] and all(f['embedded'] for f in r['fonts']) for r in results) else 'REVIEW'
result=dict(marker='DIAGRAM_ARTIFACT_'+status,pages=results,input_hash_changes=hash_changes,excluded_transient_lock_files=excluded_transient,embedded_diagram_images=media,visual_review='PENDING',scope='Authored artifact checks only; no hardware tests executed')
(RUN/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
