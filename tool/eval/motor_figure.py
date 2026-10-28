"""motor_figure.py: the speed-curvature figure, as an SVG - a row for each
pen (fountain_pen with the power law, fountain_pen before it, Tegaki), a
column for each script; each panel its samples' speed against curvature
within their strokes (as motor_law.py fits them), the fitted slope, and the
two-thirds power law's -1/3:

    python3 tool/eval/motor_figure.py out.svg new=ours.json old=ours_before.json \\
        tegaki_en=<svg>@120 tegaki_ja=<svg>@110 tegaki_ar=<svg>@110
"""
import json, math, sys
import numpy as np
from motor_law import fit, samples, tegaki

SCRIPTS = [('en', 'English', 'Caveat'), ('ja', 'Japanese', 'Klee One'), ('ar', 'Arabic', 'Amiri')]
ROWS = [('new', 'fountain_pen', 'with the power law'), ('old', 'fountain_pen', 'before it'),
        ('tegaki', 'Tegaki 1.1.0', 'its own easing')]
PW, PH, GAP, LEFT, TOP = 250, 190, 34, 150, 74
X0, X1, Y0, Y1 = -1.2, 1.2, -0.65, 0.5     # log10 of curvature and speed over their stroke's means


def centred(vk):
    """log10 curvature and speed, less their stroke's means (strokes of 8 or more)."""
    out = []
    for n in np.unique(vk[:, 2]):
        s = vk[vk[:, 2] == n]
        if len(s) >= 8:
            x, y = np.log10(s[:, 1]), np.log10(s[:, 0])
            out.append(np.column_stack([x - x.mean(), y - y.mean()]))
    return np.vstack(out)


def main():
    out, args = sys.argv[1], dict(a.split('=', 1) for a in sys.argv[2:])
    data = {}
    for key, *_ in ROWS:
        for s, *_ in SCRIPTS:
            if key == 'tegaki':
                svg, _, size = args[f'tegaki_{s}'].partition('@')
                path = tegaki(svg, float(size))
            else:
                path = json.load(open(args[key]))[s]
            vk = samples(path)
            data[key, s] = (centred(vk), *fit(vk))
    w = LEFT + 3 * PW + 2 * GAP + 20
    h = TOP + 3 * PH + 2 * GAP + 56
    sx = lambda x: (x - X0) / (X1 - X0) * PW
    sy = lambda y: (Y1 - y) / (Y1 - Y0) * PH
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
         'font-family="system-ui, -apple-system, \'Segoe UI\', sans-serif">',
         '<style>.bg{fill:#fcfcfb}.ink{fill:#0b0b0b}.ink2{fill:#52514e}.mute{fill:#898781}'
         '.grid{stroke:#e1e0d9}.axis{stroke:#c3c2b7}.fitl{stroke:#0b0b0b}.ref{stroke:#898781}'
         '.hi{fill:#2a78d6}.lo{fill:#898781}'
         '@media (prefers-color-scheme: dark){.bg{fill:#1a1a19}.ink{fill:#f0efec}.ink2{fill:#c3c2b7}'
         '.grid{stroke:#2c2c2a}.axis{stroke:#383835}.fitl{stroke:#f0efec}.hi{fill:#3987e5}}'
         'text{font-size:12px}.t{font-size:13px;font-weight:600}.big{font-size:15px;font-weight:600}</style>',
         f'<rect class="bg" width="{w}" height="{h}"/>',
         f'<text class="big ink" x="20" y="28">Pen speed against curvature, within each stroke</text>',
         f'<text class="ink2" x="20" y="48">Both as factors of the stroke\'s own average, on log scales. '
         'A hand slows as curvature^(−⅓) (the two-thirds power law): the grey line.</text>']
    xt = [(-1, '0.1×'), (math.log10(1 / 3), '0.3×'), (0, '1×'), (math.log10(3), '3×'), (1, '10×')]
    yt = [(math.log10(0.25), '0.25×'), (math.log10(0.5), '0.5×'), (0, '1×'), (math.log10(2), '2×')]
    rng = np.random.default_rng(7)
    for c, (s, script, font) in enumerate(SCRIPTS):
        x = LEFT + c * (PW + GAP)
        o.append(f'<text class="t ink" x="{x}" y="{TOP - 10}">{script} <tspan class="ink2" font-weight="400">· {font}</tspan></text>')
    for r, (key, who, how) in enumerate(ROWS):
        y = TOP + r * (PH + GAP)
        o.append(f'<text class="t ink" x="20" y="{y + PH / 2 - 4}">{who}</text>'
                 f'<text class="ink2" x="20" y="{y + PH / 2 + 13}">{how}</text>')
        for c, (s, *_) in enumerate(SCRIPTS):
            x = LEFT + c * (PW + GAP)
            pts, beta, r2 = data[key, s]
            o.append(f'<g transform="translate({x},{y})">')
            for v, label in xt:
                o.append(f'<line class="grid" x1="{sx(v):.1f}" x2="{sx(v):.1f}" y1="0" y2="{PH}" stroke-width="1"/>')
                if r == len(ROWS) - 1:
                    o.append(f'<text class="mute" x="{sx(v):.1f}" y="{PH + 16}" text-anchor="middle">{label}</text>')
            for v, label in yt:
                o.append(f'<line class="grid" x1="0" x2="{PW}" y1="{sy(v):.1f}" y2="{sy(v):.1f}" stroke-width="1"/>')
                if c == 0:
                    o.append(f'<text class="mute" x="-6" y="{sy(v) + 4:.1f}" text-anchor="end">{label}</text>')
            if c == 0:
                o.append('<text class="ink2" x="-6" y="-8" text-anchor="end">speed</text>')
            o.append(f'<line class="axis" x1="0" x2="{PW}" y1="{PH}" y2="{PH}" stroke-width="1"/>')
            pick = pts[rng.permutation(len(pts))[:350]]
            pick = pick[(pick[:, 0] > X0) & (pick[:, 0] < X1) & (pick[:, 1] > Y0) & (pick[:, 1] < Y1)]
            cls = 'hi' if key == 'new' else 'lo'
            o.append(f'<g class="{cls}" fill-opacity="0.28">' +
                     ''.join(f'<circle cx="{sx(a):.1f}" cy="{sy(b):.1f}" r="4"/>' for a, b in pick) + '</g>')
            o.append(f'<line class="ref" x1="{sx(X0):.1f}" y1="{sy(-X0 / 3):.1f}" x2="{sx(X1):.1f}" y2="{sy(-X1 / 3):.1f}" stroke-width="1.5"/>')
            o.append(f'<line class="fitl" x1="{sx(X0):.1f}" y1="{sy(-beta * X0):.1f}" x2="{sx(X1):.1f}" y2="{sy(-beta * X1):.1f}" '
                     'stroke-width="2" stroke-linecap="round"/>')
            o.append(f'<text class="ink" x="{PW - 4}" y="16" text-anchor="end">β {beta:.2f} · R² {r2:.2f}</text>')
            if r == 0 and c == 0:
                o.append(f'<text class="ink2" x="6" y="{sy(-X0 / 3) - 8:.1f}">−⅓</text>')
                o.append(f'<text class="ink2" x="6" y="{sy(-beta * X0) + 18:.1f}">fit</text>')
            o.append('</g>')
    o.append(f'<text class="ink2" x="{LEFT + 1.5 * PW + GAP}" y="{h - 14}" text-anchor="middle">curvature, as a factor of the stroke\'s average</text>')
    o.append('</svg>')
    open(out, 'w').write('\n'.join(o))
    for (key, s), (_, beta, r2) in data.items():
        print(f'{key:7} {s}  beta {beta:.3f}  R^2 {r2:.2f}')


if __name__ == '__main__':
    main()
