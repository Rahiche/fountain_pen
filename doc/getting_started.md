# Getting started

## Install

```sh
flutter pub add fountain_pen
```

Needs Flutter 3.27 or later.

## Write some text

```dart
import 'package:fountain_pen/fountain_pen.dart';

FountainPenText(
  'This text is rendered\nwith Flutter',
  fontSize: 64,
  ink: PenInk.blueBlack,
  duration: const Duration(seconds: 4), // or `speed:`, in em a second (3 by default)
  onComplete: () {},
)
```

It sizes itself to the writing and starts on its own. These set the layout:
- `maxWidth` wraps long lines;
- `lineHeight` sets the line spacing (1.3 by default);
- `align` places the lines (`PenAlign.center` by default).

## Control playback

- `autoplay: false` waits until you call `play()`.
- `delay` waits before it starts.
- `repeat: true` writes it again and again, with a short pause between.
- To start it yourself, give it a `GlobalKey<FountainPenTextState>` and call `play()`, or `reset()` to blank it.

## Paint it yourself

`PenWriting` lays the text out and times it. Paint it as written by any moment, to put it anywhere: a slide, a texture,
or a `CustomPainter` of your own.

```dart
final writing = PenWriting('Dear reader,', fontSize: 48, seed: 3);
// writing.duration: how long it takes (s); writing.size: the room it takes up.
writing.paint(canvas, centre, t); // t: seconds into the writing
```

The same `seed` writes the same way every time.

## Next

- [Inks, hands and cameras](inks_and_cameras.md)
- [Japanese and Arabic](scripts.md)
- [How it works](how_it_works.md)
- [Trace your own hand](../tool/trace/README.md)
