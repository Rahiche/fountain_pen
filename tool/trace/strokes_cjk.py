"""strokes_cjk.py: Japanese glyphs' pen strokes (kana, kanji, their
punctuation), from cjk_glyphs.swift's outlines → strokes.json, as strokes.py
writes it (em units, y up from the baseline, a radius per point; the strokes
in the order they're written).

Each outline is thinned on its own, so strokes that cross never meet; its
centre line runs straight on through its own forks and is cut at its
corners. Then the pieces are put together the way a hand moves the pen: a
stroke only ever runs right, down, or down and out to a side, until a last
hook or flick. An outline that would need the pen to run back (a box's
frame, drawn in one) is cut into strokes that don't; outlines that meet end
to start at a corner (a hook drawn as two) are one stroke. Kana are
freer: each outline is a stroke, begun from its top left.

Then the strokes are put in the order a Japanese hand is taught (筆順): see
order().

    python3 tool/trace/strokes_cjk.py <work dir>
"""
import json, math, os, sys, unicodedata
import numpy as np
from skeleton import depth, edges, prune, rdp, smooth, thin

DEG = math.pi / 180
SCALE = 256  # (px to the em in the rasters: set from meta.json)
HOOK = 0.25  # (a stroke's last bend this short, any way: a hook)
UP_DOWN = False  # (whether a stroke may run up and then down: katakana's ヘ)


def kind(c):
    o = ord(c)
    if 0x3041 <= o <= 0x309F:
        return 'kana'
    if 0x30A0 <= o <= 0x30FF and c not in 'ー・':
        return 'kata'
    if 0x4E00 <= o <= 0x9FFF or 0x3400 <= o <= 0x4DBF or 0xF900 <= o <= 0xFAFF or c == '々':
        return 'kanji'
    return 'free'


# ── An outline's centre line, as chains ─────────────────────────────────

def speck(img, d, sh, S):
    """A dot too small to thin to a line: along its longest way."""
    ys, xs = np.nonzero(img)
    if len(xs) == 0:
        return None
    pts = np.column_stack([xs, ys]).astype(float)
    c = pts.mean(0)
    _, sv, vt = np.linalg.svd(pts - c, full_matrices=False)
    ax = vt[0] * max(1.0, (sv[0] / math.sqrt(len(pts))) * 1.2)
    r = float(d.max())
    a, b = c - ax, c + ax
    ox, oy = sh['ox'], sh['oy']
    return np.array([((a[0] - ox) / S, (oy - a[1]) / S, r / S), ((b[0] - ox) / S, (oy - b[1]) / S, r / S)])


# Kana whose vertical the font draws with the next stroke growing out of it.
FOOT = set('れ')


def kana_strokes(shapes, imgs, S, char=''):
    """A kana's strokes. Outlines that carry one stroke on (one tapers away
    inside the other: ね's loop out of its slant, ひ's flick, む's loop) are
    walked as one; outlines that only cross stay apart."""
    n = len(shapes)
    walks = [pen_walk(imgs[k], sh, S, char in FOOT) for k, sh in enumerate(shapes)]
    deep = [depth(im) for im in imgs]
    parent = list(range(n))

    def root(k):
        while parent[k] != k:
            k = parent[k]
        return k

    def along(q, j):
        v = q[min(len(q) - 1, j + 5), :2] - q[max(0, j - 5), :2]
        return v / (np.hypot(*v) + 1e-9)

    bridges = []  # (end, nearest point on the other outline's line, radius), in em
    for a in range(n):
        for p, closed in walks[a]:
            if closed or len(p) < 3:
                continue
            for end, tan in ((p[0], along(p, 3)), (p[-1], along(p, len(p) - 4))):
                if end[2] >= 0.016:
                    continue
                best = None
                for b in range(n):
                    lines = [q for q, _ in walks[b]]
                    if b == a or not lines:
                        continue
                    sh = shapes[b]
                    x, y = int(round(end[0] * S + sh['ox'])), int(round(sh['oy'] - end[1] * S))
                    inside = 0 <= y < sh['h'] and 0 <= x < sh['w'] and deep[b][y, x] >= 2
                    q, j = min(((q, int(np.argmin(np.hypot(*(q[:, :2] - end[:2]).T)))) for q in lines),
                               key=lambda c: float(np.hypot(*(c[0][c[1], :2] - end[:2]))))
                    gap = float(np.hypot(*(q[j, :2] - end[:2])))
                    fit = abs(float(along(q, j) @ tan))
                    tip = min(float(np.hypot(*(q[0, :2] - end[:2]))), float(np.hypot(*(q[-1, :2] - end[:2]))))
                    run = float(np.sum(np.hypot(*np.diff(q[:, :2], axis=0).T)))
                    straight = run > 0.45 and float(np.hypot(*(q[-1, :2] - q[0, :2]))) > 0.98 * run
                    if inside and (tip < 0.08 or (fit > 0.95 and not straight)):
                        c = (2 + fit, b, None)  # (carries on inside it)
                    elif not inside and gap < 0.12 and fit > 0.85:
                        c = (fit, b, (end[:2], q[j, :2], max(end[2], 0.012)))  # (just short of it)
                    else:
                        continue
                    if best is None or c[0] > best[0]:
                        best = c
                if best is not None:
                    parent[root(a)] = root(best[1])
                    if best[2] is not None:
                        bridges.append((a, best[2]))
    groups = {}
    for k in range(n):
        groups.setdefault(root(k), []).append(k)
    out = []
    for k, ks in groups.items():
        if len(ks) == 1:
            out += [free_stroke(p, closed, k) for p, closed in walks[k]]
            continue
        # The outlines together, on one raster.
        x0 = min(-shapes[j]['ox'] for j in ks)
        y0 = min(-shapes[j]['oy'] for j in ks)
        x1 = max(shapes[j]['w'] - shapes[j]['ox'] for j in ks)
        y1 = max(shapes[j]['h'] - shapes[j]['oy'] for j in ks)
        w, h = int(math.ceil(x1 - x0)) + 1, int(math.ceil(y1 - y0)) + 1
        img = np.zeros((h, w), bool)
        for j in ks:
            dx, dy = int(round(-shapes[j]['ox'] - x0)), int(round(-shapes[j]['oy'] - y0))
            hh, ww = imgs[j].shape
            img[dy:dy + hh, dx:dx + ww] |= imgs[j]
        sh = {'ox': -x0, 'oy': -y0, 'w': w, 'h': h}
        # (Bridged across where one stops just short of the other.)
        yy, xx = np.mgrid[0:h, 0:w]
        for a, (pa, pb, r) in bridges:
            if a not in ks:
                continue
            (ax_, ay_), (bx_, by_) = [(u[0] * S + sh['ox'], sh['oy'] - u[1] * S) for u in (pa, pb)]
            vx, vy = bx_ - ax_, by_ - ay_
            t = np.clip(((xx - ax_) * vx + (yy - ay_) * vy) / max(vx * vx + vy * vy, 1e-9), 0, 1)
            img |= np.hypot(xx - ax_ - t * vx, yy - ay_ - t * vy) <= r * S
        out += [free_stroke(p, closed, k) for p, closed in pen_walk(img, sh, S, char in FOOT)]
    return out


def free_join(strokes):
    """Kana outlines that meet end to end (a hook drawn as its own): one stroke."""
    joined = True
    while joined:
        joined = False
        for a in strokes:
            for b in strokes:
                if a is b:
                    continue
                tol = 1.6 * (a.p[-1, 2] + b.p[0, 2]) + 0.015
                if length(a) < 0.15 and length(b) < 0.15:
                    continue  # (゛'s two ticks: two strokes)
                for q in (b.p, b.p[::-1]):
                    if np.hypot(*(a.p[-1, :2] - q[0, :2])) > tol:
                        continue
                    if any(c is not a and c is not b and min(np.hypot(*(c.p[0, :2] - a.p[-1, :2])),
                                                             np.hypot(*(c.p[-1, :2] - a.p[-1, :2]))) < tol for c in strokes):
                        continue
                    strokes.remove(b)
                    strokes[strokes.index(a)] = free_stroke(np.vstack([a.p, q[1:]]), False, a.piece)
                    joined = True
                    break
                if joined:
                    break
            if joined:
                break
    return strokes

class Graph:
    """An outline's centre line as a graph: its lines, and the forks they meet
    at (forks close together, as a crossing thins, are one), each line's
    ends there and which way it leaves."""
    def __init__(self, img, sh, S):
        self.S, self.sh = S, sh
        d = self.d = depth(img)
        sk = thin(img)
        pix = set(zip(*np.nonzero(sk)))
        self.dot = None
        self.es = []
        if not pix:
            return
        pix = prune(pix, d)
        es, nb, nodes = edges(pix)
        es = self.es = [e for e in es if len(e) >= 2]
        if not es:
            self.dot = speck(img, d, sh, S)
            return
        deg = self.deg = {p: len(nb[p]) for p in nodes}
        parent = {p: p for p in nodes}

        def root(p):
            while parent[p] != p:
                parent[p] = parent[parent[p]]
                p = parent[p]
            return p

        internal = self.internal = set()
        for i, e in enumerate(es):
            a, b = e[0], e[-1]
            if a in deg and b in deg and deg[a] >= 3 and deg[b] >= 3 and a != b and len(e) <= 2 * max(d[a], d[b]) + 3:
                parent[root(a)] = root(b)
                internal.add(i)
        self.root = root
        members = self.members = {}
        for p in nodes:
            members.setdefault(root(p), []).append(p)
        centre = {k: np.mean(np.array(v, float), axis=0) for k, v in members.items()}
        ports = self.ports = {}
        for i, e in enumerate(es):
            if i in internal:
                continue
            for s, end in ((0, e[0]), (1, e[-1])):
                if end not in deg:
                    continue
                k = root(end)
                path = e if s == 0 else e[::-1]
                far = path[min(len(path) - 1, int(2.5 * d[end]) + 2)]
                v = np.array(far, float) - centre[k]
                ports.setdefault(k, []).append(((i, s), math.atan2(v[0], v[1])))
        self.ends = {p for p in deg if deg[p] == 1}

    def em(self, path):
        ox, oy, S, d = self.sh['ox'], self.sh['oy'], self.S, self.d
        return np.array([((x - ox) / S, (oy - y) / S, d[y, x] / S) for (y, x) in path])

    def far_end(self, i, s):
        """Where line i leads, leaving from its end s."""
        return self.es[i][-1] if s == 0 else self.es[i][0]


def chains(img, sh, S):
    """The outline's centre line: chains of (x, y, r) in em (y up), each
    run straight on through the forks it passes; closed if a loop."""
    g = Graph(img, sh, S)
    if g.dot is not None:
        return [(g.dot, False)]
    if not g.es:
        return []
    es, d, ports, internal = g.es, g.d, g.ports, g.internal
    pair = {}
    # A whisker into a sharp turn (a box's corner run on past): a short dead
    # end at a fork of three. Dropped, the turn runs on round it.
    for k, ps in ports.items():
        if len(ps) != 3:
            continue
        dk = max(d[q] for q in g.members[k])
        spurs = [(i, s) for (i, s), _ in ps if g.far_end(i, s) in g.ends and len(es[i]) < 3.2 * dk + 4]
        if len(spurs) != 1:
            continue
        internal.add(spurs[0][0])
        (pa, _), (pb, _) = [pp for pp in ps if pp[0] != spurs[0]]
        pair[pa], pair[pb] = pb, pa
    for k, ps in ports.items():
        if len(ps) < 3 or any(pp[0] in pair for pp in ps):
            continue
        cand = []
        for a in range(len(ps)):
            for b in range(a + 1, len(ps)):
                if ps[a][0][0] == ps[b][0][0]:
                    continue
                dev = abs(abs((ps[a][1] - ps[b][1] + math.pi) % (2 * math.pi) - math.pi) - math.pi)
                cand.append((dev, a, b))
        cand.sort()
        for dev, a, b in cand:
            if dev > 50 * DEG:
                break
            pa, pb = ps[a][0], ps[b][0]
            if pa in pair or pb in pair:
                continue
            pair[pa], pair[pb] = pb, pa
    used = set(internal)
    out = []
    start = None

    def run(i, s):
        path = []
        closed = False
        while True:
            used.add(i)
            e = es[i] if s == 0 else es[i][::-1]
            path += e if not path else e[1:]
            q = pair.get((i, 1 - s))
            if q is None:
                break
            if q[0] in used:
                closed = q[0] == start
                break
            i, s = q
        return path, closed

    for k, ps in sorted(ports.items()):
        for (i, s), _ in ps:
            if i in used or (i, s) in pair:
                continue
            start = i
            path, _ = run(i, s)
            out.append((g.em(path), False))
    for i in range(len(es)):
        if i not in used:
            start = i
            path, closed = run(i, 0)
            closed = closed or (len(path) > 4 and abs(path[0][0] - path[-1][0]) + abs(path[0][1] - path[-1][1]) <= 3)
            out.append((g.em(path), closed))
    return [(c, cl) for c, cl in out if len(c) >= 2]


def pen_walk(img, sh, S, foot=False):
    """A kana's outline as a pen draws it: from its top-left end, on along
    the line. Where a fork has a dead end (a turn back the font drew as a
    branch: ろ ん そ), out to its tip and back first, the shorter first; else
    on the smoothest way. Lifted only when there's nowhere left to go. (With
    foot: a vertical running straight on down past a branch ends at its
    foot, as れ's does.)"""
    g = Graph(img, sh, S)
    if g.dot is not None:
        return [(g.dot, False)]
    if not g.es:
        return []
    es, ports = g.es, g.ports
    live = [i for i in range(len(es)) if i not in g.internal]
    at = {}
    for k, ps in ports.items():
        for (i, s), ang in ps:
            at.setdefault(k, []).append((i, s, ang))
    score = lambda q: q[0] + 0.5 * q[1]  # (top left first: rows down, columns across)
    used = set(g.internal)
    out = []
    while any(i not in used for i in live):
        # Start: a free end, top left first; else (a loop) its top.
        free = [(score(g.far_end(i, 1 - s)), i, s) for i in live if i not in used for s in (0, 1)
                if (es[i][0] if s == 0 else es[i][-1]) in g.ends]
        if free:
            _, i, s = min(free)
        else:
            i = next(j for j in live if j not in used)
            s = 0
        path = []
        heading = None
        while True:
            used.add(i)
            e = es[i] if s == 0 else es[i][::-1]
            path += e if not path else e[1:]
            end = e[-1]
            if end not in g.deg:
                break
            k = g.root(end)
            v = np.array(e[-1], float) - np.array(e[max(0, len(e) - 1 - int(2.5 * g.d[end]) - 2)], float)
            heading = math.atan2(v[0], v[1])
            nxt = [(j, t, ang) for j, t, ang in at.get(k, []) if j not in used]
            if not nxt:
                break
            dead = sorted((len(es[j]), j, t) for j, t, _ in nxt
                          if g.far_end(j, t) in g.ends and len(es[j]) < 0.45 * g.S)
            turn = lambda ang: abs((ang - heading + math.pi) % (2 * math.pi) - math.pi)
            down = abs(heading - math.pi / 2) < 20 * DEG  # (rows down: straight down the page)
            on = [j for j, t, ang in nxt if turn(ang) < 25 * DEG]
            loops = any(g.root(g.far_end(j, t)) == k for j, t, _ in nxt if j not in on)
            if foot and dead and down and on and not loops and any(j == on[0] for _, j, _ in dead):
                # A vertical running straight on down past a branch (れ's): it
                # ends at its foot; the branch is another stroke.
                i, s = on[0], next(t for j, t, _ in nxt if j == on[0])
                continue
            if dead and len(nxt) >= 2:
                # Out to the tip and back.
                _, j, t = dead[0]
                tail = es[j] if t == 0 else es[j][::-1]
                path += tail[1:] + tail[::-1][1:]
                used.add(j)
                rest = [(j2, t2, ang) for j2, t2, ang in nxt if j2 != j]
                if len(rest) == 1:
                    i, s = rest[0][0], rest[0][1]
                    continue
                nxt = rest
                v = np.array(tail[0], float) - np.array(tail[min(len(tail) - 1, 6)], float)
                heading = math.atan2(v[0], v[1])
            j, t, _ = min(nxt, key=lambda c: turn(c[2]))
            i, s = j, t
        p = g.em(path)
        closed = len(path) > 8 and abs(path[0][0] - path[-1][0]) + abs(path[0][1] - path[-1][1]) <= 3
        out.append((p, closed))
    return [(c, cl) for c, cl in out if len(c) >= 2]


# ── Corners, segments, and strokes a pen can draw ───────────────────────

def corners(p, closed):
    """Where the line turns sharply (not where it curves)."""
    n = len(p)
    r = float(np.median(p[:, 2]))
    w = max(3, int(round(1.6 * r * SCALE)) + 1)
    w = min(w, max(2, n // 3)) if not closed else w
    turn = np.zeros(n)
    for i in range(n):
        a, b = i - w, i + w
        if not closed and (a < 0 or b >= n):
            continue
        v1 = p[i, :2] - p[a % n, :2]
        v2 = p[b % n, :2] - p[i, :2]
        n1, n2 = np.hypot(*v1), np.hypot(*v2)
        if n1 == 0 or n2 == 0:
            continue
        turn[i] = math.acos(max(-1, min(1, float(v1 @ v2) / (n1 * n2))))
    cs = []
    for i in range(n):
        if turn[i] < 48 * DEG:
            continue
        lo, hi = i - w, i + w + 1
        window = [turn[j % n] for j in range(lo, hi)] if closed else turn[max(0, lo):hi]
        if turn[i] >= max(window) - 1e-9 and (not cs or i - cs[-1] > w):
            cs.append(i)
    return cs


def orient(v):
    a = math.degrees(math.atan2(v[1], v[0])) % 180
    if a < 20 or a > 160:
        return 'H'
    if 68 < a < 112:
        return 'V'
    return '/' if a < 90 else '\\'


class Seg:
    def __init__(self, p):
        self.p = p
        self.v = p[-1, :2] - p[0, :2]
        self.L = float(np.sum(np.hypot(*np.diff(p[:, :2], axis=0).T))) if len(p) > 1 else 0.0
        self.o = orient(self.v)

    def flipped(self):
        return Seg(self.p[::-1])


def forward(s):
    o, v = s.o, s.v
    if o == 'H':
        return v[0] > 0
    return v[1] < 0


# The turns a stroke makes (横折 横撇 竖折 撇折 撇点; and on round a curve).
TURNS = {('H', 'V'), ('H', '/'), ('V', 'H'), ('/', 'H'), ('/', '\\'), ('H', '\\')}


def valid(segs):
    """Whether a pen draws these in one stroke: on right, down, or down and
    out to a side, turning only as strokes do; last, maybe a short hook or
    a flick up to the right (and a rise into that hook)."""
    for k, s in enumerate(segs):
        last = k == len(segs) - 1
        hook = last and k > 0 and s.L < min(HOOK, 0.6 * segs[k - 1].L)
        rising = s.o in '/H' and s.v[0] > 0 and s.v[1] >= 0
        if k > 0 and not hook and (segs[k - 1].o, s.o) not in TURNS and not (last and rising and s.o == '/'):
            return False
        if forward(s) or hook:
            continue
        if rising and (last or (k == len(segs) - 2 and segs[-1].L < HOOK)):
            continue  # (a flick up and right: 提; or the rise into a last hook)
        if UP_DOWN and rising and k == 0 and len(segs) == 2 and segs[1].o == '\\' and segs[1].v[1] < 0:
            continue  # (up, then down: katakana's ヘ; not a kanji's roof, 𠆢, two strokes)
        if rising and k == 0 and len(segs) >= 2 and segs[1].o == 'H' and segs[1].v[0] > 0:
            continue  # (up a little, then on out to the right: 辶's sweep)
        return False
    return True


def segments(p, closed):
    cs = corners(p, closed)
    if closed:
        if not cs:
            return [Seg(p)], []
        q = np.vstack([p[cs[0]:], p[1:cs[0] + 1]])
        cs = [c - cs[0] for c in cs[1:]]
        p = q
    cuts = [0] + cs + [len(p) - 1]
    segs = [Seg(p[cuts[k]:cuts[k + 1] + 1]) for k in range(len(cuts) - 1) if cuts[k + 1] > cuts[k]]
    # (A hook that curls in two bends is one hook.)
    while len(segs) >= 3 and segs[-1].L < 0.14 and segs[-2].L < 0.14 and segs[-1].L + segs[-2].L < HOOK:
        segs[-2:] = [Seg(np.vstack([segs[-2].p, segs[-1].p[1:]]))]
    return segs, cs


def partition(segs, box):
    """The fewest strokes the chain's segments make, each one a pen can
    draw, in its direction. (In a box, a down stroke doesn't turn along
    the bottom: the bottom is its own stroke, drawn last.)"""
    n = len(segs)
    best = [(math.inf, None)] * (n + 1)
    best[0] = (0, None)
    for j in range(1, n + 1):
        for i in range(j):
            if best[i][0] == math.inf:
                continue
            sub = segs[i:j]
            for rev in (False, True):
                ss = [s.flipped() for s in reversed(sub)] if rev else sub
                if not valid(ss):
                    continue
                if box and any(a.o == 'V' and b.o == 'H' for a, b in zip(ss, ss[1:])):
                    continue
                cost = best[i][0] + 1
                if cost < best[j][0]:
                    best[j] = (cost, (i, rev))
    if best[n][0] == math.inf:
        return None
    out, j = [], n
    while j > 0:
        i, rev = best[j][1]
        sub = segs[i:j]
        out.append([s.flipped() for s in reversed(sub)] if rev else sub)
        j = i
    return out[::-1]


class Stroke:
    def __init__(self, segs, piece):
        self.segs = segs
        self.piece = piece
        self.p = np.vstack([segs[0].p] + [s.p[1:] for s in segs[1:]])

    @property
    def start(self):
        return self.p[0, :2]

    @property
    def end(self):
        return self.p[-1, :2]


def taper_end(p, ratio=0.8):
    """Which end is the finer (a sweep's tail): -1 the start, 1 the end, 0 neither."""
    n = len(p)
    if n < 6:
        return 0
    k = max(2, n // 5)
    a, b = float(np.mean(p[1:k + 1, 2])), float(np.mean(p[-k - 1:-1, 2]))
    if b < ratio * a:
        return 1
    if a < ratio * b:
        return -1
    return 0


def pen_strokes(pieces, mode):
    """The glyph's strokes, each a pen's run in the direction it's drawn."""
    strokes = []
    for k, chs in enumerate(pieces):
        for p, closed in chs:
            if mode == 'free':
                strokes.append(free_stroke(p, closed, k))
                continue
            segs, _ = segments(p, closed)
            if closed and len(segs) > 1:
                parts = None
                for c in range(len(segs)):
                    rot = segs[c:] + segs[:c]
                    got = partition(rot, True)
                    if got is not None and (parts is None or len(got) < len(parts)):
                        parts = got
            else:
                parts = partition(segs, False)
            if parts is None:
                parts = [[s if forward(s) else s.flipped()] for s in segs]
            for ss in parts:
                strokes.append(Stroke(ss, k))
    if mode == 'free':
        return strokes
    # A lone slant: a flick up to the right (提) if it's long and shallow from
    # the very bottom (シ ン), or short at the bottom left (氵 冫 扌 土); else a
    # sweep down and to the left (ノ: イ オ ソ ツ). (Not by which end tapers:
    # a sweep's slanting cut thins its line where it starts.)
    for st in strokes:
        if len(st.segs) == 1 and st.segs[0].o == '/':
            s = st.segs[0]
            lo = s.p[0] if s.p[0, 1] < s.p[-1, 1] else s.p[-1]
            ang = math.degrees(math.atan2(abs(s.v[1]), abs(s.v[0])))
            flick = ang < 25 or (s.L >= 0.5 and ang < 39 and lo[1] < 0.1) or \
                (s.L < 0.5 and lo[0] < 0.3 and lo[1] < 0.35 and ang < 65)
            if flick != (s.v[1] > 0):
                st.__init__([s.flipped()], st.piece)
    # Pieces that meet end to start at a corner: one stroke (a hook drawn
    # as two outlines, a turn along a bottom: 山's, though its side runs on
    # a little below; not a box's, whose bottom is drawn last).
    def side_of_box(a):
        return any(c is not a and len(c.segs) >= 2 and c.segs[0].o == 'H' and c.segs[1].o in 'V/' and
                   np.hypot(*(c.start - a.start)) < 0.06 for c in strokes)

    joined = True
    while joined:
        joined = False
        for a in strokes:
            for b in strokes:
                if a is b or a.piece == b.piece:
                    continue
                ra, rb = a.p[-1, 2], b.p[0, 2]
                tol = 1.6 * (ra + rb) + 0.01
                if a.segs[-1].o in 'V/' and b.segs[0].o == 'H' and len(b.segs) == 1:
                    # (A slant's bar may run on a little to its left: ム's.)
                    lead = 0.15 if a.segs[-1].o == '/' else 0.03
                    if not -lead < b.start[0] - a.end[0] < tol or not -0.06 < b.start[1] - a.end[1] < 0.14 or side_of_box(a):
                        continue
                elif np.hypot(*(a.end - b.start)) > tol:
                    continue
                va, vb = a.segs[-1].v, b.segs[0].v
                ang = math.acos(max(-1, min(1, float(va @ vb) / (np.hypot(*va) * np.hypot(*vb) + 1e-9))))
                if ang < 35 * DEG or not valid(a.segs + b.segs):
                    continue
                # (Not where a third stroke also starts or ends: a junction, not a turn.)
                if any(c is not a and c is not b and min(np.hypot(*(c.start - a.end)), np.hypot(*(c.end - a.end))) < 0.6 * tol
                       for c in strokes):
                    continue
                strokes.remove(b)
                a.__init__(a.segs + b.segs, a.piece)
                joined = True
                break
            if joined:
                break
    return strokes


class Free:
    """A kana's stroke: begun from its top-left end."""
    def __init__(self, p, piece):
        self.p = p
        self.piece = piece
        self.segs = [Seg(p)]

    start = Stroke.start
    end = Stroke.end


def free_stroke(p, closed, k):
    if closed:
        # A loop: from its top, on round to the left.
        i = int(np.argmax(p[:, 1]))
        q = np.vstack([p[i:], p[1:i + 1]])
        if len(q) > 3 and q[3, 0] > q[0, 0]:
            q = q[::-1]
        return Free(q, k)
    score = lambda pt: -pt[1] + 0.5 * pt[0]
    return Free(p if score(p[0]) <= score(p[-1]) else p[::-1], k)


# ── Order (筆順) ─────────────────────────────────────────────────────────

def seg_cross(a0, a1, b0, b1):
    d = (a1[0] - a0[0]) * (b1[1] - b0[1]) - (a1[1] - a0[1]) * (b1[0] - b0[0])
    if abs(d) < 1e-12:
        return None
    t = ((b0[0] - a0[0]) * (b1[1] - b0[1]) - (b0[1] - a0[1]) * (b1[0] - b0[0])) / d
    u = ((b0[0] - a0[0]) * (a1[1] - a0[1]) - (b0[1] - a0[1]) * (a1[0] - a0[0])) / d
    if 0 <= t <= 1 and 0 <= u <= 1:
        return a0 + (a1 - a0) * t
    return None


def crossing(a, b):
    """Where a's line crosses b's, away from both their ends; else None."""
    pa, pb = a.p[:, :2], b.p[:, :2]
    tol = max(float(np.median(a.p[:, 2])), float(np.median(b.p[:, 2]))) + 0.012
    for i in range(len(pa) - 1):
        for j in range(len(pb) - 1):
            x = seg_cross(pa[i], pa[i + 1], pb[j], pb[j + 1])
            if x is None:
                continue
            if min(np.hypot(*(x - a.start)), np.hypot(*(x - a.end)), np.hypot(*(x - b.start)), np.hypot(*(x - b.end))) > tol:
                return x
    return None


def dist_to(p, s):
    q = s.p[:, :2]
    best = math.inf
    for i in range(len(q) - 1):
        a, b = q[i], q[i + 1]
        v = b - a
        t = 0.0 if not v.any() else max(0.0, min(1.0, float((p - a) @ v) / float(v @ v)))
        best = min(best, float(np.hypot(*(a + v * t - p))))
    return best


def flat(s):
    g = s.segs[0]
    return g.o == 'H' and abs(g.v[1]) < 0.2 * abs(g.v[0])


def bar(s):
    """Whether a stroke sets off as a crossbar: right, level or rising a little
    (也's, セ's, more if it turns on down)."""
    g = s.segs[0]
    ang = math.degrees(math.atan2(g.v[1], g.v[0]))
    return g.v[0] > 0 and -20 < ang < (32 if len(s.segs) > 1 else 15)


def box(s):
    return s.p[:, 0].min(), s.p[:, 1].min(), s.p[:, 0].max(), s.p[:, 1].max()


def cut(ids, strokes, axis):
    """Ids split where nothing straddles a line across (axis 0: a vertical
    line, left part first; 1: a horizontal one, top part first)."""
    spans = []
    for i in ids:
        x0, y0, x1, y1 = box(strokes[i])
        spans.append(((x0, x1) if axis == 0 else (-y1, -y0), i))
    spans.sort()
    reach = -math.inf
    tol = 0.012
    for k, ((a, b), i) in enumerate(spans):
        if k > 0 and a > reach - tol:
            first = [j for _, j in spans[:k]]
            rest = [j for _, j in spans[k:]]
            # (Not a lone dot cut off on its own: 心's dots belong to it.)
            lone = any(len(side) == 1 and length(strokes[side[0]]) < 0.45 for side in (first, rest))
            if not lone and not any(near(strokes[x], strokes[y], 0.03) for x in first for y in rest):
                return first, rest
        reach = max(reach, b)
    return None


def length(s):
    return float(np.sum(np.hypot(*np.diff(s.p[:, :2], axis=0).T)))


def near(a, b, tol):
    """Whether two strokes come within tol of one another."""
    pa, pb = a.p[::3, :2], b.p[::3, :2]
    d = np.hypot(pa[:, None, 0] - pb[None, :, 0], pa[:, None, 1] - pb[None, :, 1])
    return float(d.min()) < tol + float(np.median(a.p[:, 2])) + float(np.median(b.p[:, 2]))


def order(strokes, char):
    n = len(strokes)
    if n <= 1:
        return list(range(n))
    # A voiced mark (゛ ゜) comes once the kana's written: its small strokes at
    # the top right, left one first.
    marks = []
    if len(unicodedata.normalize('NFD', char)) > 1 and kind(char) in ('kana', 'kata'):
        marks = sorted((i for i, s in enumerate(strokes) if box(s)[0] > 0.55 and box(s)[1] > 0.45 and length(s) < 0.3),
                       key=lambda i: box(strokes[i])[0])
    rest = [i for i in range(n) if i not in marks]
    sub = [strokes[i] for i in rest]
    if kind(char) == 'kana' or kind(char) == 'free':
        got = order_kana(sub)
    else:
        got = arrange(list(range(len(sub))), sub)
    return [rest[i] for i in got] + marks


def heading(s, along=0.15):
    """Which way a stroke sets off: its line over its first stretch."""
    q = s.p[:, :2]
    run = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(q, axis=0).T))])
    j = int(np.searchsorted(run, min(along, run[-1])))
    return q[min(j, len(q) - 1)] - q[0]


def order_kana(st):
    """Top first, then left, by where each starts; a stroke that sets off
    across another (あ お か す た は ま) before it."""
    n = len(st)
    after = {i: set() for i in range(n)}
    for a in range(n):
        for b in range(n):
            if a == b or crossing(st[a], st[b]) is None:
                continue
            v = heading(st[a])
            if abs(v[1]) < 0.4 * abs(v[0]) and v[0] > 0:
                after[b].add(a)
    done, out = set(), []
    while len(out) < n:
        ready = [i for i in range(n) if i not in done and after[i] <= done] or [i for i in range(n) if i not in done]
        i = min(ready, key=lambda j: key(st[j]))
        out.append(i)
        done.add(i)
    return out


def key(s):
    # Top first, then left: from where it starts.
    return -s.start[1] + 0.45 * s.start[0]


def arrange(ids, st):
    if len(ids) <= 1:
        return ids
    # Centre first: a tall stroke down the middle, small ones either side (小, 水).
    mid = centre_first(ids, st)
    if mid is not None:
        rest = [i for i in ids if i != mid]
        left = [i for i in rest if box(st[i])[2] <= box(st[mid])[0] + 0.03]
        right = [i for i in rest if i not in left]
        return [mid] + arrange(left, st) + arrange(right, st)
    wrap = sweep(ids, st)
    if wrap is not None:
        return wrap
    for axis in (0, 1):
        c = cut(ids, st, axis)
        if c is not None:
            return arrange(c[0], st) + arrange(c[1], st)
    wrap = frame(ids, st)
    if wrap is not None:
        return wrap
    return interlock(ids, st)


def centre_first(ids, st):
    if len(ids) < 3:
        return None
    x0 = min(box(st[i])[0] for i in ids)
    x1 = max(box(st[i])[2] for i in ids)
    for m in ids:
        s = st[m]
        if s.segs[0].o != 'V':
            continue
        bx = box(s)
        h = bx[3] - bx[1]
        cx = (bx[0] + bx[2]) / 2
        if abs(cx - (x0 + x1) / 2) > 0.12 * (x1 - x0) or h < 0.5:
            continue
        others = [i for i in ids if i != m]
        if any(crossing(s, st[i]) is not None for i in others):
            return None
        lefts = [i for i in others if box(st[i])[2] <= bx[0] + 0.03]
        rights = [i for i in others if box(st[i])[0] >= bx[2] - 0.03]
        if lefts and rights and len(lefts) + len(rights) == len(others) and \
                all(box(st[i])[3] - box(st[i])[1] < 0.75 * h for i in others):
            return m
    return None


def sweep(ids, st):
    """辶 and 廴: what they carry first, then them; 走 and its kin (起): they
    come first."""
    S = {i: st[i] for i in ids}
    # 辶 / 廴: a long sweep from the lower left out along the bottom.
    xs0 = min(box(s)[0] for s in S.values())
    xs1 = max(box(s)[2] for s in S.values())
    ys0 = min(box(s)[1] for s in S.values())
    ys1 = max(box(s)[3] for s in S.values())
    W = xs1 - xs0
    for i, s in S.items():
        bx = box(s)
        tail = s.p[int(len(s.p) * 0.55):]
        if s.start[0] < xs0 + 0.35 * W and s.start[1] < ys0 + 0.7 * (ys1 - ys0) and \
                bx[2] > xs1 - 0.12 * W and bx[1] < ys0 + 0.12 and s.end[0] > xs0 + 0.7 * W and s.end[1] < ys0 + 0.15 and \
                len(tail) > 1 and tail[-1, 0] - tail[0, 0] > 0.35 * W and abs(tail[-1, 1] - tail[0, 1]) < 0.25:
            left = [j for j in ids if j != i and box(st[j])[2] < xs0 + 0.36 * W]
            inner = [j for j in ids if j != i and j not in left]
            run = float(np.sum(np.hypot(*np.diff(s.p[:, :2], axis=0).T)))
            if float(np.hypot(*(s.end - s.start))) > 0.97 * run or not left or \
                    max(box(st[j])[3] for j in left) - min(box(st[j])[1] for j in left) < 0.4 * (ys1 - ys0):
                continue
            if inner and 1 <= len(left) <= 2:
                return arrange(inner, st) + sorted(left, key=lambda j: key(st[j])) + [i]
            if inner and len(left) > 2:
                return arrange(left, st) + [i] + arrange(inner, st)
    return None


def frame(ids, st):
    """A box's frame (口 冂 円 月), the outermost: its left side, then its top
    and right, then what's inside, then its bottom; what's above it before,
    the rest after."""
    found = []
    for a in ids:
        A = st[a]
        if A.segs[0].o not in 'V/' or A.segs[0].v[1] >= 0:
            continue
        ha = box(A)[3] - box(A)[1]
        if ha < 0.08:
            continue
        for b in ids:
            B = st[b]
            if b == a or len(B.segs) < 2 or B.segs[0].o != 'H' or B.segs[1].o not in 'V/':
                continue
            if np.hypot(*(A.start - B.start)) > 0.06:
                continue
            fx0, fx1 = box(A)[0], box(B)[2]
            ftop, fbot = max(A.start[1], B.start[1]), min(box(A)[1], box(B)[1])
            inside, bottom, above, rest = [], [], [], []
            for c in ids:
                if c in (a, b):
                    continue
                C = st[c]
                cx0, cy0, cx1, cy1 = box(C)
                if C.segs[0].o == 'H' and len(C.segs) == 1 and abs(cy0 - fbot) < 0.07 and \
                        dist_to(C.start, A) < 0.05 and dist_to(C.end, B) < 0.05:
                    bottom.append(c)
                elif cy0 > ftop - 0.03 or cx1 < fx0 + 0.02:
                    above.append(c)  # (above it, or to its left: 明's 日)
                elif cx0 > fx0 - 0.02 and cx1 < fx1 + 0.02 and cy0 > fbot - 0.04:
                    inside.append(c)  # (由's middle, sticking up out of it, too)
                else:
                    rest.append(c)  # (中's middle, on down through its bottom: last)
            area = (fx1 - fx0) * (ftop - fbot)
            found.append((area, a, b, inside, bottom, above, rest))
    if not found:
        return None
    _, a, b, inside, bottom, above, rest = max(found, key=lambda f: f[0])
    return arrange(above, st) + [a, b] + arrange(inside, st) + bottom + arrange(rest, st)


def interlock(ids, st):
    """Strokes that cross and touch: top first, then left; a crossing
    horizontal before its vertical; a vertical through everything last."""
    after = {i: set() for i in ids}  # i must come after these

    def before(a, b):
        after[b].add(a)

    S = {i: st[i] for i in ids}
    for a in ids:
        A = S[a]
        for b in ids:
            if a >= b:
                continue
            B = S[b]
            oa, ob = A.segs[0].o, B.segs[0].o
            oa, ob = 'H' if bar(A) else ('h' if oa == 'H' else oa), 'H' if bar(B) else ('h' if ob == 'H' else ob)
            x = crossing(A, B)
            if x is not None:
                h, v = (a, b) if oa == 'H' else (b, a) if ob == 'H' else (None, None)
                if h is not None:
                    H, V = S[h], S[v]
                    along = float(np.hypot(*(x - H.start))) / max(length(H), 1e-6)
                    if along < 0.15 and V.start[1] > H.start[1] + 0.05 and V.segs[0].o in '/V':
                        before(v, h)
                    elif S[v].segs[0].o == '/' and len(S[v].segs) == 1:
                        # 右 vs 左: the shorter of a sweep and a crossbar goes first.
                        lh = abs(H.end[0] - H.start[0])
                        lv = float(np.hypot(*(V.end - V.start)))
                        if lv < lh:
                            before(v, h)
                        else:
                            before(h, v)
                    else:
                        before(h, v)
                elif oa == '/' and ob == '\\':
                    before(a, b)
                elif ob == '/' and oa == '\\':
                    before(b, a)
                continue
            # A bar from a straight vertical's side comes after it (上 止); from
            # a bending stroke's side, before it (ヒ 比). A bar a vertical ends
            # on comes after the vertical (土 王).
            for h, v in ((a, b), (b, a)):
                H, V = S[h], S[v]
                if H.segs[0].o != 'H' or len(V.p) < 2:
                    continue
                tol = 1.4 * (float(np.median(H.p[:, 2])) + float(np.median(V.p[:, 2])))
                run = float(np.sum(np.hypot(*np.diff(V.p[:, :2], axis=0).T)))
                straight = float(np.hypot(*(V.end - V.start))) > 0.97 * run
                if dist_to(H.start, V) < tol and V.start[1] > H.start[1] + 0.08 and \
                        np.hypot(*(H.start - V.start)) > tol:
                    if straight and V.segs[0].o == 'V':
                        before(v, h)
                    elif not straight and H.start[1] > V.end[1] + 0.15:
                        before(h, v)
                elif V.segs[0].o == 'V' and dist_to(V.end, H) < tol and np.hypot(*(V.end - H.start)) > tol and \
                        np.hypot(*(V.end - H.end)) > tol:
                    before(v, h)
            # A sweep (ノ) and the stroke that starts against it (人 入 八 文): the sweep first.
            if oa == '/' and ob == '\\' and dist_to(B.start, A) < 0.08:
                before(a, b)
            if ob == '/' and oa == '\\' and dist_to(A.start, B) < 0.08:
                before(b, a)
    # A vertical through two bars or more, top to bottom: last of those it crosses.
    for v in ids:
        V = S[v]
        if V.segs[0].o != 'V':
            continue
        xs = [h for h in ids if h != v and flat(S[h]) and crossing(V, S[h]) is not None]
        if len(xs) >= 2:
            for h in xs:
                after[v].add(h)
                after[h].discard(v)
    # A crossbar across two strokes or more (女 母), or across one hanging from
    # another (子): after them. (Not across plain verticals: 世 艹 井.)
    for h in ids:
        H = S[h]
        if not flat(H) or len(H.segs) != 1:
            continue
        hits = [(c, crossing(H, S[c])) for c in ids if c != h]
        xs = [c for c, x in hits if x is not None]
        pts = [x for _, x in hits if x is not None]
        # (And one that starts on it, away from where others cross it: 女's ノ.)
        tol = float(np.median(H.p[:, 2])) * 1.6 + 0.01
        on = [c for c in ids if c != h and c not in xs and dist_to(S[c].start, H) < tol and
              box(S[c])[1] < H.start[1] - 0.1 and all(np.hypot(*(S[c].start - q)) > 0.08 for q in pts) and
              min(np.hypot(*(S[c].start - H.start)), np.hypot(*(S[c].start - H.end))) > 0.08]
        xs += on
        plain = all(S[c].segs[0].o == 'V' and S[c].start[1] > H.start[1] for c in xs)
        attached = any(any(np.hypot(*(S[c].start - S[o].end)) < 0.05 for o in ids if o not in (c, h)) for c in xs)
        if (len(xs) >= 2 and not plain) or (len(xs) == 1 and attached):
            for c in xs:
                after[h].add(c)
                after[c].discard(h)
    # A stroke that turns along the bottom (乚 ㇄ ㇗): after what sits inside
    # it, clear of its bottom (也 己 凶 区; not 山's middle, which stands on it).
    for w in ids:
        W = S[w]
        q = W.p
        low = q[:, 1].min()
        bot = q[q[:, 1] < low + 0.07]
        if len(bot) < 3 or W.start[1] < low + 0.3 or bot[:, 0].max() - bot[:, 0].min() < 0.25 or \
                W.start[0] > bot[:, 0].min() + 0.12:
            continue
        bx0, bx1, by = bot[:, 0].min(), bot[:, 0].max(), float(bot[:, 1].mean())
        for c in ids:
            if c == w:
                continue
            C = S[c]
            cx0, cy0, cx1, cy1 = box(C)
            if cy0 > by + 0.04 and cx1 > bx0 + 0.05 and cx0 < bx1 and dist_to(C.end, W) > 0.06 and \
                    (dist_to(C.start, W) > 0.06 or np.hypot(*(C.start - W.start)) < 0.06) and crossing(C, W) is None:
                floating = all(not near(C, S[o], 0.02) for o in ids if o != c)
                small = float(np.sum(np.hypot(*np.diff(C.p[:, :2], axis=0).T))) < 0.45
                if floating and small and cx0 > W.start[0] - 0.02:
                    after[c].add(w)
                    after[w].discard(c)
                elif not floating or not small:
                    after[w].add(c)
                    after[c].discard(w)
    # Top first, then left, as far as those allow.
    done, out = set(), []
    while len(out) < len(ids):
        ready = [i for i in ids if i not in done and after[i] <= done]
        if not ready:
            ready = [i for i in ids if i not in done]
        i = min(ready, key=lambda j: key(S[j]))
        out.append(i)
        done.add(i)
    return out


# ── Kana that the rules above get wrong: their strokes in order, as where
#    each starts (x, y in em, y up). ─────────────────────────────────────
EXCEPT = {
    'ね': [(0.33, 0.76), (0.11, 0.57)],
    'れ': [(0.31, 0.78), (0.11, 0.57), (0.31, 0.39)],
    'わ': [(0.33, 0.76), (0.11, 0.57)],
    'せ': [(0.07, 0.46), (0.7, 0.74), (0.3, 0.71)],
    'も': [(0.39, 0.76), (0.14, 0.61), (0.12, 0.36)],
    'や': [(0.12, 0.41), (0.43, 0.77), (0.19, 0.69)],
    'よ': [(0.51, 0.55), (0.49, 0.75)],
    'チ': [(0.8, 0.71), (0.11, 0.42), (0.52, 0.65)],
    '九': [(0.4, 0.8), (0.11, 0.55)],
    '心': [(0.16, 0.45), (0.33, 0.53), (0.33, 0.8), (0.77, 0.48)],
}


def resample(p, step=0.02):
    """p with a point every step em along it (its ends kept): enough to order
    strokes by, far fewer than one a pixel."""
    if len(p) < 3:
        return p
    run = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(p[:, :2], axis=0).T))])
    n = max(2, int(math.ceil(run[-1] / step)) + 1)
    at = np.linspace(0, run[-1], n)
    return np.column_stack([np.interp(at, run, p[:, k]) for k in range(p.shape[1])])


def apply_except(char, strokes, ids):
    """The strokes in the order the hints give, each begun from the end
    nearest its hint."""
    want = EXCEPT.get(char)
    if not want or len(want) != len(ids):
        return ids
    left = list(ids)
    out = []
    for (x, y) in want:
        dist = lambda i: min(np.hypot(*(strokes[i].p[0, :2] - (x, y))), np.hypot(*(strokes[i].p[-1, :2] - (x, y))))
        j = min(left, key=dist)
        if np.hypot(*(strokes[j].p[-1, :2] - (x, y))) < np.hypot(*(strokes[j].p[0, :2] - (x, y))):
            strokes[j].p = strokes[j].p[::-1]
            strokes[j].flipped = True
        out.append(j)
        left.remove(j)
    return out


# ── Main ────────────────────────────────────────────────────────────────

def main():
    work = sys.argv[1]
    # (`k/n`: every nth glyph from the kth, to run in parallel; else characters to do.)
    arg = sys.argv[2] if len(sys.argv) > 2 else None
    part = tuple(map(int, arg.split('/'))) if arg and '/' in arg and arg.replace('/', '').isdigit() else None
    only = None if part else arg
    meta = json.load(open(os.path.join(work, 'meta.json')))
    S = meta['S']
    global SCALE
    SCALE = S
    blob = np.fromfile(os.path.join(work, 'shapes.bin'), np.uint8)

    def raster(sh):
        n = sh['w'] * sh['h']
        bits = blob[sh['off']:sh['off'] + (n + 7) // 8]
        return np.unpackbits(bits)[:n].reshape(sh['h'], sh['w']).astype(bool)

    out = {'xHeight': meta['xHeight'], 'ascent': meta['ascent'], 'descent': meta['descent'],
           'space': meta.get('space', 0.25), 'glyphs': {}}
    done = 0
    for n, g in enumerate(meta['glyphs']):
        c = g['char']
        if (only and c not in only) or (part and n % part[1] != part[0]):
            continue
        done += 1
        if done % 100 == 0:
            print(done, 'glyphs', flush=True)
        global UP_DOWN
        UP_DOWN = kind(c) == 'kata'
        if kind(c) in ('kata', 'kanji'):
            strokes = pen_strokes([chains(raster(sh), sh, S) for sh in g['shapes']], 'grammar')
        else:
            strokes = free_join(kana_strokes(g['shapes'], [raster(sh) for sh in g['shapes']], S, c))
        # (Ordered by lines a point every 0.02 em; written with every point.)
        dense = [s.p for s in strokes]
        for s in strokes:
            s.p = resample(s.p)
            s.flipped = False
        ids = order(strokes, c)
        ids = apply_except(c, strokes, ids)
        res = []
        for i in ids:
            p = dense[i][::-1] if strokes[i].flipped else dense[i]
            a = smooth(p, 2)
            a = rdp(a, 0.003)
            res.append({'late': False, 'p': [round(float(v), 4) for v in a.flatten()]})
        out['glyphs'][c] = {'adv': round(g['adv'], 4), 'strokes': res}
    name = f'strokes.{part[0]}.json' if part else 'strokes.json'
    json.dump(out, open(os.path.join(work, name), 'w'), ensure_ascii=False)
    n = sum(len(v['strokes']) for v in out['glyphs'].values())
    print(f"{len(out['glyphs'])} glyphs, {n} strokes")


if __name__ == '__main__':
    main()
