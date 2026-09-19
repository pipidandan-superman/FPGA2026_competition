import csv
import hashlib
import json
import math
import stat
import zipfile
from collections import Counter
from pathlib import Path

import yaml
from PIL import Image

root = Path(__file__).resolve().parent
archive = root / 'Hand_Gesture_v6_yolov8.zip'
target = root / 'dataset'
if target.exists():
    raise RuntimeError('Extraction target already exists; refusing overwrite')
with zipfile.ZipFile(archive) as z:
    entries = z.infolist()
    if len(entries) > 20000 or sum(e.file_size for e in entries) > 1024**3:
        raise RuntimeError('Archive exceeds expected safety limits')
    seen = set()
    for e in entries:
        p = (target / e.filename).resolve()
        key = str(p).casefold()
        if not p.is_relative_to(target.resolve()) or ':' in e.filename or '\\' in e.filename:
            raise RuntimeError('Unsafe archive path')
        if key in seen or stat.S_ISLNK(e.external_attr >> 16):
            raise RuntimeError('Duplicate path or symlink')
        seen.add(key)
    bad = z.testzip()
    if bad:
        raise RuntimeError('ZIP CRC failed: ' + bad)
    z.extractall(target)

config = yaml.safe_load((target / 'data.yaml').read_text(encoding='utf-8'))
names = config['names']
expected = ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
issues = []
splits = {}
manifest = []
sizes = Counter()
for split in ['train', 'valid', 'test']:
    images = sorted((target / split / 'images').glob('*'))
    labels = sorted((target / split / 'labels').glob('*.txt'))
    boxes = Counter()
    for image in images:
        if not image.is_file():
            continue
        rel = image.relative_to(target).as_posix()
        try:
            with Image.open(image) as im:
                sizes[str(im.size)] += 1
                im.verify()
            with Image.open(image) as im:
                im.load()
        except Exception as exc:
            issues.append({'file': rel, 'error': 'image_decode', 'detail': str(exc)})
        label = target / split / 'labels' / (image.stem + '.txt')
        if not label.exists():
            issues.append({'file': rel, 'error': 'missing_label'})
        else:
            for ln, line in enumerate(label.read_text(encoding='utf-8').splitlines(), 1):
                if not line.strip():
                    continue
                try:
                    fields = line.split()
                    assert len(fields) == 5
                    cls = int(fields[0])
                    coords = [float(x) for x in fields[1:]]
                    assert 0 <= cls < len(names)
                    assert all(math.isfinite(x) and 0 <= x <= 1 for x in coords)
                    assert coords[2] > 0 and coords[3] > 0
                    boxes[str(cls)] += 1
                except (ValueError, AssertionError):
                    issues.append({'file': label.relative_to(target).as_posix(), 'line': ln, 'error': 'invalid_yolo_row'})
        manifest.append({'split': split, 'image': rel, 'bytes': image.stat().st_size, 'sha256': hashlib.sha256(image.read_bytes()).hexdigest()})
    image_stems = {p.stem for p in images}
    for label in labels:
        if label.stem not in image_stems:
            issues.append({'file': label.relative_to(target).as_posix(), 'error': 'orphan_label'})
    splits[split] = {'images': len(images), 'labels': len(labels), 'boxes_per_class_id': dict(boxes)}

result = {
    'download_status': 'DOWNLOAD_AND_ZIP_CRC_PASS',
    'package_check': 'PACKAGE_STRUCTURE_PASS' if not issues and names == expected else 'PACKAGE_CHECK_WARNING',
    'archive': str(archive), 'archive_bytes': archive.stat().st_size,
    'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'zip_entries': len(entries), 'uncompressed_bytes': sum(e.file_size for e in entries),
    'dataset_directory': str(target), 'data_yaml': config,
    'classes_match_model': names == expected, 'splits': splits, 'image_sizes': dict(sizes),
    'issue_count': len(issues), 'issues': issues,
    'scope': 'ZIP CRC, safe paths, image decoding, image-label pairing and YOLO row syntax only. No semantic label audit, no calibration or inference.'
}
(root / 'validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
with (root / 'image_manifest.csv').open('w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=['split', 'image', 'bytes', 'sha256'])
    writer.writeheader()
    writer.writerows(manifest)
print(json.dumps(result, ensure_ascii=True, indent=2))
