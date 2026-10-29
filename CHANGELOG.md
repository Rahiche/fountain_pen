## 0.2.1

- A shorter README: what it does, demos and links. The details move to their own pages: getting started, inks
  and cameras, Japanese and Arabic, and how it works (in `doc/`), and tracing your own hand (`tool/trace`).

## 0.2.0

- Japanese: `notoSansJapanese`, a hand traced from Noto Sans JP: hiragana and katakana, the 6,355 kanji of JIS X 0208,
  Japanese punctuation and full-width forms, and ASCII, each written stroke by stroke in its stroke order (筆順). Written
  as a Japanese hand writes: a finer nib, the pen lifted and carried between strokes, horizontals rising a little to
  the right.
- Arabic: `notoNaskhArabic`, a hand traced from Noto Naskh Arabic, with Persian's and Urdu's letters: written right to
  left, each letter in its joined form (`arabicShaped`), on to the next without the pen lifting, each word's dots once
  it's written.
- The pen's pace follows the two-thirds power law of a moving hand: its speed falls with the curvature of its path, to
  the −1/3, rather than only slowing in the turns. `tool/eval/motor_law.py` measures it in any pen's paths.
- `PenHand.packed`: a hand of thousands of glyphs, each unpacked the first time it's written; a hand an app doesn't use
  is left out of it.
- `tool/trace`: `cjk_glyphs.swift` and `strokes_cjk.py` trace a Japanese font of your own; `arabic_forms.py`,
  `shaped_glyphs.swift` and `strokes_arabic.py` an Arabic one; `to_packed.py` packs either.
- The example is a gallery of every hand and camera, with a playground; it runs on the web at
  https://rahiche.github.io/fountain_pen/.

## 0.1.0

- `FountainPenText`: text written out by a fountain pen, stroke by stroke.
- `PenWriting`: lay text out in a hand and paint it at any moment of its writing.
- `PenCloseUp` and `PenFilm` (sky, low, orbit): cameras that follow the pen; `PenShotView` plays them.
- A bundled Latin hand traced from Homemade Apple, and `tool/trace` to trace your own.
