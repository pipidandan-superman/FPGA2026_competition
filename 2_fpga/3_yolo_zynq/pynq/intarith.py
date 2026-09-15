"""PS 侧整数算术原语（与 G2 intref_yolov8.py 语义逐位一致，无 torch 依赖）。

来源合同：G2 run 4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01
（W8A8 / 每通道 M+shift RNE 重量化 / 移位上 RNE ties-to-even）。
两侧一致性由 offline 回归（raw_head_sha256 逐字节比对）保证。
"""
import numpy as np


def rne_shift(n: np.ndarray, s: int) -> np.ndarray:
    """int64 数组除以 2^s 的最近偶数舍入（s>=0；s<0 为左移）。

    s 先归一为 Python int：np.frexp 指数是 np.int32，NEP50 下
    `1 << np.int32(41)` 回绕为 0，会把平局阈值 full 变 0、使 s>=32 的
    RNE 退化为非零余数进位（均值 +0.5LSB）。_dyadic/requant_to 内部
    frexp 调用同样会传入 np.int32，故必须在入口统一归一。"""
    s = int(s)
    if s <= 0:
        if s == 0:
            return n.astype(np.int64)
        v = n.astype(np.int64) << (-s)
        assert np.abs(v).max(initial=0) < 2**63, 'shift-left overflow'
        return v
    q = n >> s                      # 算术向下取整
    rem = n - (q << s)              # (-2^s, 2^s)
    twice = rem * 2
    full = 1 << s                   # 平局阈值
    q = q + np.where(twice > full, 1, 0) + np.where(twice < -full, -1, 0)
    tie = (twice == full) | (twice == -full)
    q = q + np.where(tie & ((q & 1) == 1), np.where(twice > 0, 1, -1), 0)
    return q


def sat_i8(x):
    return np.clip(x, -128, 127).astype(np.int8)


def sat_i32(x):
    return np.clip(x, -2**31, 2**31 - 1).astype(np.int32)


def requant_to(x_q: np.ndarray, s_from: float, s_to: float) -> np.ndarray:
    """int8 张量从尺度 s_from 重量化到 s_to（Add/Concat 路径用）。

    M/shift 用与 G2 intref 相同的 frexp 规则现算（确定性：同一对尺度必得同一对
    M/shift，离线与板上一致；调度器另行为 RTL 预计算存档）。"""
    f, e = np.frexp(s_from / s_to)
    while f < 0.5:
        f *= 2
        e -= 1
    while f >= 1.0:
        f /= 2
        e += 1
    M = int(np.round(f * (1 << 31)))
    if M >= (1 << 31):
        M >>= 1
        e += 1
    s = 31 - e
    if s > 62:
        return np.zeros_like(x_q)
    n = x_q.astype(np.int64) * M
    return sat_i8(rne_shift(n, s))


def maxpool5(x_q: np.ndarray) -> np.ndarray:
    """5x5 stride1 maxpool，边界补 -128（输入零点）。"""
    N, C, H, W = x_q.shape
    k = 5
    p = k // 2
    xp = np.full((N, C, H + 2 * p, W + 2 * p), -128, dtype=np.int8)
    xp[:, :, p:p + H, p:p + W] = x_q
    Ho, Wo = H + 2 * p - k + 1, W + 2 * p - k + 1
    out = np.full((N, C, Ho, Wo), -128, dtype=np.int8)
    for i in range(k):
        for j in range(k):
            np.maximum(out, xp[:, :, i:i + Ho, j:j + Wo], out=out)
    return out


def upsample_nearest2(x_q: np.ndarray) -> np.ndarray:
    return x_q.repeat(2, axis=2).repeat(2, axis=3)
