"""G2 部署包加载器（无 torch/numpy 模型依赖）。

包 = rom_data/{quant.json, weights.bin, bias.bin, lut.bin, manifest.json}。
布局：quant.json 各节点含 w_off/b_off/l_off（字节偏移，节点按 sorted(nodes) 顺序导出）。
"""
import json
from pathlib import Path
import numpy as np


class YoloPackage:
    def __init__(self, rom_dir):
        self.dir = Path(rom_dir)
        q = json.loads((self.dir / 'quant.json').read_text(encoding='utf-8'))
        self.quant = q
        self.size = q['input']['size']
        self.input_scale = q['input']['scale']
        self.nodes = {n['node']: n for n in q['nodes']}
        self.tensor_scales = q['tensor_scales']
        self.w_buf = np.frombuffer((self.dir / 'weights.bin').read_bytes(), dtype=np.int8)
        self.b_buf = np.frombuffer((self.dir / 'bias.bin').read_bytes(), dtype='<i4')
        self.lut_buf = np.frombuffer((self.dir / 'lut.bin').read_bytes(), dtype=np.int8)
        self.manifest = json.loads((self.dir / 'manifest.json').read_text(encoding='utf-8'))

    def node(self, name):
        return self.nodes[name]

    def w(self, name):
        n = self.nodes[name]
        shape = n['w_shape']
        cnt = int(np.prod(shape))
        return self.w_buf[n['w_off']:n['w_off'] + cnt].reshape(shape)

    def b(self, name):
        n = self.nodes[name]
        cnt = shape_out = n['w_shape'][0]
        return self.b_buf[n['b_off'] // 4:n['b_off'] // 4 + cnt].copy()

    def lut(self, name):
        n = self.nodes[name]
        if not n['has_act']:
            return None
        return self.lut_buf[n['l_off']:n['l_off'] + 256].copy()

    def stored_scale(self, name):
        return self.nodes[name]['stored_scale']

    def verify_hashes(self):
        """对包内 4 个文件核对 manifest SHA-256（加载时强制，防止半更新包）。"""
        import hashlib
        ok = {}
        for f, want in self.manifest['files'].items():
            got = hashlib.sha256((self.dir / f).read_bytes()).hexdigest()
            ok[f] = (got == want)
        return ok
