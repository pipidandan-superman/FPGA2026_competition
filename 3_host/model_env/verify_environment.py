"""Environment smoke check only: no camera, accuracy or latency acceptance."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
args = parser.parse_args()
out = Path(args.output).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
os.environ['YOLO_CONFIG_DIR'] = str(out.parent / 'ultralytics_config')
os.environ['YOLO_AUTOINSTALL'] = 'false'
os.environ['MPLCONFIGDIR'] = str(out.parent / 'matplotlib_config')
os.environ['OMP_NUM_THREADS'] = '2'
os.environ['MKL_NUM_THREADS'] = '2'
os.environ['YOLO_OFFLINE'] = 'true'
for directory in ('YOLO_CONFIG_DIR', 'MPLCONFIGDIR'):
    Path(os.environ[directory]).mkdir(parents=True, exist_ok=True)

import cv2
import numpy as np
import onnx
import onnxruntime as ort
import torch
import torchvision
from ultralytics import YOLO, settings
from ultralytics.utils import USER_CONFIG_DIR

assert Path(USER_CONFIG_DIR).resolve().is_relative_to(out.parent), USER_CONFIG_DIR
settings.update({'sync': False, 'runs_dir': str(out.parent / 'predictions'),
                 'datasets_dir': str(out.parent / 'datasets'), 'weights_dir': str(out.parent / 'weights')})
root = Path(__file__).resolve().parents[2]
model_dir = root / '3_host/model'
expected = {
    'best.pt': '68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79',
    'best.onnx': 'ac45c457be282ea1d9db819180930b062436ecc834219c3418ff06e9e6bbbf0f',
}
for name, digest in expected.items():
    assert hashlib.sha256((model_dir / name).read_bytes()).hexdigest() == digest, name
assert sys.version_info[:3] == (3, 12, 10)
assert sys.prefix != sys.base_prefix
assert torch.version.cuda is None, 'Expected CPU baseline'
assert 'GUI:                           NONE' not in cv2.getBuildInformation()
torch.set_num_threads(2)
nms = torchvision.ops.nms(torch.tensor([[0., 0., 10., 10.], [1., 1., 9., 9.]]), torch.tensor([0.9, 0.8]), 0.5)
assert nms.tolist() == [0]
onnx.checker.check_model(str(model_dir / 'best.onnx'))
options = ort.SessionOptions()
options.intra_op_num_threads = 2
session = ort.InferenceSession(str(model_dir / 'best.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
input_meta, output_meta = session.get_inputs()[0], session.get_outputs()[0]
assert input_meta.shape == [1, 3, 640, 640], input_meta.shape
assert input_meta.type == 'tensor(float)', input_meta.type
assert output_meta.shape == [1, 11, 8400], output_meta.shape
dummy = np.zeros((1, 3, 640, 640), dtype=np.float32)
onnx_output = session.run(None, {input_meta.name: dummy})[0]
assert onnx_output.shape == (1, 11, 8400) and np.isfinite(onnx_output).all()
model = YOLO(str(model_dir / 'best.pt'), task='detect')
names = ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
assert [model.names[i] for i in range(7)] == names, model.names
with torch.inference_mode():
    prediction = model.model.eval()(torch.from_numpy(dummy))
    tensor = prediction[0] if isinstance(prediction, (tuple, list)) else prediction
    assert tuple(tensor.shape) == (1, 11, 8400) and torch.isfinite(tensor).all()
# Exercise actual preprocessing and postprocessing on a synthetic image.
image = np.zeros((480, 640, 3), dtype=np.uint8)
pt_result = model.predict(image, device='cpu', imgsz=640, rect=False, conf=0.45, iou=0.7, verbose=False, save=False)
assert len(pt_result) == 1 and pt_result[0].orig_shape == (480, 640)
packages = {d.metadata['Name'].lower(): d.version for d in importlib.metadata.distributions()}
result = dict(result='MODEL_ENV_SMOKE_PASS', python=sys.version, executable=sys.executable,
              platform=platform.platform(), base_prefix=sys.base_prefix, packages=dict(sorted(packages.items())),
              providers=session.get_providers(), model_sha256=expected, class_names=names,
              input_shape=input_meta.shape, output_shape=list(onnx_output.shape),
              torch_output_shape=list(tensor.shape), torchvision_nms='PASS', onnx_checker='PASS',
              synthetic_preprocess_postprocess='PASS', camera_opened=False,
              ultralytics_config_dir=str(USER_CONFIG_DIR),
              accuracy_validated=False, performance_validated=False)
out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(result, indent=2, ensure_ascii=False))
