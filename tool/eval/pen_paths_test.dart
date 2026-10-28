// Where fountain_pen's pen is over time, for motor_law.py: each job's text
// written in its hand, the pen's tip sampled 240 times a second, in em.
//
//   JOBS=jobs.json OUT=paths.json flutter test tool/eval/pen_paths_test.dart
//
// jobs.json: {"label": {"text": "...", "hand": "<a traced strokes.json>", "seconds": 8}, ...}
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fountain_pen/fountain_pen.dart';

void main() {
  test('pen paths', () {
    final jobs = jsonDecode(File(Platform.environment['JOBS']!).readAsStringSync()) as Map<String, dynamic>;
    final out = <String, List<List<double>>>{};
    for (final MapEntry(key: label, value: job) in jobs.entries) {
      final hand = PenHand.fromJson(jsonDecode(File(job['hand'] as String).readAsStringSync()));
      final w =
          PenWriting(job['text'] as String, hand: hand, fontSize: 200, duration: (job['seconds'] as num).toDouble());
      out[label] = [
        for (var t = 0.0; t <= w.duration; t += 1 / 240) [t, w.tip(t).dx / w.em, -w.tip(t).dy / w.em],
      ];
    }
    File(Platform.environment['OUT']!).writeAsStringSync(jsonEncode(out));
  });
}
