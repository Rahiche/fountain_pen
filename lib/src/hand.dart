/// A hand: how a writer forms each character, as pen strokes.
///
/// Each glyph is a list of strokes in the order a hand draws them; each
/// stroke a polyline of points in em units (x to the right, y up from the
/// baseline). A late stroke (an i's dot, a detached bar) waits until its
/// word is written, as a hand does.
///
/// The bundled hand is [homemadeApple]; trace your own from a font you may
/// use with `tool/trace` (see the README).
class PenHand {
  const PenHand({required this.xHeight, required this.space, required this.glyphs});

  /// The height of a lowercase x, and the advance of a space (em).
  final double xHeight, space;

  /// Each character's strokes.
  final Map<String, PenGlyph> glyphs;

  /// A hand from the JSON `tool/trace/strokes.py` writes.
  factory PenHand.fromJson(Map<String, dynamic> json) => PenHand(
        xHeight: (json['xHeight'] as num).toDouble(),
        space: (json['space'] as num).toDouble(),
        glyphs: {
          for (final MapEntry(:key, :value) in (json['glyphs'] as Map<String, dynamic>).entries)
            key: PenGlyph((value['adv'] as num).toDouble(), [
              for (final s in value['strokes'] as List)
                PenStroke([for (final v in s['p'] as List) (v as num).toDouble()],
                    late: s['late'] == true, dot: s['dot'] == true),
            ]),
        },
      );

  /// Whether this hand can write [character].
  bool canWrite(String character) => character == ' ' || glyphs.containsKey(character);
}

/// One character as a hand writes it: how far the pen moves on after it
/// (em), and its strokes in order.
class PenGlyph {
  const PenGlyph(this.advance, this.strokes);

  final double advance;
  final List<PenStroke> strokes;
}

/// One stroke of the pen: `x, y, r` for each point along it (em; `r` the
/// traced line's half-width, unused by the nib), and whether it's written
/// late (once its word is done) or is a dot.
class PenStroke {
  const PenStroke(this.points, {this.late = false, this.dot = false});

  final List<double> points;
  final bool late, dot;
}
