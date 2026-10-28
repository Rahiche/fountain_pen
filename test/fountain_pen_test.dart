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

  group('Japanese', () {
    test('the hand writes kana, kanji, their punctuation and ASCII', () {
      const kana = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん';
      const katakana = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン';
      for (final c in '$kana$katakana日本語文字書道東京描画、。「」ー！Aa1'.split('')) {
        expect(notoSansJapanese.canWrite(c), isTrue, reason: c);
      }
      expect(notoSansJapanese.glyphs.length, greaterThan(6700));
      expect(notoSansJapanese.canWrite('🙂'), isFalse);
      expect(homemadeApple.canWrite('あ'), isFalse);
    });

    test('in the strokes a Japanese hand is taught', () {
      const count = {
        '一': 1, '十': 2, '口': 3, '日': 4, '田': 5, '木': 4, '人': 2, '山': 3, '中': 4, '女': 3, '子': 3,
        'あ': 3, 'い': 2, 'ね': 2, 'の': 1, 'ん': 1, 'ア': 2, 'シ': 3, 'ツ': 3, 'ロ': 3, // (and 力: 2)
        '力': 2,
      };
      for (final MapEntry(key: c, value: n) in count.entries) {
        expect(notoSansJapanese.glyphs[c]!.strokes.length, n, reason: c);
      }
    });

    test('written a stroke at a time, the pen lifted between', () {
      final w = PenWriting('日本語の手書き', hand: notoSansJapanese);
      final latin = PenWriting('Japanese', hand: notoSansJapanese);
      expect(w.duration, greaterThan(latin.duration));
      for (final t in [0.0, w.duration / 3, w.duration, w.duration + 1]) {
        paintAt((c) => w.paint(c, Offset.zero, t));
        expect(w.tip(t).isFinite, isTrue);
      }
    });

    test('a full-width space is as wide as a character', () {
      final a = PenWriting('日\u3000日', hand: notoSansJapanese, seed: 1),
          b = PenWriting('日 日', hand: notoSansJapanese, seed: 1);
      expect(a.size.width, greaterThan(b.size.width));
    });
  });

  group('Arabic', () {
    test('letters joined in the forms their neighbours call for', () {
      // ب alone; بب: first, last; ببب: first, between, last; لا: the ligature.
      expect(arabicShaped('ب').text, '\uFE8F');
      expect(arabicShaped('بب').text, '\uFE91\uFE90');
      expect(arabicShaped('ببب').text, '\uFE91\uFE92\uFE90');
      expect(arabicShaped('لا').text, '\uFEFB');
      expect(arabicShaped('بلا').text, '\uFE91\uFEFC');
      // (ا joins only to the letter before it: what comes after starts afresh.)
      expect(arabicShaped('ابا').text, '\uFE8D\uFE91\uFE8E');
      expect(arabicShaped('ببب').joined, [true, true, false]);
      // (Vowel marks left out.)
      expect(arabicShaped('بَ').text, '\uFE8F');
    });

    test('lines with Arabic run right to left', () {
      expect(isRightToLeft('هذا النص'), isTrue);
      expect(isRightToLeft('Flutter فلاتر'), isFalse);
      expect(isRightToLeft('2026 مرحبا'), isTrue);
    });

    test('the hand writes every joined form, right to left', () {
      for (final c in 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي'.split('')) {
        for (final f in [c, c * 2, c * 3]) {
          for (final g in arabicShaped(f).text.split('')) {
            expect(notoNaskhArabic.canWrite(g), isTrue, reason: '$c: ${g.codeUnitAt(0).toRadixString(16)}');
          }
        }
      }
      final w = PenWriting('بسم الله', hand: notoNaskhArabic);
      expect(w.duration, greaterThan(0.5));
      // (Begun at the right: the pen's first mark is right of its last.)
      expect(w.tip(0.05).dx, greaterThan(w.tip(w.duration).dx));
      paintAt((c) => w.paint(c, Offset.zero, w.duration / 2));
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
