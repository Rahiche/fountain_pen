import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';

void paintAt(void Function(Canvas c) paint) {
  final rec = ui.PictureRecorder();
  paint(Canvas(rec));
  rec.endRecording().dispose();
}

void main() {
  group('PenWriting', () {
    test('takes time to write, and takes up room', () {
      final w = PenWriting('Hello world');
      expect(w.duration, greaterThan(0.5));
      expect(w.size.width, greaterThan(w.size.height));
      expect(w.size.height, greaterThan(0));
    });

    test('the same seed writes the same way; another seed, another way', () {
      final a = PenWriting('Handwriting', seed: 3),
          b = PenWriting('Handwriting', seed: 3),
          c = PenWriting('Handwriting', seed: 4);
      expect(a.duration, b.duration);
      expect(a.bounds, b.bounds);
      expect(a.tip(1.0), b.tip(1.0));
      expect(c.bounds == a.bounds && c.duration == a.duration, isFalse);
    });

    test('written in the time asked for', () {
      final w = PenWriting('This text is rendered\nwith Flutter', duration: 2);
      expect(w.duration, closeTo(2, 1e-6));
    });

    test('no wider than asked', () {
      final w = PenWriting('A rather long line of handwriting', fontSize: 120, maxWidth: 400);
      expect(w.em, lessThan(120));
      expect(w.size.width, lessThanOrEqualTo(400));
    });

    test("characters the hand can't write are left as spaces", () {
      final w = PenWriting('naïve 文字 ok');
      expect(w.duration, greaterThan(0));
      expect(homemadeApple.canWrite('文'), isFalse);
      expect(homemadeApple.canWrite('a'), isTrue);
    });

    test('nothing to write: nothing written', () {
      final w = PenWriting('');
      expect(w.duration, 0);
      expect(w.size, Size.zero);
    });

    test('paints at any moment', () {
      final w = PenWriting('Ink & paper!', ink: PenInk.white);
      for (final t in [0.0, 0.3, w.duration / 2, w.duration, w.duration + 1]) {
        paintAt((c) => w.paint(c, Offset.zero, t));
        expect(w.tip(t).isFinite, isTrue);
        expect(w.follow(t).isFinite, isTrue);
      }
    });
  });

  group('shots', () {
    test('a close-up and the three film angles paint throughout', () {
      final w = PenWriting('Every letter', ink: PenInk.white);
      final shots = <PenShot>[
        PenCloseUp(PenWriting('Every letter')),
        for (final a in PenFilmAngle.values) PenFilm(w, angle: a),
      ];
      for (final s in shots) {
        expect(s.duration, greaterThan(0));
        for (var t = 0.0; t <= s.duration; t += s.duration / 7) {
          paintAt((c) => s.paint(c, const Size(1280, 720), t));
        }
      }
    });
  });

  group('FountainPenText', () {
    testWidgets('sizes itself to the writing and finishes it', (tester) async {
      var done = 0;
      final key = GlobalKey<FountainPenTextState>();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child:
                FountainPenText('Hi there', key: key, duration: const Duration(seconds: 1), onComplete: () => done++)),
      ));
      final size = tester.getSize(find.byType(CustomPaint).last);
      expect(size.width, greaterThan(size.height));
      // (The ticker's first frame, then half a second.)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(key.currentState!.progress, closeTo(0.5, 0.05));
      await tester.pump(const Duration(milliseconds: 600));
      expect(done, 1);
      key.currentState!.reset();
      expect(key.currentState!.progress, 0);
    });

    testWidgets('waits to be played when asked to', (tester) async {
      final key = GlobalKey<FountainPenTextState>();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: FountainPenText('Later', key: key, autoplay: false),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(key.currentState!.progress, 0);
      key.currentState!.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(key.currentState!.progress, greaterThan(0));
      await tester.pumpAndSettle();
    });
  });
}
