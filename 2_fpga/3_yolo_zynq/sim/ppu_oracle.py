#!/usr/bin/env python3
"""ppu_oracle.py - PPU graph-op integer kernels (P1/P2 authority library).

Every kernel is a verbatim transcription of the frozen software contract
(intref_yolov8.py, run04 copy) so that RTL testbenches and the golden replay
share ONE arithmetic definition.  The G0 replay already proved these
semantics bit-equivalent to the software golden; this library must not
invent or "improve" anything.

Kernels take precomputed (M, shift) pairs exactly like the hardware
descriptor path (quant-table profiles): the PL never computes req_pair.

verbatim sources (intref_yolov8.py, run04):
  rne_shift      lines 37-59   (NEP50: s must be python int)
  sat_i8         line  62
  req_pair       lines 70-87
  requant_to     lines 176-180 (concat segment requant)
  int_add        lines 183-189 (dual requant, int32 sum, saturate once)
  maxpool5       lines 192-204 (k5 s1 p2, pad -128)
  upsample_nearest2 lines 207-208
"""
import numpy as np


def rne_shift(n, s):
    """Round-to-nearest-even divide of int64 array by 2^s. VERBATIM."""
    s = int(s)
    if s <= 0:
        if s == 0:
            return n.astype(np.int64)
        v = n.astype(np.int64) << (-s)
        assert np.abs(v).max(initial=0) < 2 ** 63, 'shift-left overflow'
        return v
    q = n >> s
    rem = n - (q << s)
    twice = rem * 2
    full = 1 << s
    q = q + np.where(twice > full, 1, 0) + np.where(twice < -full, -1, 0)
    tie = (twice == full) | (twice == -full)
    q = q + np.where(tie & ((q & 1) == 1), np.where(twice > 0, 1, -1), 0)
    return q


def sat_i8(x):
    """Saturate to int8. VERBATIM."""
    return np.clip(x, -128, 127).astype(np.int8)


def sat_i32(x):
    """Saturate to int32. VERBATIM (add contract keeps this clip order)."""
    return np.clip(x, -2 ** 31, 2 ** 31 - 1)


def req_pair(r):
    """(M, shift) pair for ratio r>0. VERBATIM (software-side only;
    hardware receives M/shift via quant-table profiles)."""
    assert r > 0
    f, e = np.frexp(r)
    while f < 0.5:
        f *= 2
        e -= 1
    while f >= 1.0:
        f /= 2
        e += 1
    m = int(np.round(f * (1 << 31)))
    if m >= (1 << 31):
        m >>= 1
        e += 1
    shift = 31 - e
    if shift > 62:
        return 0, 0
    return m, int(shift)


IDENT_M, IDENT_S = 1 << 30, 30     # req_pair(1.0): exact identity pass-through


def is_identity_pair(m, s):
    """Same-scale segments may take the hardware shortcut (plain copy);
    bit-exact because x*2^30 >> 30 RNE == x for all int8 x (P0-proven)."""
    return m == IDENT_M and s == IDENT_S


def requant_seg(x_q, m, s):
    """Concat/copy segment requant: x_q int8, (m,s) profile. VERBATIM
    requant_to body with caller-supplied pair (hardware segment path)."""
    n = x_q.astype(np.int64) * int(m)
    return sat_i8(rne_shift(n, int(s)))


def add_q(a_q, ma, sa, b_q, mb, sb):
    """Add kernel (public): both inputs requantized then summed once."""
    a = rne_shift(a_q.astype(np.int64) * int(ma), int(sa))
    b = rne_shift(b_q.astype(np.int64) * int(mb), int(sb))
    return sat_i8(sat_i32(a + b))


def concat_q(segments):
    """Concat kernel: [(x_q int8 [C_i,H,W], m_i, s_i), ...] -> [C,H,W].
    Identity-pair segments are plain copies (exact, P0-proven)."""
    parts = []
    for x_q, m, s in segments:
        if is_identity_pair(m, s):
            parts.append(x_q)
        else:
            parts.append(requant_seg(x_q, m, s))
    return np.concatenate(parts, axis=0)


def maxpool5_padded(x_q):
    """5x5 s1 maxpool, pad -128. VERBATIM (pad-value model)."""
    c, h, w = x_q.shape
    k, p = 5, 2
    xp = np.full((c, h + 2 * p, w + 2 * p), -128, dtype=np.int8)
    xp[:, p:p + h, p:p + w] = x_q
    o = np.full((c, h, w), -128, dtype=np.int8)
    for i in range(k):
        for j in range(k):
            np.maximum(o, xp[:, i:i + h, j:j + w], out=o)
    return o


def maxpool5_masked(x_q):
    """Hardware-structure model: max over VALID window positions only
    (no pad bytes materialised).  Equivalence to the pad-value model is
    proven in PPU manual section 2.2 (pad -128 == int8 minimum); this
    model exists so P2 can cross-check both structures on real and
    adversarial vectors."""
    c, h, w = x_q.shape
    k, p = 5, 2
    o = np.empty((c, h, w), dtype=np.int8)
    for y in range(h):
        for x in range(w):
            y0, y1 = max(0, y - p), min(h, y - p + k)
            x0, x1 = max(0, x - p), min(w, x - p + k)
            o[:, y, x] = x_q[:, y0:y1, x0:x1].max(axis=(1, 2))
    return o


def upsample2_q(x_q):
    """Nearest-neighbour x2 on H and W. VERBATIM shape-wise."""
    return x_q.repeat(2, axis=1).repeat(2, axis=2)


def view_q(x_q, c0, c1):
    """View = channel slice; zero-copy at the buffer-table level."""
    return x_q[c0:c1]


# --------------------------------------------------------------------- --
# TB-oriented statistics (NOT part of the bit-exact path): counts the
# adversarial events a P2 vector generator must cover (lesson: synthetic
# stimulus that never exercises ties/saturation gives false-green gates).
# --------------------------------------------------------------------- --
def requant_stats(x_q, m, s):
    """Element stats of one requant application (for vecgen coverage audit)."""
    n = x_q.astype(np.int64) * int(m)
    s = int(s)
    q = n >> s
    rem = n - (q << s)
    twice = rem * 2
    full = 1 << s
    tie = (twice == full) | (twice == -full)
    y = sat_i8(rne_shift(n, s))
    return {
        'elems': int(x_q.size),
        'ties': int(np.count_nonzero(tie)),
        'sat_lo': int(np.count_nonzero(y == -128)),
        'sat_hi': int(np.count_nonzero(y == 127)),
        'identity_path': bool(is_identity_pair(m, s)),
        'distinct_vals': int(len(np.unique(x_q))),
    }
