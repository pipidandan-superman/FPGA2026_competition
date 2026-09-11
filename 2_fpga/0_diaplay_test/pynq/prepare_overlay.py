"""Extract only the validated pair from the current board-proven XSA."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

XSA_HASH = 'd69fb256b66106da87514fc3821fe177bbe538c128e74485f43a4a265f092ebc'
EXPECTED = {'overlay.bit': '0518c46b4dca4dca83b1e94ae5c1e8cbc8bb68fbf4537e5a90c025a10b76db87',
            'overlay.hwh': '96eeba65209e66ac3e05a65907f48cc374dab490b9d88e2e72e22689e939a4dd'}
parser = argparse.ArgumentParser()
parser.add_argument('--xsa', type=Path, default=Path(__file__).resolve().parents[1] / 'vitis/display_test_wrapper.xsa')
parser.add_argument('--out', type=Path, default=Path(__file__).resolve().parent)
args = parser.parse_args()
if hashlib.sha256(args.xsa.read_bytes()).hexdigest() != XSA_HASH:
    raise SystemExit('XSA changed: revalidate hardware address windows and update the application contract first')
parts = {}
with zipfile.ZipFile(args.xsa) as archive:
    for dest, digest in EXPECTED.items():
        candidates = [archive.read(n) for n in archive.namelist() if n.lower().endswith(Path(dest).suffix)]
        matches = [data for data in candidates if hashlib.sha256(data).hexdigest() == digest]
        if len(matches) != 1:
            raise SystemExit(f'Expected exactly one validated {dest}')
        parts[dest] = matches[0]
args.out.mkdir(parents=True, exist_ok=True)
for name, data in parts.items():
    target = args.out / name
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != EXPECTED[name]:
        raise SystemExit(f'Refusing to overwrite a different overlay: {target}')
    target.write_bytes(data)
print(json.dumps(dict(result='OVERLAY_PAIR_VERIFIED', xsa_sha256=XSA_HASH, files=EXPECTED), indent=2))
