// Renders the README's demos to PNG frames (FRAMES_DIR/<name>/f%05d.png);
// tool/demo/make_gifs.sh turns them into doc/<name>.gif.
//   FRAMES_DIR=/some/dir flutter test tool/demo/render_test.dart
// ONLY=paper,closeup renders just those.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';

final _only = {...?Platform.environment['ONLY']?.split(',').where((s) => s.isNotEmpty)};

Future<void> render(String name, Size size, double seconds, void Function(Canvas c, double t) paint) async {
  if (_only.isNotEmpty && !_only.contains(name)) return;
  final dir = Directory('${Platform.environment['FRAMES_DIR'] ?? 'build/demo'}/$name')..createSync(recursive: true);
  final frames = (seconds * 30).round();
  for (var f = 0; f < frames; f++) {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec), f / 30);
    final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/f${(f + 1).toString().padLeft(5, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
    img.dispose();
  }
}

const paperColor = Color(0xFFF7F3EA), darkPaper = Color(0xFF101114);

/// [w] fitted into [box] of [c] (92% of its width, 88% of its height) and
/// painted as written by [t].
void fit(Canvas c, PenWriting w, Rect box, double t) {
  final k = math.min(box.width * 0.92 / w.size.width, box.height * 0.88 / w.size.height);
  c
    ..save()
    ..translate(box.center.dx, box.center.dy)
    ..scale(k)
    ..translate(-w.bounds.center.dx, -w.bounds.center.dy);
  w.paint(c, Offset.zero, t);
  c.restore();
}

/// [w] written on paper, held a second once it's done.
Future<void> onPaper(String name, PenWriting w, {Size size = const Size(960, 420)}) => render(
      name,
      size,
      w.duration + 1,
      (c, t) {
        c.drawRect(Offset.zero & size, Paint()..color = paperColor);
        fit(c, w, Offset.zero & size, t);
      },
    );

void main() {
  testWidgets('demos', (tester) async {
    await tester.runAsync(() async {
      // Each hand on paper, as the widget writes it.
      await onPaper('paper', PenWriting('This text is rendered\nwith Flutter', fontSize: 110, maxWidth: 860, duration: 5.5));
      await onPaper('paper_ja',
          PenWriting('このテキストは\nFlutterで描画されています', hand: notoSansJapanese, fontSize: 110, maxWidth: 860, duration: 9));
      await onPaper('paper_ar', PenWriting('هذا النص\nمرسوم بفلاتر', hand: notoNaskhArabic, fontSize: 130, maxWidth: 860, duration: 7));
      await onPaper('paper_ur', PenWriting('یہ تحریر قلم سے\nلکھی گئی ہے', hand: notoNaskhArabic, fontSize: 130, maxWidth: 860, duration: 7));

      // The cameras: close on the pen, then filmed in 3D from the sky, low along the line and in an orbit.
      const film = Size(960, 540);
      final close = PenCloseUp(PenWriting('Every letter goes on a journey', fontSize: 110));
      await render('closeup', film, close.duration, (c, t) => close.paint(c, film, t));
      for (final (name, text, angle) in [
        ('film', 'Every letter goes on a journey', PenFilmAngle.sky),
        ('film_low', 'Ink, nib and paper', PenFilmAngle.low),
        ('film_orbit', 'Stroke by stroke', PenFilmAngle.orbit),
      ]) {
        final shot = PenFilm(PenWriting(text, fontSize: 110, ink: PenInk.white), angle: angle, done: 4.2, reveal: 3.4);
        await render(name, film, shot.duration, (c, t) => shot.paint(c, film, t));
      }
      final shotJa = PenFilm(PenWriting('手書きの日本語', hand: notoSansJapanese, fontSize: 110, ink: PenInk.white),
          angle: PenFilmAngle.sky, done: 5.2, reveal: 4.2);
      await render('film_ja', film, shotJa.duration, (c, t) => shotJa.paint(c, film, t));
      final shotAr = PenFilm(PenWriting('بالقلم والحبر', hand: notoNaskhArabic, fontSize: 130, ink: PenInk.white),
          angle: PenFilmAngle.sky, done: 4.6, reveal: 3.6);
      await render('film_ar', film, shotAr.duration, (c, t) => shotAr.paint(c, film, t));

      // Inks and nibs: each cell writes its own name, all at once.
      const grid = Size(960, 420);
      final cells = [
        ('blue-black', PenInk.blueBlack, false),
        ('sepia', const PenInk(color: Color(0xFF5B3A1E)), false),
        ('crimson', const PenInk(color: Color(0xFF9E1B32)), false),
        ('broad nib', const PenInk(heavy: 0.36, fine: 0.05), false),
        ('steady hand', const PenInk(waver: 0), false),
        ('white ink', PenInk.white, true),
      ];
      final inks = [for (final (text, ink, _) in cells) PenWriting(text, fontSize: 90, ink: ink, duration: 3.2)];
      await render('inks', grid, 4.4, (c, t) {
        c.drawRect(Offset.zero & grid, Paint()..color = paperColor);
        for (var i = 0; i < cells.length; i++) {
          final box = Rect.fromLTWH((i % 3) * grid.width / 3, (i ~/ 3) * grid.height / 2, grid.width / 3, grid.height / 2);
          if (cells[i].$3) c.drawRRect(RRect.fromRectAndRadius(box.deflate(10), const Radius.circular(10)), Paint()..color = darkPaper);
          fit(c, inks[i], box.deflate(18), t);
        }
      });

      // The same line, four seeds: four hands.
      const tall = Size(960, 540);
      final seeds = [for (final s in [1, 2, 3, 4]) PenWriting('Never quite the same twice', fontSize: 90, seed: s, duration: 4)];
      await render('seeds', tall, 5, (c, t) {
        c.drawRect(Offset.zero & tall, Paint()..color = paperColor);
        for (var i = 0; i < seeds.length; i++) {
          fit(c, seeds[i], Rect.fromLTWH(0, i * tall.height / 4, tall.width, tall.height / 4), t);
        }
      });
    });
  });
}
