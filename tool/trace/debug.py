"""debug.py <chars> <out.ppm> (run in the work dir): each glyph's raster (grey) and its traced
strokes over it, in order (red, orange, green, blue, purple…), a dot where
each starts; late strokes dashed in cyan."""
import json, sys
import numpy as np
meta = json.load(open('meta.json')); S = meta['S']
st = json.load(open('strokes.json'))['glyphs']
by = {g['char']: g for g in meta['glyphs']}
chars = list(dict.fromkeys(sys.argv[1]))
cell = 300
cols = 6
rows = (len(chars) + cols - 1) // cols
img = np.full((rows * cell, cols * cell, 3), 255, np.uint8)
colors = [(220, 30, 30), (240, 140, 0), (30, 160, 40), (30, 80, 220), (150, 40, 200), (200, 0, 120), (0, 150, 150)]
def dot(cy, cx, r, c, y0, x0):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy * dy + dx * dx <= r * r:
                yy, xx = cy + dy, cx + dx
                if 0 <= yy < cell and 0 <= xx < cell:
                    img[y0 + yy, x0 + xx] = c
for k, ch in enumerate(chars):
    g = by[ch]; y0, x0 = (k // cols) * cell, (k % cols) * cell
    r = np.fromfile(f"raster/{g['code']}.gray", np.uint8).reshape(g['h'], g['w'])
    sc = min(1.0, (cell - 20) / max(g['w'], g['h']))
    # (Raster scaled into the cell, nearest.)
    hh, ww = int(g['h'] * sc), int(g['w'] * sc)
    ys = (np.arange(hh) / sc).astype(int); xs = (np.arange(ww) / sc).astype(int)
    sub = r[ys][:, xs] > 110
    img[y0 + 10:y0 + 10 + hh, x0 + 10:x0 + 10 + ww][sub] = (205, 205, 205)
    for i, s in enumerate(st[ch]['strokes']):
        p = np.array(s['p']).reshape(-1, 3)
        c = (0, 190, 230) if s['late'] else colors[i % len(colors)]
        # em → raster px → cell px
        px = (p[:, 0] * S + g['ox']) * sc + 10; py = (g['oy'] - p[:, 1] * S) * sc + 10
        for j in range(len(p) - 1):
            n = int(max(abs(px[j + 1] - px[j]), abs(py[j + 1] - py[j]))) + 1
            for t in np.linspace(0, 1, n):
                if s['late'] and int(t * n) % 6 < 3: continue
                dot(int(py[j] + (py[j + 1] - py[j]) * t), int(px[j] + (px[j + 1] - px[j]) * t), 1, c, y0, x0)
        dot(int(py[0]), int(px[0]), 5, c, y0, x0)
with open(sys.argv[2], 'wb') as f:
    f.write(f'P6 {img.shape[1]} {img.shape[0]} 255\n'.encode()); f.write(img.tobytes())
