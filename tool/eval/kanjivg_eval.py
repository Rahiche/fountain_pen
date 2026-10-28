"""kanjivg_eval.py <kanjivg.xml.gz> <strokes.json> [results.json]: how close a
traced Japanese hand (strokes_cjk.py's strokes.json) comes to KanjiVG's stroke
data. KanjiVG (https://kanjivg.tagaini.net, CC BY-SA 3.0) is only measured
against here: none of it goes into a hand.

For each character both have, both sets of strokes are fitted into a unit box
and paired by shape (an optimal assignment, either way along). Then:
  count      the same number of strokes
  order      the pairs in KanjiVG's order: Kendall's tau, and exactly
  direction  each paired stroke run KanjiVG's way
  exact      all three: the character written just as KanjiVG writes it
  shape      the mean distance between paired strokes (of the box)
and the same for a naive order (top first, then left: no rules) to compare.

    python3 -I tool/eval/kanjivg_eval.py kanjivg-20260714.xml.gz work/strokes.json results.json
"""
import gzip, json, math, re, sys
import xml.etree.ElementTree as ET
import numpy as np

KVG = '{http://kanjivg.tagaini.net}'
TOKEN = re.compile(r'[MmCcSsLlHhVvZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def svg_points(d, steps=10):
    """An SVG path (KanjiVG's: moves, lines, cubic curves) as points along it."""
    toks = TOKEN.findall(d)
    pts, i, cmd = [], 0, None
    cur = np.zeros(2)
    start = cur.copy()
    ctrl = None

    def pair():
        nonlocal i
        v = np.array([float(toks[i]), float(toks[i + 1])])
        i += 2
        return v

    def cubic(p0, c1, c2, p1):
        for k in range(1, steps + 1):
            t = k / steps
            u = 1 - t
            pts.append(u ** 3 * p0 + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t ** 3 * p1)

    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
            if cmd in 'Zz':
                cur = start.copy()
                pts.append(cur.copy())
            continue
        rel = cmd.islower()
        if cmd in 'Mm':
            p = pair()
            cur = cur + p if rel and pts else p
            start = cur.copy()
            pts.append(cur.copy())
            cmd = 'l' if rel else 'L'
            ctrl = None
        elif cmd in 'Ll':
            p = pair()
            cur = cur + p if rel else p
            pts.append(cur.copy())
            ctrl = None
        elif cmd in 'Hh':
            v = float(toks[i])
            i += 1
            cur = np.array([cur[0] + v if rel else v, cur[1]])
            pts.append(cur.copy())
            ctrl = None
        elif cmd in 'Vv':
            v = float(toks[i])
            i += 1
            cur = np.array([cur[0], cur[1] + v if rel else v])
            pts.append(cur.copy())
            ctrl = None
        elif cmd in 'Cc':
            c1, c2, p = pair(), pair(), pair()
            if rel:
                c1, c2, p = cur + c1, cur + c2, cur + p
            cubic(cur, c1, c2, p)
            ctrl, cur = c2, p
        elif cmd in 'Ss':
            c2, p = pair(), pair()
            if rel:
                c2, p = cur + c2, cur + p
            c1 = 2 * cur - ctrl if ctrl is not None else cur
            cubic(cur, c1, c2, p)
            ctrl, cur = c2, p
        else:
            i += 1
    return np.array(pts)


def kanjivg(path):
    """Each character's strokes (y down), in KanjiVG's order."""
    out = {}
    with gzip.open(path) as f:
        for _, el in ET.iterparse(f):
            if el.tag != 'kanji':
                continue
            kid = el.get('id', '')
            m = re.fullmatch(r'kvg:kanji_([0-9a-f]+)', kid)
            if m:
                strokes = []
                for p in el.iter('path'):
                    n = re.search(r'-s(\d+)$', p.get('id', ''))
                    if n and p.get('d'):
                        strokes.append((int(n.group(1)), svg_points(p.get('d'))))
                strokes.sort(key=lambda s: s[0])
                if strokes:
                    out[chr(int(m.group(1), 16))] = [s for _, s in strokes]
            el.clear()
    return out


def ours(path):
    """Each character's strokes (y up, so flipped to y down), in the hand's order."""
    d = json.load(open(path))['glyphs']
    out = {}
    for c, g in d.items():
        strokes = []
        for s in g['strokes']:
            p = np.array(s['p'], float).reshape(-1, 3)[:, :2]
            strokes.append(p * (1, -1))
        out[c] = strokes
    return out


def fit(strokes):
    """Into a unit box, keeping their proportions, centred."""
    allp = np.vstack(strokes)
    lo, hi = allp.min(0), allp.max(0)
    k = 1 / max(float((hi - lo).max()), 1e-9)
    mid = (lo + hi) / 2
    return [(s - mid) * k + 0.5 for s in strokes]


def resample(p, n=20):
    if len(p) < 2:
        return np.repeat(p[:1], n, axis=0)
    run = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(p, axis=0).T))])
    if run[-1] == 0:
        return np.repeat(p[:1], n, axis=0)
    at = np.linspace(0, run[-1], n)
    return np.column_stack([np.interp(at, run, p[:, 0]), np.interp(at, run, p[:, 1])])


def hungarian(cost):
    """The cheapest one-to-one pairing of rows with columns (rows <= columns)."""
    n, m = len(cost), len(cost[0])
    INF = float('inf')
    u, v, p, way = [0.0] * (n + 1), [0.0] * (m + 1), [0] * (m + 1), [0] * (m + 1)
    for i in range(1, n + 1):
        p[0] = i
        j0 = 0
        minv, used = [INF] * (m + 1), [False] * (m + 1)
        while True:
            used[j0] = True
            i0, delta, j1 = p[j0], INF, 0
            for j in range(1, m + 1):
                if not used[j]:
                    c = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if c < minv[j]:
                        minv[j], way[j] = c, j0
                    if minv[j] < delta:
                        delta, j1 = minv[j], j
            for j in range(m + 1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minv[j] -= delta
            j0 = j1
            if p[j0] == 0:
                break
        while True:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
            if j0 == 0:
                break
    pairs = [-1] * n
    for j in range(1, m + 1):
        if p[j]:
            pairs[p[j] - 1] = j - 1
    return pairs


def kendall(seq):
    n = len(seq)
    if n < 2:
        return 1.0
    s = sum((1 if seq[b] > seq[a] else -1) for a in range(n) for b in range(a + 1, n))
    return s / (n * (n - 1) / 2)


def score(mine, ref):
    """How mine (strokes in its order) compares with ref: paired by shape."""
    A = [resample(s) for s in fit(mine)]
    B = [resample(s) for s in fit(ref)]
    swap = len(A) > len(B)
    rows, cols = (B, A) if swap else (A, B)
    cost, same = [], []
    for r in rows:
        row, srow = [], []
        for c in cols:
            fwd = float(np.mean(np.hypot(*(r - c).T)))
            back = float(np.mean(np.hypot(*(r - c[::-1]).T)))
            row.append(min(fwd, back))
            srow.append(fwd <= back)
        cost.append(row)
        same.append(srow)
    pairs = hungarian(cost)
    matched = []  # (my index, ref index, cost, same way)
    for i, j in enumerate(pairs):
        if j < 0:
            continue
        mi, ri = (j, i) if swap else (i, j)
        matched.append((mi, ri, cost[i][j], same[i][j]))
    matched.sort()
    seq = [ri for _, ri, _, _ in matched]
    count = len(A) == len(B)
    order = count and seq == list(range(len(B)))
    way = sum(1 for m in matched if m[3]) / max(len(matched), 1)
    return {
        'count': count, 'order': order, 'tau': kendall(seq), 'way': way,
        'exact': order and way == 1.0, 'shape': float(np.mean([m[2] for m in matched])) if matched else 1.0,
        'n': len(A), 'n_ref': len(B), 'pairs': [(m[0], m[1]) for m in matched],
    }


def naive(strokes):
    """The same strokes, top first then left, by where each starts (y up)."""
    return sorted(strokes, key=lambda s: -s[0][1] + 0.45 * s[0][0])


def group(c):
    o = ord(c)
    if 0x3041 <= o <= 0x309F:
        return 'hiragana'
    if 0x30A0 <= o <= 0x30FF:
        return 'katakana'
    try:
        b = c.encode('euc_jp')
        if len(b) == 2 and 0xB0 <= b[0] <= 0xCF:
            return 'kanji L1'
        if len(b) == 2 and 0xD0 <= b[0] <= 0xF4:
            return 'kanji L2'
    except UnicodeEncodeError:
        pass
    return 'other'


def main():
    ref = kanjivg(sys.argv[1])
    mine = ours(sys.argv[2])
    both = [c for c in mine if c in ref and group(c) != 'other']
    results = {}
    for c in both:
        if not mine[c]:
            # (Nothing traced: wrong on every count.)
            results[c] = {'group': group(c), 'count': False, 'order': False, 'tau': 0.0, 'way': 0.0, 'exact': False,
                          'shape': 1.0, 'n': 0, 'n_ref': len(ref[c]), 'pairs': [], 'naive_order': False, 'naive_tau': 0.0}
            continue
        r = score(mine[c], ref[c])
        # (Flip back to y up for the naive order's "top first", then fit again.)
        nv = naive([s * (1, -1) for s in mine[c]])
        rn = score([s * (1, -1) for s in nv], ref[c])
        results[c] = {'group': group(c), **r, 'naive_order': rn['order'], 'naive_tau': rn['tau']}
    print(f'{len(both)} characters in both (of {len(mine)} traced, {len(ref)} in KanjiVG)\n')
    head = f"{'':10}{'chars':>7}{'count':>8}{'order':>8}{'tau':>7}{'way':>7}{'exact':>8}{'shape':>7}   {'naive order':>12}{'naive tau':>10}"
    print(head)
    for name in ('hiragana', 'katakana', 'kanji L1', 'kanji L2', 'all'):
        rs = [r for r in results.values() if name == 'all' or r['group'] == name]
        if not rs:
            continue
        pct = lambda k: 100 * sum(1 for r in rs if r[k]) / len(rs)
        mean = lambda k: sum(r[k] for r in rs) / len(rs)
        print(f"{name:10}{len(rs):7d}{pct('count'):7.1f}%{pct('order'):7.1f}%{mean('tau'):7.3f}{100 * mean('way'):6.1f}%"
              f"{pct('exact'):7.1f}%{mean('shape'):7.3f}   {pct('naive_order'):11.1f}%{mean('naive_tau'):10.3f}")
    if len(sys.argv) > 3:
        json.dump(results, open(sys.argv[3], 'w'), ensure_ascii=False)


if __name__ == '__main__':
    main()
