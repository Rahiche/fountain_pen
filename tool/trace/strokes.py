"""strokes.py: each glyph's pen strokes, from its raster (glyphs.swift):
thinned to a centre line (Zhang-Suen), cut into a graph (ends, junctions
and the lines between), spurs pruned, then walked the way a hand would
draw it: from the leftmost end, at every fork on along the smoothest way,
lifting the pen only when stuck; a small detached part (a dot, a
crossbar) is "late", drawn once the word's done. → strokes.json (em units,
y up from the baseline; a radius per point).

    python3 tool/trace/strokes.py <work dir> [rtl]   (glyphs.swift's raster/ and meta.json in it)

rtl: for a script written right to left (Arabic): from the rightmost end,
each stroke turned round to run leftwards.
"""
import json, math, os, sys
import numpy as np
from skeleton import depth, edges, prune, rdp, smooth, thin, walk

if len(sys.argv) > 1:
    os.chdir(sys.argv[1])
rtl = len(sys.argv) > 2 and sys.argv[2] == 'rtl'

meta = json.load(open('meta.json'))
S = meta['S']


out = {'xHeight': meta['xHeight'], 'ascent': meta['ascent'], 'descent': meta['descent'], 'space': meta['space'], 'glyphs': {}}
for g in meta['glyphs']:
    w, h = g['w'], g['h']
    img = np.fromfile(f"raster/{g['code']}.gray", np.uint8).reshape(h, w) > 110
    d = depth(img)
    sk = thin(img)
    pix = set(zip(*np.nonzero(sk)))
    pix = prune(pix, d)
    es, _, _ = edges(pix)
    es = [e for e in es if len(e) >= 3]
    covered = {p for e in es for p in e}
    specks = [p for p in pix if p not in covered]
    dots = []
    for p in specks:
        for dd in dots:
            if abs(dd[0][0] - p[0]) <= 6 and abs(dd[0][1] - p[1]) <= 6:
                dd.append(p)
                break
        else:
            dots.append([p])
    # (Left and high first: an ascender's top before the end of its tail. Right
    # to left: right and high first.)
    side = -1 if rtl else 1
    strokes = walk(es, score=lambda p: side * (p[1] - g['ox']) / S - 0.6 * (g['oy'] - p[0]) / S,
                   **(dict(retrace=0.3 * S, hairpin=2.9) if rtl else {}))
    # Which part of the glyph each stroke is in (strokes that meet are one).
    part = {}
    for k, s in enumerate(strokes):
        part[k] = k
    def root(k):
        while part[k] != k:
            k = part[k]
        return k
    cells = [set(s) for s in strokes]
    for a in range(len(strokes)):
        for b in range(a + 1, len(strokes)):
            near = cells[a] & cells[b] or any((y + dy, x + dx) in cells[b] for (y, x) in (strokes[a][0], strokes[a][-1]) for dy in (-1, 0, 1) for dx in (-1, 0, 1))
            if near:
                part[root(a)] = root(b)
    size = {}
    for k, s in enumerate(strokes):
        size[root(k)] = size.get(root(k), 0) + len(s)
    main = max(size, key=size.get) if size else None
    # A Latin hand runs left to right: a first stroke found running back
    # (from the exit, say: an e's) is turned round, unless it starts at an
    # ascender's top (an l's), where a hand does start.
    if strokes:
        (y0, x0), (y1, x1) = strokes[0][0], strokes[0][-1]
        if side * (x0 - x1) > 0.15 * S and (g['oy'] - y0) / S < 1.25 * meta['xHeight']:
            strokes[0] = strokes[0][::-1]
    if rtl:
        # (Right to left: a main stroke found running rightwards, from a tail's
        # tip to a loop it closes (ف ق), is turned round to start at the loop.)
        for k, s_ in enumerate(strokes):
            (y0, x0), (y1, x1) = s_[0], s_[-1]
            if len(s_) > 0.3 * S and x1 - x0 > 0.15 * S and y0 >= y1 - 0.1 * S:
                strokes[k] = s_[::-1]
    res = []
    for k, s in enumerate(strokes):
        a = smooth([(x, y, d[y, x]) for (y, x) in s])
        # (y down in the raster → em units, y up from the baseline.)
        em = np.column_stack([(a[:, 0] - g['ox']) / S, (g['oy'] - a[:, 1]) / S, a[:, 2] / S])
        em = rdp(em, 0.004)
        # (A part on its own, small: a dot, a detached bar: drawn once the word's done.)
        late = root(k) != main and size[root(k)] < 0.3 * size[main]
        res.append({'late': bool(late), 'p': [round(float(v), 4) for v in em.flatten()]})
    for dd in dots:
        y = float(sum(p[0] for p in dd)) / len(dd); x = float(sum(p[1] for p in dd)) / len(dd)
        rr = float(max(d[p] for p in dd))
        if rr < 3:
            continue
        cx, cy = (x - g['ox']) / S, (g['oy'] - y) / S
        res.append({'late': True, 'dot': True, 'p': [round(cx - rr / S * 0.3, 4), round(cy, 4), round(rr / S, 4), round(cx + rr / S * 0.3, 4), round(cy, 4), round(rr / S, 4)]})
    out['glyphs'][g['char']] = {'adv': round(g['adv'], 4), 'strokes': res}
json.dump(out, open('strokes.json', 'w'))
n = sum(len(v['strokes']) for v in out['glyphs'].values())
pts = sum(len(s['p']) // 3 for v in out['glyphs'].values() for s in v['strokes'])
print(f"{len(out['glyphs'])} glyphs, {n} strokes, {pts} points")
for c in [c for c in 'Thisxtrendwlu' if c in out['glyphs']]:
    v = out['glyphs'][c]
    print(c, len(v['strokes']), 'strokes', [len(s['p']) // 3 for s in v['strokes']], ['late' if s['late'] else '' for s in v['strokes']])
