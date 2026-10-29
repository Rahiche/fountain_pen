# Trace your own hand

A hand (`PenHand`) holds every character's strokes as centre lines, in the order a hand draws them. These tools trace
them from a font's outlines. Each glyph is thinned to its centre line and cut into a graph. The graph is then walked
the way a pen would go, from the top left, carrying on through each fork along the smoothest way. Small detached
parts, like an i's dot, wait until the word is written.

Trace only a font you're licensed to use. You need macOS for the first step, and Python 3 with numpy for the rest.

## A Latin script font

```sh
mkdir -p tool/trace/work/raster
swift tool/trace/glyphs.swift path/to/Font.ttf tool/trace/work      # rasterise each glyph
python3 tool/trace/strokes.py tool/trace/work                       # trace its strokes → strokes.json
python3 tool/trace/to_dart.py tool/trace/work/strokes.json lib/src/hands/my_hand.dart \
    myHand "My Font" "Licensed under …"                             # → const myHand = PenHand(...)
```

Then use `FountainPenText('…', hand: myHand)`. Or skip the Dart step and load the JSON with `PenHand.fromJson`.

To check a trace, run `cd tool/trace/work && python3 ../debug.py "abc" debug.ppm`. It draws each glyph's strokes, in
order, over its raster.

## An Arabic font

Rasterise each letter's joined forms, then trace them right to left:

```sh
python3 tool/trace/arabic_forms.py work/forms.tsv                           # each letter's forms, and how to shape them
swift tool/trace/shaped_glyphs.swift path/to/Font.ttf work/forms.tsv work   # each form rasterised
python3 tool/trace/strokes_arabic.py work                                  # strokes, right to left → strokes.json
python3 tool/trace/to_packed.py work/strokes.json lib/src/hands/my_hand.dart myHand "My Font" "Licensed under …"
```

## A Japanese (or other CJK) font

These work best with a font that, like Noto Sans JP, keeps each stroke as its own outline:

```sh
swift tool/trace/cjk_glyphs.swift path/to/Font.ttf chars.txt work 300      # each outline rasterised (weight 300)
python3 tool/trace/strokes_cjk.py work                                    # strokes, in stroke order → strokes.json
python3 tool/trace/to_packed.py work/strokes.json lib/src/hands/my_hand.dart myHand "My Font" "Licensed under …"
swift tool/trace/order_sheet.swift work/strokes.json "永字八法" check.png   # each stroke numbered, to check
```

Kanji come out in the order a hand is taught:
- top before bottom, and left before right;
- a crossbar before the vertical through it;
- a box's sides before what's in it, and its bottom after;
- 辶 last.

Those rules cover the common kanji. Some rarer ones have exceptions the rules don't know, so they may come out of
order.
