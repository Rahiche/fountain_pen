"""strokes_arabic.py: an Arabic hand's strokes, from the joined forms
shaped_glyphs.swift rasterises → strokes.json (as strokes.py writes it: em
units, y up from the baseline, a radius per point; late strokes written
once the word's done).

Each glyph's centre line (strokes_cjk.py's Graph: forks close together are
one) is walked as an Arabic hand writes it: from its right (or top) end,
leftwards, on along the smoothest way; round a loop first where one leaves
a fork and comes back to it (ص ط ف); out to the tip and back of a short dead
end, where the font drew a turn back as a branch (ح's bar, ع's head); lifted
only when there's nowhere left to go. The small parts on their own (dots,
hamza, ك's mark, madda) are late, written after the word; ط and ظ's upright
comes after their bowl.

    python3 tool/trace/strokes_arabic.py <work dir>   (shaped_glyphs.swift's raster/ and meta.json in it)
"""
import json, math, os, sys
import numpy as np
from skeleton import rdp, smooth
from strokes_cjk import Graph

# ط and ظ (alone and joined): the bowl, then the upright.
UPRIGHT_LAST = {0x0637, 0x0638} | set(range(0xFEC1, 0xFEC9))
# ع and غ joined from before (their last and middle forms): the loop a hand
# writes as a crossed tie, not round the font's outline.
CROSSED = {0xFECA, 0xFECC, 0xFECE, 0xFED0}


def line(a, b):
    """Pixels from a to b, a step of about one at a time."""
    n = max(1, int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))))
    return [(int(round(a[0] + (b[0] - a[0]) * k / n)), int(round(a[1] + (b[1] - a[1]) * k / n))) for k in range(1, n + 1)]


def tie(loop, path):
    """The loop as a hand crosses it: the pen, coming in from the right, turns
    up at the loop's right edge, across to its top left, along its top, then
    back down across that first stroke to its left edge, and on (path: the
    pen's way so far, cut back to the loop's right edge). Returns the loop's
    left edge, where the pen goes on from."""
    ys = [q[0] for q in loop]
    xs = [q[1] for q in loop]
    top, bottom, left, right = min(ys), max(ys), min(xs), max(xs)
    while len(path) > 1 and path[-1][1] < right:
        path.pop()
    p = path[-1]
    for q in ((top, left), (top, right), (bottom, left)):
        path += line(p, q)
        p = q
    return left


def arabic_walk(g, upright_last=False, crossed=False):
    """The glyph's strokes (pixel paths), each from its right or top end."""
    es, ports = g.es, g.ports
    live = [i for i in range(len(es)) if i not in g.internal]
    at = {}
    for k, ps in ports.items():
        for (i, s), ang in ps:
            at.setdefault(k, []).append((i, s, ang))
    used = set(g.internal)
    later = []
    if upright_last:
        # The upright: from the highest free end down to its fork, near vertical.
        tops = [(min(es[i][0][0], es[i][-1][0]), i) for i in live
                if es[i][0] in g.ends or es[i][-1] in g.ends]
        if tops:
            _, i = min(tops)
            e = es[i] if es[i][0][0] < es[i][-1][0] else es[i][::-1]
            dy, dx = e[-1][0] - e[0][0], e[-1][1] - e[0][1]
            if dy > 0.25 * g.S and abs(dx) < 0.5 * dy:
                used.add(i)
                later.append(e)
    # (Rows run down, columns across: right and high first.)
    score = lambda q: q[0] - 0.8 * q[1]
    out = []
    while any(i not in used for i in live):
        free = [(score(es[i][0] if s == 0 else es[i][-1]), i, s) for i in live if i not in used for s in (0, 1)
                if (es[i][0] if s == 0 else es[i][-1]) in g.ends]
        if free:
            _, i, s = min(free)
        else:
            i = min((j for j in live if j not in used), key=lambda j: min(score(q) for q in es[j]))
            e = es[i]
            k = min(range(len(e)), key=lambda j: score(e[j]))
            es[i] = e[k:] + e[1:k + 1] if e[0] == e[-1] else e
            s = 0
        path = []
        skip_right_of = None
        while True:
            used.add(i)
            e = es[i] if s == 0 else es[i][::-1]
            if skip_right_of is not None:
                # (After a crossed loop: on from its left edge, not back to its fork.)
                if e[-1][1] < skip_right_of:
                    # (Leaving leftwards, on to the next letter: from where it passes the loop.)
                    e = e[next(n for n, q in enumerate(e) if q[1] < skip_right_of):]
                skip_right_of = None
                path += e
            else:
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
            # Round a loop first: out of the fork and back to it.
            loops = [(j, t) for j, t, _ in nxt if g.root(g.far_end(j, t)) == k]
            for j, t in loops:
                if j in used:
                    continue
                loop = es[j] if t == 0 else es[j][::-1]
                if crossed:
                    skip_right_of = tie(loop, path)
                else:
                    path += loop[1:]
                used.add(j)
            # Out to the tip of a short dead end and back.
            nxt = [(j, t, ang) for j, t, ang in nxt if j not in used]
            dead = sorted((len(es[j]), j, t) for j, t, _ in nxt if g.far_end(j, t) in g.ends and len(es[j]) < 0.45 * g.S)
            if dead and len(nxt) >= 2:
                _, j, t = dead[0]
                tail = es[j] if t == 0 else es[j][::-1]
                path += tail[1:] + tail[::-1][1:]
                used.add(j)
                nxt = [(j2, t2, ang) for j2, t2, ang in nxt if j2 != j]
                v = np.array(tail[0], float) - np.array(tail[min(len(tail) - 1, 6)], float)
                heading = math.atan2(v[0], v[1])
            if not nxt:
                break
            turn = lambda ang: abs((ang - heading + math.pi) % (2 * math.pi) - math.pi)
            j, t, _ = min(nxt, key=lambda c: turn(c[2]))
            i, s = j, t
        out.append(path)
    return out + later


def blobs(img):
    """The image's separate parts, each a list of its pixels."""
    seen = np.zeros(img.shape, bool)
    out = []
    for y0, x0 in zip(*np.nonzero(img)):
        if seen[y0, x0]:
            continue
        stack, part = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            part.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (y + dy, x + dx)
                if 0 <= q[0] < img.shape[0] and 0 <= q[1] < img.shape[1] and img[q] and not seen[q]:
                    seen[q] = True
                    stack.append(q)
        out.append(part)
    return out


def main():
    work = sys.argv[1]
    meta = json.load(open(os.path.join(work, 'meta.json')))
    S = meta['S']
    out = {'xHeight': meta['xHeight'], 'ascent': meta['ascent'], 'descent': meta['descent'], 'space': meta['space'],
           'glyphs': {}}
    for gm in meta['glyphs']:
        w, h = gm['w'], gm['h']
        img = np.fromfile(os.path.join(work, f"raster/{gm['code']}.gray"), np.uint8).reshape(h, w) > 110
        sh = {'ox': gm['ox'], 'oy': gm['oy'], 'w': w, 'h': h}
        g = Graph(img, sh, S)
        if g.dot is not None:
            paths = []
            ems = [g.dot]
        else:
            paths = arabic_walk(g, gm['code'] in UPRIGHT_LAST, gm['code'] in CROSSED) if g.es else []
            # (A main stroke found running rightwards, from a tail's tip to the
            # loop it closes (ف ق و), turned round to start at its head.)
            for k, q in enumerate(paths):
                if len(q) > 0.3 * S and q[-1][1] - q[0][1] > 0.15 * S and q[0][0] >= q[-1][0] - 0.1 * S:
                    paths[k] = q[::-1]
            ems = [g.em(p) for p in paths]
            # Dots too small to thin to a line: a dot each, where they are.
            drawn = {q for p in paths for q in p}
            for part in blobs(img):
                if len(part) < 12 or any(q in drawn for q in part):
                    continue
                ys, xs = zip(*part)
                cy, cx, r = sum(ys) / len(ys), sum(xs) / len(xs), float(max(g.d[q] for q in part))
                x, y = (cx - gm['ox']) / S, (gm['oy'] - cy) / S
                ems.append(np.array([(x + 0.3 * r / S, y, r / S), (x - 0.3 * r / S, y, r / S)]))
                paths.append([part[0]])
        # The parts on their own, small (dots, hamza, ك's mark, madda): late.
        size = [len(p) for p in paths] or [1]
        main_ = max(size)
        res = []
        for k, p in enumerate(ems):
            if len(p) < 2:
                continue
            a = smooth(p, 3)
            a = rdp(a, 0.004)
            run = float(np.sum(np.hypot(*np.diff(a[:, :2], axis=0).T)))
            late = k < len(size) and size[k] < 0.3 * main_ and not (gm['code'] in UPRIGHT_LAST and k == len(ems) - 1)
            res.append({'late': bool(late), 'dot': bool(late and run < 0.07),
                        'p': [round(float(v), 4) for v in a.flatten()]})
        out['glyphs'][gm['char']] = {'adv': round(gm['adv'], 4), 'strokes': res}
    json.dump(out, open(os.path.join(work, 'strokes.json'), 'w'), ensure_ascii=False)
    n = sum(len(v['strokes']) for v in out['glyphs'].values())
    print(f"{len(out['glyphs'])} glyphs, {n} strokes")


if __name__ == '__main__':
    main()
