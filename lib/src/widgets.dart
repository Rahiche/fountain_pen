import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'camera.dart';
import 'hand.dart';
import 'hands/homemade_apple.dart';
import 'ink.dart';
import 'writing.dart';

/// [text] written out by a fountain pen as it appears, then left on the
/// page. Sizes itself to the writing.
///
/// ```dart
/// FountainPenText('This text is rendered\nwith Flutter', fontSize: 56)
/// ```
///
/// Starts on its own ([autoplay]) after [delay]; [repeat] writes it again
/// and again. To start it yourself, give it a `GlobalKey<FountainPenTextState>`
/// and call [FountainPenTextState.play] or [FountainPenTextState.reset].
class FountainPenText extends StatefulWidget {
  const FountainPenText(
    this.text, {
    super.key,
    this.hand = homemadeApple,
    this.fontSize = 48,
    this.ink = PenInk.blueBlack,
    this.speed = 3,
    this.duration,
    this.maxWidth,
    this.lineHeight = 1.3,
    this.align = PenAlign.center,
    this.seed = 7,
    this.autoplay = true,
    this.delay = Duration.zero,
    this.repeat = false,
    this.onComplete,
  });

  final String text;
  final PenHand hand;

  /// px to the em.
  final double fontSize;
  final PenInk ink;

  /// How fast the pen moves (em a second; a hand's pace is about 3).
  final double speed;

  /// How long to take writing it all (else at [speed]).
  final Duration? duration;

  /// Written smaller if it would be wider than this.
  final double? maxWidth;
  final double lineHeight;
  final PenAlign align;

  /// The same seed, the same hand: each letter's little irregularities.
  final int seed;
  final bool autoplay;
  final Duration delay;
  final bool repeat;

  /// Called once it's all written.
  final VoidCallback? onComplete;

  @override
  State<FountainPenText> createState() => FountainPenTextState();
}

class FountainPenTextState extends State<FountainPenText> with SingleTickerProviderStateMixin {
  late PenWriting _writing;
  late final AnimationController _clock = AnimationController(vsync: this)..addStatusListener(_status);

  @override
  void initState() {
    super.initState();
    _write();
    if (widget.autoplay) {
      if (widget.delay == Duration.zero) {
        play();
      } else {
        Future<void>.delayed(widget.delay, () {
          if (mounted) play();
        });
      }
    }
  }

  @override
  void didUpdateWidget(FountainPenText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = oldWidget;
    if (o.text != widget.text ||
        o.hand != widget.hand ||
        o.fontSize != widget.fontSize ||
        o.ink != widget.ink ||
        o.speed != widget.speed ||
        o.duration != widget.duration ||
        o.maxWidth != widget.maxWidth ||
        o.lineHeight != widget.lineHeight ||
        o.align != widget.align ||
        o.seed != widget.seed) {
      final running = _clock.isAnimating;
      _write();
      if (running) play();
    }
  }

  void _write() {
    _writing = PenWriting(
      widget.text,
      hand: widget.hand,
      fontSize: widget.fontSize,
      ink: widget.ink,
      speed: widget.speed,
      duration: widget.duration == null ? null : widget.duration!.inMicroseconds / 1e6,
      maxWidth: widget.maxWidth,
      lineHeight: widget.lineHeight,
      align: widget.align,
      seed: widget.seed,
    );
    _clock.duration = Duration(microseconds: math.max(1, (_writing.duration * 1e6).round()));
  }

  void _status(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    widget.onComplete?.call();
    if (widget.repeat) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted && widget.repeat) play();
      });
    }
  }

  /// Writes it from the start.
  void play() => _clock.forward(from: 0);

  /// Blank again (and stopped).
  void reset() => _clock.reset();

  /// How far through the writing it is (0..1).
  double get progress => _clock.value;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: _writing.size,
          painter: FountainPenPainter(_writing, _clock),
        ),
      );
}

/// Paints [writing] as written by [progress] (0..1 of its duration),
/// fitted into the canvas.
class FountainPenPainter extends CustomPainter {
  FountainPenPainter(this.writing, this.progress) : super(repaint: progress);

  final PenWriting writing;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final b = writing.bounds;
    if (b.isEmpty) return;
    final k = (size.width / b.width).clamp(0.0, size.height / b.height);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(k)
      ..translate(-b.center.dx, -b.center.dy);
    writing.paint(canvas, Offset.zero, progress.value * writing.duration);
    canvas.restore();
  }

  @override
  bool shouldRepaint(FountainPenPainter old) => old.writing != writing || old.progress != progress;
}

/// Plays a [PenShot] ([PenCloseUp], [PenFilm]) filling its box.
class PenShotView extends StatefulWidget {
  const PenShotView(this.shot, {super.key, this.autoplay = true, this.repeat = false, this.onComplete});

  final PenShot shot;
  final bool autoplay, repeat;
  final VoidCallback? onComplete;

  @override
  State<PenShotView> createState() => PenShotViewState();
}

class PenShotViewState extends State<PenShotView> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      widget.onComplete?.call();
      if (widget.repeat && mounted) play();
    });

  @override
  void initState() {
    super.initState();
    _clock.duration = Duration(microseconds: math.max(1, (widget.shot.duration * 1e6).round()));
    if (widget.autoplay) play();
  }

  @override
  void didUpdateWidget(PenShotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shot != widget.shot) {
      _clock.duration = Duration(microseconds: math.max(1, (widget.shot.duration * 1e6).round()));
      if (widget.autoplay) play();
    }
  }

  /// Plays it from the start.
  void play() => _clock.forward(from: 0);

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _ShotPainter(widget.shot, _clock), size: Size.infinite),
      );
}

class _ShotPainter extends CustomPainter {
  _ShotPainter(this.shot, this.clock) : super(repaint: clock);

  final PenShot shot;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    shot.paint(canvas, size, clock.value * shot.duration);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShotPainter old) => old.shot != shot || old.clock != clock;
}
