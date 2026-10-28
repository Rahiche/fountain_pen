// Renders the README's demos to PNG frames (FRAMES_DIR/<name>/f%05d.png).
//   FRAMES_DIR=/some/dir flutter test tool/demo/render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';

Future<void> render(String name, Size size, double seconds, void Function(Canvas c, double t) paint) async {
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

void main() {
  testWidgets('demos', (tester) async {
    await tester.runAsync(() async {
      // On paper, as the widget writes it.
      const size = Size(960, 420);
      final w = PenWriting('This text is rendered\nwith Flutter', fontSize: 110, maxWidth: 860, duration: 5.5);
      await render('paper', size, 6.5, (c, t) {
        c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF7F3EA));
        final k = (size.width * 0.92 / w.size.width).clamp(0.0, size.height * 0.88 / w.size.height);
        c
          ..translate(size.width / 2, size.height / 2)
          ..scale(k)
          ..translate(-w.bounds.center.dx, -w.bounds.center.dy);
        w.paint(c, Offset.zero, t);
      });
      // Filmed from the sky, white ink on black paper.
      const film = Size(960, 540);
      final shot = PenFilm(PenWriting('Every letter goes on a journey', fontSize: 110, ink: PenInk.white), angle: PenFilmAngle.sky, done: 4.2, reveal: 3.4);
      await render('film', film, shot.duration, (c, t) => shot.paint(c, film, t));
    });
  });
}
