# Measuring a traced hand

`kanjivg_eval.py` compares a traced Japanese hand with [KanjiVG](https://kanjivg.tagaini.net)'s stroke data: for each
character both have, whether it has the same number of strokes, whether they come in the same order (exactly, and as
Kendall's tau), whether each runs the same way, and how close their shapes are. It also scores a naive order (top
first, then left) of the same strokes, to show what the ordering rules add.

KanjiVG is licensed under CC BY-SA 3.0. It's only measured against here: none of it goes into a hand, and it isn't
part of this package. Download it yourself:

```sh
gh release download -R KanjiVG/kanjivg -p 'kanjivg-*.xml.gz' -D /tmp/kanjivg
python3 tool/eval/kanjivg_eval.py /tmp/kanjivg/kanjivg-*.xml.gz work/strokes.json results.json
```

`work/strokes.json` is what `tool/trace/strokes_cjk.py` writes; `results.json` has each character's scores.

# Measuring the pen's pace

A hand slows round tight curves and speeds up along straights by a precise rule, the two-thirds power law: its speed
falls as the path's curvature to the −1/3 (Lacquaniti, Terzuolo & Viviani 1983). `motor_law.py` fits that exponent, β,
to any pen's paths over time, the way motion recordings are measured: each stroke smoothed with a 10 Hz low-pass,
speed and curvature taken along it, and log speed fitted to log curvature within strokes (each at its own pace).

```sh
JOBS=jobs.json OUT=/tmp/paths.json flutter test tool/eval/pen_paths_test.dart
python3 tool/eval/motor_law.py ours=/tmp/paths.json tegaki=tegaki:hello.svg@120 results.json
python3 tool/eval/motor_law.py --controls ours=/tmp/paths.json tegaki=tegaki:hello.svg@120
python3 tool/eval/motor_figure.py speed_curvature.svg new=/tmp/paths.json old=/tmp/before.json \
    tegaki_en=hello.svg@120 tegaki_ja=nihongo.svg@110 tegaki_ar=marhaba.svg@110
```

`pen_paths_test.dart` writes fountain_pen's paths (see its header for `jobs.json`). An SVG from
[Tegaki](https://github.com/gkurt/tegaki)'s CLI is read for its strokes and their animation, `@` its font size in px.
`--controls` retimes each path's own strokes four ways and measures them the same way: constant speed, Tegaki's easing
and a minimum-jerk bell should show no law (β near 0, little explained), and speed set as curvature^−1/3 shows what the
measurement finds for a true law on those paths (β about 0.26 here: the smoothing takes a little off).

Measured on "Hello, handwriting" (Caveat), 手書きの日本語 (Klee One) and مرحبا بالعالم (Amiri), each pen's own
paths:

| | English | Japanese | Arabic |
|---|---|---|---|
| fountain_pen 0.2.0 (the power law) | β 0.27, R² 0.53 | β 0.24, R² 0.53 | β 0.31, R² 0.53 |
| fountain_pen 0.1.0 (slower in the turns) | β 0.10, R² 0.54 | β 0.08, R² 0.36 | β 0.07, R² 0.24 |
| Tegaki 1.1.0 | β 0.19, R² 0.17 | β 0.05, R² 0.01 | β 0.16, R² 0.20 |
| a true −1/3 law on fountain_pen's paths (control) | β 0.26, R² 0.88 | β 0.26, R² 0.83 | β 0.27, R² 0.81 |

R² is the share of the changes in speed within strokes that curvature accounts for. Tegaki's speed changes come from its
easing (each stroke fast to a stop), which on its own paths measures β 0.11–0.18 with R² 0.04–0.11.
