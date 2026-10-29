# fountain_pen

Text written out by a fountain pen, stroke by stroke, in Latin, Japanese and Arabic.

**[Try it in your browser →](https://rahiche.github.io/fountain_pen/)**

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/paper.gif" alt="'This text is rendered with Flutter' written out by a fountain pen" width="720">
</p>

## Use

```sh
flutter pub add fountain_pen
```

```dart
FountainPenText(
  'This text is rendered\nwith Flutter',
  fontSize: 64,
  ink: PenInk.blueBlack,
  duration: const Duration(seconds: 4),
)
```

It starts on its own. Use `autoplay`, `delay`, `repeat` and `onComplete`, or `play()` and `reset()` through a
`GlobalKey<FountainPenTextState>`.

## Japanese and Arabic

```dart
FountainPenText('このテキストは\nFlutterで描画されています', hand: notoSansJapanese)
FountainPenText('هذا النص\nمرسوم بفلاتر', hand: notoNaskhArabic) // Persian and Urdu too
```

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/paper_ja.gif" alt="Japanese written out stroke by stroke" width="360">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/paper_ar.gif" alt="Arabic written out right to left" width="360">
</p>

Kanji and kana follow their stroke order (筆順). Arabic is written right to left, with each word's letters joined and
its dots added last.

## Inks and hands

```dart
FountainPenText('sepia', ink: const PenInk(color: Color(0xFF5B3A1E)))
FountainPenText('broad nib', ink: const PenInk(heavy: 0.36, fine: 0.05))
FountainPenText('another hand', seed: 3)
```

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/inks.gif" alt="Six inks and nibs" width="360">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/seeds.gif" alt="The same line in four hands" width="360">
</p>

## Cameras

```dart
PenShotView(PenFilm(PenWriting('Every letter goes on a journey', ink: PenInk.white), angle: PenFilmAngle.low))
```

`PenFilm` films from the `sky`, `low` along the line, or in an `orbit`; `PenCloseUp` follows the nib.

<p align="center">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/film.gif" alt="White ink on black paper, filmed from above" width="360">
  <img src="https://raw.githubusercontent.com/Rahiche/fountain_pen/main/doc/closeup.gif" alt="Close on the pen, then easing out" width="360">
</p>

## More

- `PenWriting` paints the writing at any moment, for your own `CustomPainter`.
- The pen moves as a hand does: quick on the straights, slower in the turns (the two-thirds power law).
- To trace your own font into a hand, see [tool/trace](https://github.com/Rahiche/fountain_pen/tree/main/tool/trace).
- Characters a hand has no strokes for are left as spaces.

## License

Apache 2.0. The hands are traced from three fonts:
- [Homemade Apple](https://fonts.google.com/specimen/Homemade+Apple), Apache 2.0;
- Noto Sans JP and Noto Naskh Arabic, both under the
  [SIL Open Font License](https://github.com/Rahiche/fountain_pen/blob/main/lib/src/hands/OFL.txt).

See [NOTICE](https://github.com/Rahiche/fountain_pen/blob/main/NOTICE).
