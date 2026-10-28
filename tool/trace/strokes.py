"""strokes.py: each glyph's pen strokes, from its raster (glyphs.swift):
thinned to a centre line (Zhang-Suen), cut into a graph (ends, junctions
and the lines between), spurs pruned, then walked the way a hand would
draw it: from the leftmost end, at every fork on along the smoothest way,
lifting the pen only when stuck; a small detached part (a dot, a
crossbar) is "late", drawn once the word's done. → strokes.json (em units,
y up from the baseline; a radius per point).

    python3 tool/trace/strokes.py <work dir>   (glyphs.swift's raster/ and meta.json in it)
"""
import json, math, os, sys
import numpy as np

if len(sys.argv) > 1:
    os.chdir(sys.argv[1])

meta = json.load(open('meta.json'))
S = meta['S']


def thin(img):
    img = img.astype(np.uint8).copy()
    while True:
        changed = False
        for step in (0, 1):
            P = np.pad(img, 1)
            p2, p3, p4, p5 = P[:-2, 1:-1], P[:-2, 2:], P[1:-1, 2:], P[2:, 2:]
            p6, p7, p8, p9 = P[2:, 1:-1], P[2:, :-2], P[1:-1, :-2], P[:-2, :-2]
            nb = [p2, p3, p4, p5, p6, p7, p8, p9]
            B = sum(n.astype(np.int32) for n in nb)
            seq = nb + [p2]
            A = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.int32) for i in range(8))
            if step == 0:
                c = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                c = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            m = (img == 1) & (B >= 2) & (B <= 6) & (A == 1) & c
            if m.any():
                img[m] = 0
                changed = True
        if not changed:
            return img


def depth(img):
    d = np.zeros(img.shape, np.float32)
    cur = img.astype(bool).copy()
    k = 0
    while cur.any():
        k += 1
        d[cur] = k
        P = np.pad(cur, 1)
        cur = cur & P[:-2, 1:-1] & P[2:, 1:-1] & P[1:-1, :-2] & P[1:-1, 2:]
    return d


FOUR = ((-1, 0), (0, 1), (1, 0), (0, -1))
DIAG = ((-1, 1), (1, 1), (1, -1), (-1, -1))


def graph(pix):
    """Each pixel's neighbours: the four sides, and a corner only where no
    side pixel already joins the two (no little triangles)."""
    nb = {}
    for (y, x) in pix:
        out = [(y + dy, x + dx) for dy, dx in FOUR if (y + dy, x + dx) in pix]
        for dy, dx in DIAG:
            q = (y + dy, x + dx)
            if q in pix and (y + dy, x) not in pix and (y, x + dx) not in pix:
                out.append(q)
        nb[p] = out if (p := (y, x)) else out
    return nb


def edges(pix):
    nb = graph(pix)
    nodes = {p for p in pix if len(nb[p]) != 2}
    seen, out = set(), []
    for n in nodes:
        for q in nb[n]:
            if (n, q) in seen:
                continue
            path = [n, q]
            seen.add((n, q))
            prev, cur = n, q
            while cur not in nodes:
                nxt = [r for r in nb[cur] if r != prev]
                if not nxt:
                    break
                prev, cur = cur, nxt[0]
                path.append(cur)
            seen.add((path[-1], path[-2]))
            out.append(path)
    # Loops with no node at all (an o drawn in one go).
    done = {p for e in out for p in e}
    for p in pix:
        if p in done or p in nodes:
            continue
        path, prev, cur = [p], None, p
        while True:
            nxt = [r for r in nb[cur] if r != prev and r not in path[1:]]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            path.append(cur)
            if cur == p:
                break
        done.update(path)
        if len(path) > 3:
            out.append(path)
    return out, nb, nodes


def prune(pix, d):
    """Spurs: a short line from an end to a fork (the thinning's whiskers)."""
    for _ in range(4):
        es, nb, nodes = edges(pix)
        cut = False
        for e in es:
            a, b = e[0], e[-1]
            ends = (len(nb[a]) == 1) + (len(nb[b]) == 1)
            forks = (len(nb[a]) >= 3) + (len(nb[b]) >= 3)
            fork = a if len(nb[a]) >= 3 else b
            if ends == 1 and forks == 1 and len(e) < 1.5 * d[fork] + 2:
                for p in e:
                    if len(nb[p]) < 3:
                        pix.discard(p)
                cut = True
        if not cut:
            break
    return pix


def walk(es, score=lambda p: p[1]):
    """The strokes, as a hand would draw them: from the leftmost free end,
    on along the smoothest continuation at every fork; lifted when stuck."""
    at = {}
    for i, e in enumerate(es):
        at.setdefault(e[0], []).append((i, False))
        at.setdefault(e[-1], []).append((i, True))
    used = [False] * len(es)
    strokes = []
    def heading(path, rev, back=False):
        pts = path[::-1] if rev else path
        k = min(len(pts) - 1, 6)
        if back:
            (y0, x0), (y1, x1) = pts[-1 - k], pts[-1]
        else:
            (y0, x0), (y1, x1) = pts[0], pts[k]
        return math.atan2(y1 - y0, x1 - x0)
    while not all(used):
        # Start: a free end (one line meets it) furthest left, else any.
        cands = []
        for i, e in enumerate(es):
            if used[i]:
                continue
            for rev, p in ((False, e[0]), (True, e[-1])):
                free = len([j for j, _ in at[p] if not used[j]]) == 1
                cands.append((0 if free else 1, score(p), i, rev))
        cands.sort()
        _, _, i, rev = cands[0]
        stroke = []
        while True:
            used[i] = True
            pts = es[i][::-1] if rev else es[i]
            stroke += pts if not stroke else pts[1:]
            end = pts[-1]
            h = heading(es[i], rev, back=True)
            nxt = []
            for j, r in at.get(end, []):
                if used[j]:
                    continue
                # (Leaving from this end: a line ending here runs backwards.)
                h2 = heading(es[j], r)
                turn = abs((h2 - h + math.pi) % (2 * math.pi) - math.pi)
                nxt.append((turn, j, r))
            if not nxt:
                break
            nxt.sort()
            if nxt[0][0] > 2.4:   # (A hairpin: lift rather than double back.)
                break
            _, i, rev = nxt[0]
        strokes.append(stroke)
    return strokes


def smooth(pts, k=3):
    a = np.array(pts, float)
    if len(a) < 2 * k + 2:
        return a
    out = a.copy()
    for i in range(k, len(a) - k):
        out[i] = a[i - k:i + k + 1].mean(axis=0)
    return out


def rdp(a, eps):
    if len(a) < 3:
        return a
    p, q = a[0, :2], a[-1, :2]
    v = q - p
    n = np.hypot(*v)
    dists = np.abs(v[0] * (a[1:-1, 1] - p[1]) - v[1] * (a[1:-1, 0] - p[0])) / n if n > 0 else np.hypot(*(a[1:-1, :2] - p).T)
    i = int(np.argmax(dists)) + 1
    if dists[i - 1] > eps:
        return np.vstack([rdp(a[:i + 1], eps)[:-1], rdp(a[i:], eps)])
    return np.vstack([a[0], a[-1]])


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
    # (Left and high first: an ascender's top before the end of its tail.)
    strokes = walk(es, score=lambda p: (p[1] - g['ox']) / S - 0.6 * (g['oy'] - p[0]) / S)
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
        if x0 - x1 > 0.15 * S and (g['oy'] - y0) / S < 1.25 * meta['xHeight']:
            strokes[0] = strokes[0][::-1]
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
for c in 'Thisxtrendwlu':
    v = out['glyphs'][c]
    print(c, len(v['strokes']), 'strokes', [len(s['p']) // 3 for s in v['strokes']], ['late' if s['late'] else '' for s in v['strokes']])
