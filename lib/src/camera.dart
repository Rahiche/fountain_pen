import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:vector_math/vector_math.dart' as vm;

import 'writing.dart';

/// A [PenWriting] filmed: what's on screen at each moment of [duration].
abstract class PenShot {
  /// How long the shot runs (s).
  double get duration;

  /// Paints the shot [t] seconds in, filling [size].
  void paint(Canvas canvas, Size size, double t);
}

/// The writing, close on the pen, following it along the line at a hand's
/// pace until [slow] seconds; then the pen hurrying (a time-lapse, [ramp]
/// seconds to get up to speed) as the camera eases out to the whole text,
/// done by [done]. [zoom]: how close it starts. On [paper].
class PenCloseUp implements PenShot {
  PenCloseUp(
    this.writing, {
    this.slow = 3.75,
    this.ramp = 0.8,
    this.done = 5.6,
    this.zoom = 3.2,
    this.lead = 0.25,
    this.hold = 0.6,
    this.paper = const Color(0xFFFFFFFF),
  }) {
    final left = writing.duration - (slow - lead);
    final rest = done - slow - ramp / 2;
    _rate = left <= 0 || rest <= 0 ? 1 : math.max(1, left / rest);
  }

  final PenWriting writing;
  final double slow, ramp, done, zoom, lead, hold;
  final Color paper;
  late final double _rate;

  @override
  double get duration => done + hold;

  /// The pen's own clock at [t].
  double pen(double t) {
    if (t < lead) return 0;
    if (t < slow) return t - lead;
    final u = t - slow;
    if (u < ramp) return slow - lead + u + (_rate - 1) * u * u / (2 * ramp);
    return slow - lead + ramp + (_rate - 1) * ramp / 2 + _rate * (u - ramp);
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final fit = math.min(
        size.width * 0.9 / math.max(writing.size.width, 1), size.height * 0.8 / math.max(writing.size.height, 1));
    final out = _smooth01((t - slow) / (done - slow));
    final z = zoom + (1 - zoom) * out;
    // Following the writing, steadily.
    var f = Offset.zero;
    for (var i = -4; i <= 4; i++) {
      f += writing.follow(pen(t + i * 0.06));
    }
    final centre = writing.bounds.center;
    final focus = Offset.lerp(f / 9, centre, out)!;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(fit * z)
      ..translate(-focus.dx, -focus.dy);
    writing.paint(canvas, Offset.zero, pen(t));
    canvas.restore();
  }
}

/// Where a [PenFilm]'s camera is.
enum PenFilmAngle {
  /// From above, turning slowly.
  sky,

  /// Down low along the line, the words running off into the distance.
  low,

  /// Round the pen, swinging from one side to the other.
  orbit,
}

/// The writing on paper filmed by a camera in 3D that follows the pen, from
/// [angle]: slow at first (a hand's pace), the pen hurrying as the camera
/// pulls back to the whole line from [reveal]; done by [done]. Best with
/// light ink on dark paper ([PenInk.white]).
class PenFilm implements PenShot {
  PenFilm(
    this.writing, {
    this.angle = PenFilmAngle.sky,
    this.lead = 0.2,
    this.reveal = 2.8,
    this.done = 3.3,
    this.hold = 0.45,
    this.paper = const Color(0xFF050506),
    this.grain = true,
  }) {
    final r = math.Random(5);
    final w = math.max(writing.size.width, 400.0), h = math.max(writing.size.height, 200.0);
    for (var i = 0; i < (grain ? 5000 : 0); i++) {
      _grain.add(Offset((r.nextDouble() * 2 - 1) * w * 1.4, (r.nextDouble() * 2 - 1) * h * 2.5));
    }
  }

  final PenWriting writing;
  final PenFilmAngle angle;
  final double lead, reveal, done, hold;
  final Color paper;
  final bool grain;
  final _grain = <Offset>[];

  @override
  double get duration => done + hold;

  /// The pen's clock: slow at first, hurrying as the camera pulls back.
  double pen(double t) {
    final x = (math.max(0, t - lead) / (done - lead)).clamp(0.0, 1.0);
    return writing.duration * (0.3 * x + 0.7 * x * x) + math.max(0, t - done) * 1e3;
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final mid = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(mid, size.height * 0.75,
        Paint()..shader = Gradient.radial(mid, size.height * 0.75, [const Color(0x40302822), const Color(0x00000000)]));
    var f = Offset.zero;
    for (var i = -4; i <= 4; i++) {
      f += writing.follow(pen(t + i * 0.06));
    }
    f = f / 9;
    final out = _smooth01((t - reveal) / (done + 0.4 - reveal));
    final focus = Offset.lerp(f, writing.bounds.center, out)!;
    final u = (t / duration).clamp(0.0, 1.0);
    // How high over the paper (deg), from which side (deg; 0: from the
    // bottom of the page), how far (x-heights).
    final (el, az, k) = switch (angle) {
      PenFilmAngle.sky => (64.0 + 8 * u, -32.0 + 38 * u, 13.0),
      PenFilmAngle.low => (17.0 + 8 * u, -34.0 + 14 * u, 12.0),
      PenFilmAngle.orbit => (40.0, -62.0 + 104 * u, 15.0),
    };
    final xh = writing.hand.xHeight * writing.em;
    final near = k * xh, whole = writing.size.width * 1.25 / (2 * math.tan(19 * math.pi / 180));
    final elev = (el + (74 - el) * out) * math.pi / 180, azim = (az * (1 - out)) * math.pi / 180;
    final d = near + (math.max(whole, near) - near) * out;
    // Paper: x right, y down; the world: x right, y up the page, z up.
    final target = vm.Vector3(focus.dx, -focus.dy, 0);
    final eye =
        target + vm.Vector3(math.sin(azim) * math.cos(elev), -math.cos(azim) * math.cos(elev), math.sin(elev)) * d;
    // (Up: up the page from overhead, the room's up from low down.)
    final up = (vm.Vector3(0, 1, 0) * math.sin(elev) + vm.Vector3(0, 0, 1) * math.cos(elev))..normalize();
    final view = vm.makeViewMatrix(eye, target, up);
    final proj = vm.makePerspectiveMatrix(38 * math.pi / 180, size.width / size.height, 1, 1e5);
    final port = vm.Matrix4.translationValues(size.width / 2, size.height / 2, 0)
      ..multiply(vm.Matrix4.diagonal3Values(size.width / 2, -size.height / 2, 1));
    final m = port * proj * view * vm.Matrix4.diagonal3Values(1, -1, 1);
    bool front(Offset p) => view.transformed3(vm.Vector3(p.dx, -p.dy, 0)).z < -0.05 * d;
    canvas
      ..save()
      ..transform(Float64List.fromList(m.storage));
    if (grain) {
      canvas.drawPoints(
          PointMode.points,
          [
            for (final g in _grain)
              if (front(g)) g
          ],
          Paint()
            ..color = const Color(0x16FFFFFF)
            ..strokeWidth = 0.04 * xh
            ..strokeCap = StrokeCap.round);
    }
    writing.paint(canvas, Offset.zero, pen(t), keep: (a, b) => front(a) && front(b));
    canvas.restore();
  }
}

double _smooth01(double x) {
  final u = x.clamp(0.0, 1.0);
  return u * u * u * (u * (u * 6 - 15) + 10);
}
