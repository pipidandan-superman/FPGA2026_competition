"""Read-only model audit and analytical sizing; no training or RTL build."""
from pathlib import Path
import os
import sys
import json
import csv
import hashlib
import math
from collections import Counter

RUN = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
for key, leaf in [('YOLO_CONFIG_DIR', 'ultralytics_config'), ('MPLCONFIGDIR', 'matplotlib_config')]:
    os.environ[key] = str(RUN / leaf)
    (RUN / leaf).mkdir(exist_ok=True)
os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false',
                  PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1',
                  OMP_NUM_THREADS='2', MKL_NUM_THREADS='2')

import torch
import onnx
import numpy as np
import onnxruntime as ort
import ultralytics
from ultralytics import YOLO, settings
from ultralytics.utils import USER_CONFIG_DIR

assert Path(USER_CONFIG_DIR).resolve().is_relative_to(RUN)
settings.update({'sync': False, 'runs_dir': str(RUN/'predictions'),
                 'datasets_dir': str(RUN/'datasets'), 'weights_dir': str(RUN/'weights')})
torch.set_num_threads(2)


def save(name, data):
    (RUN/name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shape_tree(value):
    if isinstance(value, torch.Tensor):
        return list(value.shape)
    if isinstance(value, (list, tuple)):
        return [shape_tree(x) for x in value]
    if isinstance(value, dict):
        return {str(k): shape_tree(v) for k, v in value.items()}
    return str(type(value))


def main():
    files = {n: ROOT/'3_host/model'/n for n in ('best.pt', 'best.onnx')}
    expected = {'best.pt': '68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79',
                'best.onnx': 'ac45c457be282ea1d9db819180930b062436ecc834219c3418ff06e9e6bbbf0f'}
    hashes = {n: sha(p) for n, p in files.items()}
    assert hashes == expected, hashes
    model = YOLO(str(files['best.pt']), task='detect').model.eval().float()
    head = model.model[-1]
    result = {'result': 'IN_PROGRESS', 'python': sys.executable,
              'versions': {'torch': torch.__version__, 'ultralytics': ultralytics.__version__,
                           'onnx': onnx.__version__, 'onnxruntime': ort.__version__},
              'model_sha256': hashes, 'parameters_all': sum(p.numel() for p in model.parameters()),
              'classes': model.names, 'strides': head.stride.tolist(), 'nc': head.nc,
              'reg_max': head.reg_max, 'raw_head_channels': head.no,
              'module_counts': dict(Counter(type(m).__name__ for m in model.modules())),
              'profiles': {}, 'notes': [
                  'Synthetic forward shapes and exact dense MAC counts, not accuracy or hardware performance.',
                  'MAC convention: one multiply-accumulate; ops=2*MAC; non-convolution ops excluded.',
                  'FP32 graph activation elements interpreted as hypothetical INT8 byte capacities only.',
                  '320/416/256 are PyTorch shape trials, not modified existing fixed-640 ONNX.',
                  'Traffic estimates exclude tiling reloads, padding, nonconv traffic and bus overhead.']}
    save('architecture.json', model.yaml)
    for size in (256, 320, 416, 640):
        rows, stages, handles = [], [], []
        def conv_hook(name):
            def hook(m, ins, out):
                x = ins[0]
                b, co, ho, wo = out.shape
                kh, kw = m.kernel_size
                k = m.in_channels // m.groups * kh * kw
                mac = int(b*co*ho*wo*k)
                rows.append(dict(name=name, input_shape=list(x.shape), output_shape=list(out.shape),
                    kernel=list(m.kernel_size), stride=list(m.stride), padding=list(m.padding),
                    groups=m.groups, M=int(co), N=int(b*ho*wo), K=int(k), macs=mac,
                    weights=m.weight.numel(), bias=0 if m.bias is None else m.bias.numel(),
                    ifm_elements=x.numel(), ofm_elements=out.numel(),
                    materialized_im2col_elements=int(b*ho*wo*k*m.groups),
                    is_dfl='dfl' in name))
            return hook
        for name, m in model.named_modules():
            if isinstance(m, torch.nn.Conv2d):
                handles.append(m.register_forward_hook(conv_hook(name)))
        for i, m in enumerate(model.model):
            def top_hook(module, ins, out, idx=i):
                stages.append(dict(index=idx, kind=type(module).__name__,
                                   source=module.f, output=shape_tree(out)))
            handles.append(m.register_forward_hook(top_hook))
        with torch.inference_mode():
            output = model(torch.zeros(1, 3, size, size))
        for h in handles:
            h.remove()
        y = output[0] if isinstance(output, (tuple, list)) else output
        network_rows = [r for r in rows if not r['is_dfl']]
        profile = dict(input_size=size, output_shape=list(y.shape), raw_shapes=shape_tree(output[1]),
                       conv_calls=len(rows), network_conv_calls=len(network_rows),
                       conv_macs=sum(r['macs'] for r in rows),
                       network_conv_macs=sum(r['macs'] for r in network_rows),
                       conv_weight_elements=sum(r['weights'] for r in network_rows),
                       max_single_conv_output_int8_bytes=max(r['ofm_elements'] for r in network_rows),
                       max_im2col_int8_bytes=max(r['materialized_im2col_elements'] for r in network_rows),
                       naive_conv_input_output_int8_bytes=sum(r['ifm_elements']+r['ofm_elements'] for r in network_rows),
                       raw_head_int8_bytes=int(head.no * sum((size//int(s))**2 for s in head.stride)),
                       max_k=max(r['K'] for r in network_rows),
                       conv_rows=rows, stages=stages)
        cycles = {}
        for pm, pn in ((8,8),(8,16),(16,8)):
            # K is serial; M output channels, N output positions. No DSP packing.
            active = sum(math.ceil(r['M']/pm)*math.ceil(r['N']/pn)*r['K'] for r in network_rows)
            wave = sum(math.ceil(r['M']/pm)*math.ceil(r['N']/pn)*(r['K']+pm+pn-2) for r in network_rows)
            cycles[f'{pm}x{pn}'] = dict(ideal_tiled_cycles=active, isolated_systolic_wave_cycles=wave,
                                      tiled_utilization=profile['network_conv_macs']/(active*pm*pn),
                                      wave_utilization=profile['network_conv_macs']/(wave*pm*pn))
        profile['array_cycle_models'] = cycles
        result['profiles'][str(size)] = profile
        with (RUN/f'conv_layers_{size}.csv').open('w', newline='', encoding='utf-8-sig') as stream:
            w=csv.DictWriter(stream, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
        print(f"SIZE {size}: MAC={profile['network_conv_macs']} max_activation={profile['max_single_conv_output_int8_bytes']} raw_head={profile['raw_head_int8_bytes']}", flush=True)
    graph = onnx.load(str(files['best.onnx']))
    onnx.checker.check_model(graph)
    inferred = onnx.shape_inference.infer_shapes(graph, strict_mode=True, data_prop=True)
    shapes = {}
    for value in list(inferred.graph.input)+list(inferred.graph.value_info)+list(inferred.graph.output):
        dims = value.type.tensor_type.shape.dim
        if all(d.HasField('dim_value') for d in dims):
            shapes[value.name] = [int(d.dim_value) for d in dims]
    initializers = {x.name: x for x in inferred.graph.initializer}
    nodes = []
    uses = Counter(t for n in inferred.graph.node for t in n.input)
    outputs = {o.name for o in inferred.graph.output}
    live = {i.name: math.prod(shapes[i.name]) for i in inferred.graph.input if i.name in shapes and i.name not in initializers}
    peak = sum(live.values())
    for n in inferred.graph.node:
        ns = {'name': n.name, 'op': n.op_type, 'inputs': list(n.input), 'outputs': list(n.output),
              'output_shapes': {o: shapes.get(o) for o in n.output}}
        if n.op_type == 'Conv':
            ws = list(initializers[n.input[1]].dims)
            os_ = shapes[n.output[0]]
            ns['macs'] = int(math.prod(os_) * math.prod(ws[1:]))
        nodes.append(ns)
        # Logical buffers without fusion or alias reuse, every numeric element costs one hypothetical byte.
        for o in n.output:
            if o in shapes and n.op_type != 'Constant':
                live[o] = math.prod(shapes[o])
        peak=max(peak,sum(live.values()))
        for i in n.input:
            uses[i]-=1
            if uses[i] == 0 and i not in outputs:
                live.pop(i,None)
        for o in n.output:
            if uses[o] == 0 and o not in outputs:
                live.pop(o,None)
    onnx_macs = sum(n.get('macs',0) for n in nodes)
    assert onnx_macs == result['profiles']['640']['conv_macs'], (onnx_macs,result['profiles']['640']['conv_macs'])
    result['onnx'] = dict(opsets=[{'domain': x.domain, 'version': x.version} for x in graph.opset_import],
                        node_count=len(nodes), ops=dict(Counter(n.op_type for n in graph.graph.node)),
                        initializer_elements=sum(math.prod(i.dims) for i in graph.graph.initializer),
                        initializer_bytes=sum(onnx.numpy_helper.to_array(i).nbytes for i in graph.graph.initializer),
                        conv_macs=onnx_macs, logical_live_peak_elements_no_fusion=peak,
                        known_shapes=len(shapes))
    save('onnx_nodes.json',nodes)
    # Check the two local formats on a fixed synthetic input. Not a dataset accuracy test.
    rng=np.random.default_rng(7020)
    x=rng.random((1,3,640,640),dtype=np.float32)
    with torch.inference_mode():
        pt=model(torch.from_numpy(x))[0].cpu().numpy()
    opts=ort.SessionOptions(); opts.intra_op_num_threads=2; opts.inter_op_num_threads=1
    session=ort.InferenceSession(str(files['best.onnx']), sess_options=opts, providers=['CPUExecutionProvider'])
    ox=session.run(None,{session.get_inputs()[0].name:x})[0]
    delta=np.abs(pt-ox)
    result['synthetic_format_check']={'max_abs': float(delta.max()), 'mean_abs': float(delta.mean()),
                                    'allclose_rtol1e-3_atol1e-3': bool(np.allclose(pt,ox,rtol=1e-3,atol=1e-3)),
                                    'finite': bool(np.isfinite(ox).all() and np.isfinite(pt).all())}
    assert {n:sha(p) for n,p in files.items()} == hashes
    result['result']='MODEL_STATIC_PROFILE_PASS'
    result['quantization']='NOT_RUN_NO_CALIBRATION_DATA_AUDIT'
    result['hardware']='NOT_RUN'
    result['script_sha256']=sha(Path(__file__))
    save('profile.json',result)
    summary={k:v for k,v in result.items() if k not in ('profiles','module_counts')}
    summary['profiles']={s:{k:v for k,v in p.items() if k not in ('conv_rows','stages','raw_shapes')} for s,p in result['profiles'].items()}
    save('summary.json',summary)
    print(json.dumps(summary,ensure_ascii=False,indent=2),flush=True)


if __name__ == '__main__':
    class Tee:
        def __init__(self,*streams): self.streams=streams
        def write(self,s):
            for stream in self.streams: stream.write(s); stream.flush()
        def flush(self):
            for stream in self.streams: stream.flush()
    with (RUN/'console.log').open('x',encoding='utf-8') as console:
        oldout,olderr=sys.stdout,sys.stderr
        sys.stdout=Tee(oldout,console); sys.stderr=Tee(olderr,console)
        try:
            main()
        except Exception:
            import traceback
            traceback.print_exc()
            raise
        finally:
            sys.stdout,sys.stderr=oldout,olderr
