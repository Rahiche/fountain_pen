# fountain_pen

Text written out by a fountain pen, stroke by stroke, in Flutter: Latin; Japanese (kana and kanji, each stroke in the
order a Japanese hand is taught); and Arabic, right to left, its letters joined.

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/paper.gif" alt="'This text is rendered with Flutter' written out by a fountain pen" width="720">
</p>

Not a font fading in, and not one letter at a time: each letter is drawn the way a hand draws it, stroke after stroke, in the
order a writer would. The nib lays down heavy downstrokes and hairline upstrokes. The ink glistens wet for a moment, and pools
a little where the pen lands. The hand slows into the turns and dots its i's once the word is done. No two letters come out
quite the same: each is a little turned, sized, lifted and spaced its own way, and the line wanders.

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/film.gif" alt="White ink on black paper, filmed from above as it's written" width="720">
</p>

## Use

```sh
flutter pub add fountain_pen
```

```dart
import 'package:fountain_pen/fountain_pen.dart';

FountainPenText(
  'This text is rendered\nwith Flutter',
  fontSize: 64,
  ink: PenInk.blueBlack,
  duration: const Duration(seconds: 4), // or `speed:`, in em a second
  onComplete: () {},
)
```

It sizes itself to the writing and starts on its own. Use `autoplay: false`, `delay` and `repeat`, or give it a
`GlobalKey<FountainPenTextState>` and call `play()` or `reset()`.

### More control

`PenWriting` lays the text out and times it. Paint it as written by any moment, to put it anywhere: a slide, a texture, a
`CustomPainter` of your own.

```dart
final writing = PenWriting('Dear reader,', fontSize: 48, seed: 3);
// writing.duration: how long it takes (s); writing.size: the room it takes up.
writing.paint(canvas, centre, t); // t: seconds into the writing
```

The same `seed` writes the same way every time.

### Japanese

`notoSansJapanese` writes Japanese: hiragana and katakana, the 6,355 kanji of JIS X 0208, Japanese punctuation and
full-width forms, and ASCII for the Latin in between.

```dart
FountainPenText('このテキストは\nFlutterで描画されています', hand: notoSansJapanese)
```

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/paper_ja.gif" alt="'このテキストはFlutterで描画されています' written out by a fountain pen" width="720">
</p>

It's written the way a Japanese hand writes: each stroke on its own, the pen lifted and carried to the next, a finer
nib, and horizontals rising a little to the right. Each character's strokes come in its stroke order (筆順): for kana,
as taught; for kanji, by the rules a hand is taught (top before bottom, left before right, a crossbar before the
vertical through it, a box's sides before what's in it and its bottom after, 辶 last, ...). Those rules cover the
common kanji; a few thousand of them have exceptions the rules don't know, so a rare kanji may come out of order.

The hand is about 1 MB of data, unpacked a character at a time as it's first written; an app that never uses it
leaves it out.

### Arabic

`notoNaskhArabic` writes Arabic (and the extra letters of Persian and Urdu) right to left: each letter in the form its
neighbours call for, joined on to the next without the pen lifting, and each word's dots and hamzas put in once the
word's written.

```dart
FountainPenText('هذا النص\nمرسوم بفلاتر', hand: notoNaskhArabic)
```

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/paper_ar.gif" alt="'هذا النص مرسوم بفلاتر' written out by a fountain pen" width="720">
</p>

A line runs right to left when its first letter is Arabic. Vowel marks are left out, and Latin within an Arabic line
isn't reordered.

### Cameras

Film the writing instead of just showing it. `PenShotView` plays any of these:

- **`PenCloseUp(writing)`**: close on the pen at a hand's pace, gliding along the line. Then the pen hurries, like a
  time-lapse, as the camera eases out to the whole text.
- **`PenFilm(writing, angle: PenFilmAngle.sky)`**: a camera in 3D over the paper that follows the pen. It films from the
  `sky`, `low` along the line, or in an `orbit` round the pen, then pulls back to the whole line. Best with `PenInk.white`
  on its black paper.

```dart
PenShotView(PenFilm(PenWriting('Every letter goes on a journey', ink: PenInk.white), angle: PenFilmAngle.low))
```

## How it works

A hand (`PenHand`) holds every character's strokes as centre lines, in the order a hand draws them. They are traced from a
font's outlines: each glyph is thinned to its centre line and cut into a graph. The graph is walked the way a pen would go,
from the top left, carrying on through each fork along the smoothest way. Small detached parts, like an i's dot, wait until
the word is written.

`PenWriting` draws those lines with a nib, not with the font's own outlines:

- **Width:** the line is broad going down and fine coming up, broader again across the nib's edge.
- **Timing:** the pen's pace slows in the turns.
- **Ink:** it feathers into the paper, dries darker at its edges, and catches the light while it's wet.

## Make your own hand

The bundled hand, `homemadeApple`, is traced from [Homemade Apple](https://fonts.google.com/specimen/Homemade+Apple)
(Apache 2.0). Its capitals are quirky. To trace another script font you're licensed to use (macOS for the first step;
Python 3 with numpy for the rest):

```sh
mkdir -p tool/trace/work/raster
swift tool/trace/glyphs.swift path/to/Font.ttf tool/trace/work      # rasterise each glyph
python3 tool/trace/strokes.py tool/trace/work                       # trace its strokes → strokes.json
python3 tool/trace/to_dart.py tool/trace/work/strokes.json lib/src/hands/my_hand.dart \
    myHand "My Font" "Licensed under …"                             # → const myHand = PenHand(...)
```

Then `FountainPenText('…', hand: myHand)`. Or skip the Dart step and load the JSON with `PenHand.fromJson`. To see a trace,
run `cd tool/trace/work && python3 ../debug.py "abc" debug.ppm`: it draws each glyph's strokes in order over its raster.

For an Arabic font, rasterise each letter's joined forms and trace them right to left:

```sh
python3 tool/trace/arabic_forms.py work/forms.tsv                           # each letter's forms, and how to shape them
swift tool/trace/shaped_glyphs.swift path/to/Font.ttf work/forms.tsv work   # each form rasterised
python3 tool/trace/strokes_arabic.py work                                  # strokes, right to left → strokes.json
python3 tool/trace/to_packed.py work/strokes.json lib/src/hands/my_hand.dart myHand "My Font" "Licensed under …"
```

For a Japanese (or other CJK) font, trace it with the CJK tools. They work best with a font that, like Noto Sans JP,
keeps each stroke as its own outline:

```sh
swift tool/trace/cjk_glyphs.swift path/to/Font.ttf chars.txt work 300      # each outline rasterised (weight 300)
python3 tool/trace/strokes_cjk.py work                                    # strokes, in stroke order → strokes.json
python3 tool/trace/to_packed.py work/strokes.json lib/src/hands/my_hand.dart myHand "My Font" "Licensed under …"
swift tool/trace/order_sheet.swift work/strokes.json "永字八法" check.png   # each stroke numbered, to check
```

## Limits

- **Latin, Japanese and Arabic, for now:** Basic Latin; Japanese (`notoSansJapanese`); Arabic, with Persian's and
  Urdu's letters (`notoNaskhArabic`). Characters a hand has no strokes for are left as spaces.
- **No joins between letters:** letters connect only where the font's own strokes meet. Strokes aren't joined across
  letters.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE); the Latin hand is derived from Homemade Apple, © 2010 Font Diner,
Inc., Apache 2.0. The Japanese hand is derived from Noto Sans JP, © 2014-2021 Adobe, and like it is licensed under the
SIL Open Font License 1.1 ([lib/src/hands/OFL.txt](lib/src/hands/OFL.txt)); so is the Arabic hand, derived from Noto
Naskh Arabic, © 2014 Google Inc.
