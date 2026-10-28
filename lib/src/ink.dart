import 'dart:ui';

/// The pen and its ink: the ink's colour; the nib, how fine a line it draws
/// moving one way and how much broader moving down (both of the x-height);
/// and how much the hand wavers. Wet ink glistens a moment after the pen;
/// ink pools a little where the pen lands.
class PenInk {
  const PenInk({
    this.color = const Color(0xFF16204A),
    this.fine = 0.035,
    this.heavy = 0.21,
    this.nibAngle = 0.7,
    this.waver = 1.0,
    this.wet = true,
    this.pools = true,
  });

  /// Blue-black, for paper.
  static const blueBlack = PenInk();

  /// White ink, for black paper.
  static const white = PenInk(color: Color(0xFFF4EEE2));

  final Color color;

  /// The hairline's width, and how much more a full downstroke adds (of the
  /// x-height).
  final double fine, heavy;

  /// The angle a broad nib's edge holds (radians, up from the right): lines
  /// across it are broad, along it fine.
  final double nibAngle;

  /// How much the hand wavers (0: a steady hand).
  final double waver;

  /// Whether fresh ink glistens, and whether ink pools where the pen lands.
  final bool wet, pools;

  /// Whether the ink is light (on dark paper).
  bool get isLight => color.computeLuminance() > 0.5;
}
