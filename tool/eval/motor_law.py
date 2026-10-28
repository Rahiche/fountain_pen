"""motor_law.py: how a pen's speed follows its path's curvature. A hand's
does, by the two-thirds power law: speed ~ curvature^-beta, beta close to
1/3 (Lacquaniti, Terzuolo & Viviani 1983) - slow round tight turns, quick
along straights. Fitted here, on log speed against log curvature, for pen
paths sampled over time:

    python3 tool/eval/motor_law.py [--sigma=13] [--trim=0.2] name=paths.json ... name=tegaki:<svg>[@size] ... [out.json]
    python3 tool/eval/motor_law.py --controls [--sigma=13] [--trim=0.2] name=paths.json ... name=tegaki:<svg>[@size] ...

paths.json: {"label": [[t, x, y], ...]} in em (as fountain_pen's tip() gives
them, sampled finely); an SVG from Tegaki's CLI is read for its strokes'
paths and when each is drawn, @size its font size in px (default 100).

As motion recordings are usually measured: each stroke (the pen down, from
landing to lifting) is smoothed with a Gaussian low-pass in time, --sigma
ms (default 13, a cutoff near 10 Hz), its ends where the filter would run
off it dropped, then differentiated. The law holds piecewise, at a speed of
its own for each stroke (Viviani & Cenzato 1985), so beta is fitted within
strokes: each stroke's mean log speed and log curvature taken off first.
--trim: the share of each stroke's time, at either end, left out too (0 by
default): where the pen sets off from rest and comes back to it, which is
starting and stopping, not following a curve.

--controls: each path's own strokes, retimed by four rules and measured the
same way - a check that the fit finds no law where there's none (constant
speed; Tegaki's easing, fast to a stop; a minimum-jerk bell) and finds 1/3
where it was put (speed as curvature^-1/3).
"""
import json, re, sys
import numpy as np


def ease(u, x1, y1, x2, y2):
    """CSS cubic-bezier(x1, y1, x2, y2) at time u."""
    lo, hi = 0.0, 1.0
    for _ in range(40):
        s = (lo + hi) / 2
        x = 3 * (1 - s) ** 2 * s * x1 + 3 * (1 - s) * s * s * x2 + s ** 3
        lo, hi = (s, hi) if x < u else (lo, s)
    s = (lo + hi) / 2
    return 3 * (1 - s) ** 2 * s * y1 + 3 * (1 - s) * s * s * y2 + s ** 3


def tegaki_strokes(path, size):
    """Tegaki's strokes: (begin, dur, points in em, dashoffset from, to,
    keySplines, dash length) for each mask's revealing path."""
    s = open(path).read()
    out = []
    for m in re.finditer(r'<mask[^>]*>(.*?)</mask>', s, re.S):
        body = m.group(1)
        d = re.search(r'\sd="([^"]+)"', body)
        a = re.search(r'<animate[^>]*>', body)
        if not d or not a:
            continue
        pts = np.array([float(v) for v in re.findall(r'-?\d+\.?\d*', d.group(1))]).reshape(-1, 2)
        attr = lambda k: re.search(k + r'="([^"]+)"', a.group(0)).group(1)
        v0, v1 = (float(v) for v in attr('values').split(';'))
        spline = [float(v) for v in attr('keySplines').split()] if 'keySplines' in a.group(0) else [0, 0, 1, 1]
        dash = float(re.search(r'stroke-dasharray="([\d.]+)', body).group(1))
        out.append((float(attr('begin').rstrip('s')), float(attr('dur').rstrip('s')),
                    pts * [1 / size, -1 / size], v0 / size, v1 / size, spline, dash / size))
    return out


def tegaki(path, size, rate=240):
    """Where Tegaki's pen is over time: each mask's path, revealed by its
    stroke-dashoffset animation (a dash as long as the path, offset from
    v0 to v1), the pen at the revealed length's end."""
    strokes = tegaki_strokes(path, size)
    end = max(b + d for b, d, *_ in strokes)
    out = []
    for k in range(int(end * rate) + 1):
        t = k / rate
        on = [st for st in strokes if st[0] <= t <= st[0] + st[1]]
        if not on:
            continue
        b, d, pts, v0, v1, sp, dash = on[0]
        off = v0 + (v1 - v0) * ease((t - b) / d, *sp)
        run = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])
        at = min(max(dash - off, 0), run[-1])
        out.append([t, np.interp(at, run, pts[:, 0]), np.interp(at, run, pts[:, 1])])
    return out


def strokes_of(path):
    """A sampled path's strokes: the stretches where the pen moves on the
    paper, as (t, x, y) arrays. (One ends where the pen stops, jumps, or
    goes unsampled: lifted to its next stroke.)"""
    a = np.array(path, float)
    if len(a) < 2:
        return []
    step = np.hypot(*np.diff(a[:, 1:], axis=0).T)
    dt = np.diff(a[:, 0])
    moving = (step > 1e-5) & (step < 0.04) & (dt < 1.5 * np.median(dt))
    out, i = [], 0
    while i < len(moving):
        if not moving[i]:
            i += 1
            continue
        j = i
        while j < len(moving) and moving[j]:
            j += 1
        out.append(a[i:j + 1])
        i = j
    return out


def samples(path, sigma_ms=13.0, trim=0.0):
    """(speed, curvature, stroke) along each stroke, smoothed (see above)."""
    out = []
    for n, st in enumerate(strokes_of(path)):
        t, xy = st[:, 0], st[:, 1:]
        h = float(np.median(np.diff(t)))
        sd = sigma_ms / 1000 / h
        k = np.exp(-0.5 * (np.arange(-int(3 * sd), int(3 * sd) + 1) / sd) ** 2)
        k /= k.sum()
        if len(xy) < len(k) + 10:
            continue
        sm = np.column_stack([np.convolve(xy[:, c], k, mode='valid') for c in (0, 1)])
        d1 = np.gradient(sm, h, axis=0)
        d2 = np.gradient(d1, h, axis=0)
        v = np.hypot(*d1.T)
        kappa = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / np.maximum(v, 1e-9) ** 3
        at = t[len(k) // 2:len(t) - len(k) // 2]
        ok = (v > 0.05) & (kappa > 0.3) & (kappa < 100)
        ok &= (at >= t[0] + trim * (t[-1] - t[0])) & (at <= t[-1] - trim * (t[-1] - t[0]))
        out.append(np.column_stack([v[ok], kappa[ok], np.full(ok.sum(), n)]))
    return np.vstack(out) if out else np.zeros((0, 3))


def fit(vk):
    """beta in speed ~ curvature^-beta within strokes, and the share of the
    variance in log speed within strokes that it explains (R^2)."""
    xs, ys = [], []
    for n in np.unique(vk[:, 2]):
        s = vk[vk[:, 2] == n]
        if len(s) < 8:
            continue
        x, y = np.log(s[:, 1]), np.log(s[:, 0])
        xs.append(x - x.mean())
        ys.append(y - y.mean())
    if not xs or sum(map(len, xs)) < 20:
        return float('nan'), float('nan')
    x, y = np.concatenate(xs), np.concatenate(ys)
    slope = (x @ y) / (x @ x)
    r2 = 1 - np.sum((y - slope * x) ** 2) / np.sum(y ** 2)
    return -slope, r2


def retime(strokes, rule, rate=240, mean=2.0):
    """The same strokes (point arrays, in em), the pen moved along each by
    [rule], at [mean] em/s on average, lifting for 0.15 s between them."""
    out, t0 = [], 0.0
    for p in strokes:
        p = p[np.concatenate([[True], np.hypot(*np.diff(p, axis=0).T) > 1e-7])]
        run = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(p, axis=0).T))])
        if run[-1] < 0.02:
            continue
        # (The pen's progress along the stroke, s of 0 to 1, by time u of 0 to 1.)
        u = np.linspace(0, 1, 400)
        if rule == 'constant':
            s = u
        elif rule == 'tegaki':
            s = 1 - (1 - u) ** 2
        elif rule == 'min-jerk':
            s = 10 * u ** 3 - 15 * u ** 4 + 6 * u ** 5
        else:
            # Speed as curvature^-1/3: the curvature of the stroke smoothed
            # along its length (0.015 em), the time to each point summed from it.
            q = np.linspace(0, run[-1], max(int(run[-1] / 0.002), 20))
            xy = np.column_stack([np.interp(q, run, p[:, c]) for c in (0, 1)])
            sd = 0.015 / (q[1] - q[0])
            g = np.exp(-0.5 * (np.arange(-int(3 * sd), int(3 * sd) + 1) / sd) ** 2)
            g /= g.sum()
            sm = np.column_stack([np.convolve(np.pad(xy[:, c], len(g) // 2, mode='reflect', reflect_type='odd'),
                                              g, mode='valid') for c in (0, 1)])
            d1 = np.gradient(sm, axis=0)
            d2 = np.gradient(d1, axis=0)
            kap = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / np.maximum(np.hypot(*d1.T), 1e-12) ** 3
            pace = np.clip(kap, 0.5, 300) ** (-1 / 3)
            tt = np.concatenate([[0], np.cumsum(np.diff(q) / ((pace[1:] + pace[:-1]) / 2))])
            u, s = tt / tt[-1], q / run[-1]
        dur = run[-1] / mean
        for k in range(int(dur * rate) + 1):
            at = np.interp(k / (rate * dur), u, s) * run[-1]
            out.append([t0 + k / rate, np.interp(at, run, p[:, 0]), np.interp(at, run, p[:, 1])])
        t0 += dur + 0.15
    return out


def load(arg):
    name, src = arg.split('=', 1)
    if src.startswith('tegaki:'):
        svg, _, size = src[len('tegaki:'):].partition('@')
        return name, {'': tegaki(svg, float(size or 100))}
    return name, json.load(open(src))


def main():
    args = sys.argv[1:]
    out = args[-1] if args and args[-1].endswith('.json') and '=' not in args[-1] else None
    sigma = next((float(a.split('=')[1]) for a in args if a.startswith('--sigma=')), 13.0)
    trim = next((float(a.split('=')[1]) for a in args if a.startswith('--trim=')), 0.0)
    controls = '--controls' in args
    results = {}
    for arg in [a for a in args if '=' in a and not a.startswith('--')]:
        name, paths = load(arg)
        for label, path in paths.items():
            key = f'{name}/{label}' if label else name
            if controls:
                geometry = [st[:, 1:] for st in strokes_of(path)]
                row = []
                for rule in ('constant', 'tegaki', 'min-jerk', 'law'):
                    beta, r2 = fit(samples(retime(geometry, rule), sigma, trim))
                    row.append(f'{rule} {beta:6.3f} (R^2 {r2:4.2f})')
                print(f'{key:16} ' + '   '.join(row))
                continue
            vk = samples(path, sigma, trim)
            beta, r2 = fit(vk)
            pick = np.random.default_rng(1).permutation(len(vk))[:500]
            results[key] = {'beta': beta, 'r2': r2, 'n': len(vk), 'points': vk[pick, :2].round(4).tolist()}
            print(f'{key:24} beta {beta:6.3f}   R^2 {r2:5.2f}   ({len(vk)} samples)')
    if out:
        json.dump(results, open(out, 'w'))


if __name__ == '__main__':
    main()
