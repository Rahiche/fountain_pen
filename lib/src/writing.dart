import 'dart:math' as math;
import 'dart:ui';

import 'hand.dart';
import 'hands/homemade_apple.dart';
import 'ink.dart';

/// How the lines of a [PenWriting] line up.
enum PenAlign { start, center }

/// [text] laid out in a [hand] and timed as it would be written: every
/// stroke of every letter, in order, at a hand's pace (slower in the turns,
/// a little uneven), the pen lifting between strokes, an i's dot once its
/// word is done. Never quite the same twice over: each letter a little
/// turned, sized, lifted and spaced its own way, the line wandering, the
/// hand wavering (all from [seed], so the same seed writes the same way).
///
/// Paint it as written by any moment with [paint]. Latin text: characters
/// the hand has no strokes for are left as spaces.
class PenWriting {
  PenWriting(
    this.text, {
    this.hand = homemadeApple,
    this.fontSize = 48,
    this.ink = PenInk.blueBlack,
    double speed = 3,
    double? duration,
    double? maxWidth,
    this.lineHeight = 1.3,
    this.align = PenAlign.center,
    this.seed = 7,
  }) {
    final widths = [for (final line in text.split('\n')) _width(line)];
    final widest = widths.isEmpty ? 0.0 : widths.reduce(math.max);
    em = maxWidth == null || widest <= 0 ? fontSize : math.min(fontSize, maxWidth / widest);
    _layout(speed);
    // (Still too wide, the ink reaching past the letters' advances: smaller.)
    if (maxWidth != null && bounds.width > maxWidth && bounds.width > 0) {
      em *= maxWidth / bounds.width * 0.999;
      _relayout(speed);
    }
    if (duration != null && duration > 0 && this.duration > 0) {
      // (Written again at the pace that takes [duration]: the pauses too.)
      _relayout(speed * this.duration / duration);
    }
  }

  void _relayout(double speed) {
    _strokes.clear();
    _lineMid.clear();
    _track = null;
    _boundsCache = null;
    _layout(speed);
  }

  final String text;
  final PenHand hand;

  /// The size the text is written at (px to the em), unless [maxWidth] made
  /// it smaller ([em]).
  final double fontSize;
  final PenInk ink;
  final double lineHeight;
  final PenAlign align;
  final int seed;

  /// The size it's written at (px to the em).
  late double em;

  /// How long it takes to write (s).
  late double duration;

  final _strokes = <_Stroke>[];
  final _lineMid = <double>[];

  /// Where the ink reaches, round the point [paint] centres it on.
  Rect get bounds => _boundsCache ??= _bounds();
  Rect? _boundsCache;

  /// The size it takes up, written.
  Size get size => bounds.size;

  double _width(String line) => line.split('').fold(0.0, (w, ch) => w + (hand.glyphs[ch]?.advance ?? hand.space));

  void _layout(double speed) {
    final r = math.Random(seed);
    double rnd() => r.nextDouble() * 2 - 1;
    // (Pauses as quick as the writing: a hand in a hurry pauses less.)
    final pause = 3 / speed;
    final lines = text.split('\n');
    final x = hand.xHeight, xh = x * em;
    final widest = lines.map(_width).fold(0.0, math.max);
    var t = 0.0;
    Offset? last;
    for (final (k, line) in lines.indexed) {
      final chars = line.split('');
      final gaps = [for (var i = 0; i < chars.length; i++) 0.02 * rnd()];
      final width = _width(line) + gaps.fold(0.0, (a, b) => a + b);
      final baseline = (k - (lines.length - 1) / 2) * lineHeight * em + xh / 2;
      _lineMid.add(baseline - xh / 2);
      final tilt = 0.015 * rnd(), wave = r.nextDouble() * 6;
      var pen = align == PenAlign.center ? -width / 2 : -widest / 2;
      final late = <_Stroke>[];
      void dots() {
        for (final s in late) {
          s.t0 = t + 0.06 * pause;
          t = s.t0 + s.time;
          s.lands = true;
          _strokes.add(s);
        }
        late.clear();
        last = null;
      }

      for (final (i, ch) in chars.indexed) {
        final g = hand.glyphs[ch];
        if (g == null) {
          dots();
          t += 0.07 * pause;
          pen += hand.space + gaps[i];
          continue;
        }
        // This letter its own way: turned, sized, lifted a little.
        final rot = 0.04 * rnd() * ink.waver, scale = 1 + 0.045 * rnd() * ink.waver;
        final lift = (0.025 * rnd() + 0.03 * math.sin(pen * 1.1 + wave)) * ink.waver;
        final cx = g.advance / 2, cy = x / 2;
        Offset place(double px, double py) {
          final dx = (px - cx) * scale, dy = (py - cy) * scale;
          final ux = cx + dx * math.cos(rot) - dy * math.sin(rot),
              uy = cy + dx * math.sin(rot) + dy * math.cos(rot) + lift;
          return Offset((pen + ux) * em, baseline - (uy + (pen + ux) * tilt * ink.waver) * em);
        }

        for (final s in g.strokes) {
          final pts = [for (var j = 0; j + 2 < s.points.length; j += 3) place(s.points[j], s.points[j + 1])];
          if (pts.isEmpty) continue;
          final stroke = _Stroke(s.dot ? pts : _smooth(pts, 1.2), xh, speed * em, ink, r, dot: s.dot);
          if (s.late) {
            late.add(stroke);
            continue;
          }
          // On from where it was, or from ink this letter's already laid (a
          // fork the trace split at): no lift, no pool.
          final from = pts.first;
          final on = (last != null && (from - last!).distance < 0.05 * em) ||
              _strokes.reversed.take(4).any((o) => o.p.any((q) => (q - from).distance < 0.04 * em));
          stroke.lands = !on;
          stroke.t0 = on ? t : t + (0.03 + 0.03 * r.nextDouble()) * pause;
          t = stroke.t0 + stroke.time;
          last = stroke.p.last;
          _strokes.add(stroke);
        }
        pen += g.advance + gaps[i];
      }
      dots();
      if (k < lines.length - 1) t += 0.15 * pause;
    }
    duration = t;
  }

  Rect _bounds() {
    if (_strokes.isEmpty) return Rect.zero;
    var l = double.infinity, tp = double.infinity, rt = -double.infinity, b = -double.infinity;
    for (final s in _strokes) {
      for (final p in s.p) {
        l = math.min(l, p.dx);
        tp = math.min(tp, p.dy);
        rt = math.max(rt, p.dx);
        b = math.max(b, p.dy);
      }
    }
    final pad = hand.xHeight * em * (ink.fine + ink.heavy) + 2;
    return Rect.fromLTRB(l - pad, tp - pad, rt + pad, b + pad);
  }

  /// A smooth line through [p] (Catmull-Rom), a point every [step] px.
  static List<Offset> _smooth(List<Offset> p, double step) {
    if (p.length < 2) return p;
    final out = <Offset>[p.first];
    for (var i = 0; i + 1 < p.length; i++) {
      final p0 = i == 0 ? p[0] * 2 - p[1] : p[i - 1],
          p1 = p[i],
          p2 = p[i + 1],
          p3 = i + 2 < p.length ? p[i + 2] : p[i + 1] * 2 - p[i];
      final n = math.max(1, ((p2 - p1).distance / step).ceil());
      for (var k = 1; k <= n; k++) {
        final u = k / n, u2 = u * u, u3 = u2 * u;
        out.add(
            (p1 * 2 + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 + (p1 * 3 - p0 - p2 * 3 + p3) * u3) * 0.5);
      }
    }
    return out;
  }

  /// Where the pen is [t] seconds in (round the point [paint] centres the
  /// text on): on the stroke it's drawing, else where it last lifted.
  Offset tip(double t) {
    var at = _strokes.isEmpty ? Offset.zero : _strokes.first.p.first;
    for (final s in _strokes) {
      if (t < s.t0) break;
      at = s.at(t - s.t0);
    }
    return at;
  }

  /// Where a camera following the writing looks [t] seconds in: along the
  /// line as far as the pen has got (never back), at the line's middle,
  /// smoothed: a steady glide, not the nib's every loop.
  Offset follow(double t) {
    final tr = _track ??= _makeTrack();
    final i = (t / _step).clamp(0.0, tr.length - 1.001);
    return Offset.lerp(tr[i.floor()], tr[i.floor() + 1], i - i.floor())!;
  }

  static const _step = 0.02;
  List<Offset>? _track;

  List<Offset> _makeTrack() {
    final raw = <Offset>[];
    var line = -1;
    var far = 0.0;
    for (var t = 0.0; t <= duration + 0.5; t += _step) {
      final p = tip(t);
      var k = 0;
      for (var j = 1; j < _lineMid.length; j++) {
        if ((p.dy - _lineMid[j]).abs() < (p.dy - _lineMid[k]).abs()) k = j;
      }
      if (k != line) {
        line = k;
        far = p.dx;
      }
      far = math.max(far, p.dx);
      raw.add(Offset(far, _lineMid.isEmpty ? 0 : _lineMid[k]));
    }
    if (raw.length < 2) raw.add(raw.isEmpty ? Offset.zero : raw.first);
    // (A wide bell: half a second of the pen either side.)
    const sigma = 0.45 / _step;
    final w = [for (var j = -3 * sigma.round(); j <= 3 * sigma.round(); j++) math.exp(-j * j / (2 * sigma * sigma))];
    final half = w.length ~/ 2;
    return [
      for (var i = 0; i < raw.length; i++)
        () {
          var sum = Offset.zero, n = 0.0;
          for (var j = 0; j < w.length; j++) {
            sum += raw[(i + j - half).clamp(0, raw.length - 1)] * w[j];
            n += w[j];
          }
          return sum / n;
        }(),
    ];
  }

  /// Paints it as written by [t] seconds in, centred on [centre] (only the
  /// strokes [keep] says, if given: what a camera has in front of it).
  void paint(Canvas canvas, Offset centre, double t, {bool Function(Offset first, Offset last)? keep}) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    for (final s in _strokes) {
      if (t > s.t0 && (keep == null || keep(s.p.first, s.p.last))) s.paint(canvas, t - s.t0);
    }
    canvas.restore();
  }
}

class _Stroke {
  _Stroke(List<Offset> pts, this.xh, double v, this.style, math.Random r, {this.dot = false})
      : ink = Color.lerp(
            style.color, style.isLight ? const Color(0xFFD8CDB8) : const Color(0xFF070B1E), 0.3 * r.nextDouble())! {
    // The hand wavers: a slow drift off the line, its own for each stroke.
    final ph = [for (var i = 0; i < 4; i++) r.nextDouble() * 6.3];
    var s = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) s += (pts[i] - pts[i - 1]).distance;
      final k = s / xh;
      p.add(pts[i] +
          Offset(math.sin(k * 1.9 + ph[0]) + 0.4 * math.sin(k * 4.3 + ph[1]),
                  math.sin(k * 1.7 + ph[2]) + 0.4 * math.sin(k * 3.9 + ph[3])) *
              (0.014 * xh * style.waver));
    }
    // When each point's reached: slower in the turns, a little uneven.
    final speed = v * (0.88 + 0.24 * r.nextDouble());
    tt.add(0);
    for (var i = 1; i < p.length; i++) {
      final a = i > 1 ? p[i - 1] - p[i - 2] : p[1] - p[0], b = p[i] - p[i - 1];
      final turn = a.distance > 0 && b.distance > 0 ? 1 - (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance) : 0.0;
      tt.add(tt.last + b.distance / (speed * (1 - math.min(0.55, turn * 8))));
    }
    if (dot) tt.last = 0.05 * 3 * xh / math.max(v, 1e-6);
    // Its half-width along it: fine coming up, heavy going down (more so
    // across the nib's edge), pressed a little unevenly; smoothed.
    final q = r.nextDouble() * 6.3, raw = <double>[];
    for (var i = 0; i < p.length; i++) {
      final d = i + 1 < p.length ? p[i + 1] - p[i] : (i > 0 ? p[i] - p[i - 1] : const Offset(0, 1));
      final len = math.max(d.distance, 1e-6);
      final down = (d.dy / len).clamp(0.0, 1.0);
      final across = ((d.dx * math.sin(style.nibAngle) + d.dy * math.cos(style.nibAngle)) / len).abs();
      raw.add(xh *
          (style.fine + style.heavy * (0.7 * down * down + 0.3 * across) * (0.85 + 0.15 * math.sin(i * 0.035 + q))) /
          2);
    }
    for (var i = 0; i < raw.length; i++) {
      var sum = 0.0, n = 0;
      for (var j = math.max(0, i - 6); j <= math.min(raw.length - 1, i + 6); j++) {
        sum += raw[j];
        n++;
      }
      half.add(dot ? xh * 0.11 : sum / n);
    }
  }

  final double xh;
  final PenInk style;
  final bool dot;
  final Color ink;
  final p = <Offset>[];
  final tt = <double>[];
  final half = <double>[];
  double t0 = 0;
  bool lands = true;

  double get time => tt.last;

  Offset at(double t) {
    var n = 1;
    while (n < p.length && tt[n] <= t) {
      n++;
    }
    if (n >= p.length) return p.last;
    return Offset.lerp(p[n - 1], p[n], ((t - tt[n - 1]) / (tt[n] - tt[n - 1])).clamp(0.0, 1.0))!;
  }

  void paint(Canvas c, double t) {
    var n = 1;
    while (n < p.length && tt[n] <= t) {
      n++;
    }
    final done = n >= p.length;
    final pts = p.sublist(0, n), w = half.sublist(0, n);
    if (!done) {
      final f = ((t - tt[n - 1]) / (tt[n] - tt[n - 1])).clamp(0.0, 1.0);
      pts.add(Offset.lerp(p[n - 1], p[n], f)!);
      w.add(half[n - 1] + (half[n] - half[n - 1]) * f);
    }
    final paint = Paint()..color = ink;
    if (dot || pts.length < 2) {
      c.drawCircle(pts.first, w.first * (dot ? math.min(1, t / math.max(time, 1e-6)) : 1), paint);
      return;
    }
    final light = style.isLight;
    // Its outline: either side of the line, as wide as the nib draws it.
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final d = pts[math.min(i + 1, pts.length - 1)] - pts[math.max(i - 1, 0)];
      final len = math.max(d.distance, 1e-6);
      final nrm = Offset(-d.dy / len, d.dx / len) * w[i];
      left.add(pts[i] + nrm);
      right.add(pts[i] - nrm);
    }
    final body = Path()..addPolygon([...left, ...right.reversed], true);
    // (The ink feathers a little into the paper.)
    c.drawPath(
        body,
        Paint()
          ..color = ink.withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.025 * xh));
    c.drawPath(body, paint);
    c.drawCircle(pts.first, w.first, paint);
    c.drawCircle(pts.last, w.last, paint);
    // (Dried, the ink's darker at its edges than down its middle.)
    final coreL = <Offset>[], coreR = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final d = (left[i] - right[i]) * 0.5;
      coreL.add(pts[i] + d * 0.5);
      coreR.add(pts[i] - d * 0.5);
    }
    c.drawPath(
        Path()..addPolygon([...coreL, ...coreR.reversed], true),
        Paint()
          ..color = (light ? const Color(0xFFFFFFFF) : Color.lerp(ink, const Color(0xFF5A6FB0), 0.5)!)
              .withValues(alpha: light ? 0.35 : 0.28)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.012 * xh));
    if (style.wet) {
      // Wet a moment where it's just been: deeper, catching the light.
      var i0 = pts.length - 1;
      while (i0 > 0 && i0 < tt.length && t - tt[i0] < 0.4) {
        i0--;
      }
      if (i0 < pts.length - 2) {
        final wet = Path()..addPolygon([...left.sublist(i0), ...right.sublist(i0).reversed], true);
        c.drawPath(
            wet, Paint()..color = (light ? const Color(0xFFFFE9C2) : const Color(0xFF0E2A86)).withValues(alpha: 0.3));
        for (var i = i0 + 1; i < pts.length; i++) {
          final age = i < tt.length ? (t - tt[i]).clamp(0.0, 0.4) : 0.0;
          c.drawLine(
            pts[i - 1] + (left[i - 1] - pts[i - 1]) * 0.45,
            pts[i] + (left[i] - pts[i]) * 0.45,
            Paint()
              ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5 * (1 - age / 0.4))
              ..strokeWidth = math.max(0.6, w[i] * 0.22)
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
    // A little ink pooled where the pen landed.
    if (style.pools && lands) {
      c.drawCircle(
        pts.first,
        w.first * 1.1,
        Paint()
          ..color = (light ? const Color(0xFFFFFFFF) : Color.lerp(ink, const Color(0xFF000510), 0.4)!)
              .withValues(alpha: 0.22),
      );
    }
  }
}
