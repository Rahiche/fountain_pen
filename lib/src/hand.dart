import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// A hand: how a writer forms each character, as pen strokes.
///
/// Each glyph is a list of strokes in the order a hand draws them; each
/// stroke a polyline of points in em units (x to the right, y up from the
/// baseline). A late stroke (an i's dot, a detached bar) waits until its
/// word is written, as a hand does.
///
/// The bundled hands are [homemadeApple] (Latin) and [notoSansJapanese]
/// (Japanese); trace your own from a font you may use with `tool/trace` (see
/// the README).
class PenHand {
  const PenHand({required this.xHeight, required this.space, required this.glyphs});

  /// A hand packed by `tool/trace/to_packed.py` (base64, in parts): each
  /// glyph is unpacked the first time it's written.
  factory PenHand.packed(List<String> data) {
    final glyphs = _PackedGlyphs(base64.decode(data.join()));
    return PenHand(xHeight: glyphs.xHeight, space: glyphs.space, glyphs: glyphs);
  }

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

/// A packed hand's glyphs, unpacked as they're asked for. The bytes: `FPH`,
/// a version; the x-height and space (1/10000 em); the glyph count; then each
/// glyph's character (on from the last) and length; then the glyphs. A glyph:
/// its advance (1/10000 em) and its strokes; a stroke: whether it's late or a
/// dot, its point count and width (1/1024 em), then its points, the first
/// where it is and each after how far on (1/512 em). Counts and steps are
/// varints, steps zigzagged.
class _PackedGlyphs extends UnmodifiableMapBase<String, PenGlyph> {
  _PackedGlyphs(this._b) {
    if (_b.length < 4 || _b[0] != 0x46 || _b[1] != 0x50 || _b[2] != 0x48 || _b[3] != 1) {
      throw const FormatException('Not a packed hand (FPH1)');
    }
    _i = 4;
    xHeight = _u16() / 10000;
    space = _u16() / 10000;
    final n = _varint();
    var code = 0;
    final lengths = <int>[];
    final codes = <int>[];
    for (var k = 0; k < n; k++) {
      code += _varint();
      codes.add(code);
      lengths.add(_varint());
    }
    var at = _i;
    for (var k = 0; k < n; k++) {
      _at[codes[k]] = at;
      at += lengths[k];
    }
  }

  final Uint8List _b;
  var _i = 0;
  late final double xHeight, space;
  final _at = <int, int>{};
  final _done = <int, PenGlyph>{};

  int _u16() => _b[_i++] | _b[_i++] << 8;

  int _varint() {
    var v = 0, shift = 0;
    while (true) {
      final b = _b[_i++];
      v |= (b & 0x7f) << shift;
      if (b < 0x80) return v;
      shift += 7;
    }
  }

  int _zigzag() {
    final v = _varint();
    return v.isEven ? v >> 1 : -((v + 1) >> 1);
  }

  PenGlyph _unpack(int at) {
    _i = at;
    final advance = _u16() / 10000;
    final strokes = <PenStroke>[];
    for (var k = _varint(); k > 0; k--) {
      final flags = _b[_i++];
      final n = _varint();
      final r = _b[_i++] / 1024;
      final p = Float64List(n * 3);
      var x = 0, y = 0;
      for (var j = 0; j < n; j++) {
        x += _zigzag();
        y += _zigzag();
        p[j * 3] = x / 512;
        p[j * 3 + 1] = y / 512;
        p[j * 3 + 2] = r;
      }
      strokes.add(PenStroke(p, late: flags & 1 != 0, dot: flags & 2 != 0));
    }
    return PenGlyph(advance, strokes);
  }

  static int? _code(Object? key) => key is String && key.isNotEmpty && key.runes.length == 1 ? key.runes.first : null;

  @override
  PenGlyph? operator [](Object? key) {
    final c = _code(key);
    final at = c == null ? null : _at[c];
    return at == null ? null : _done[c!] ??= _unpack(at);
  }

  @override
  bool containsKey(Object? key) => _at.containsKey(_code(key));

  @override
  Iterable<String> get keys => _at.keys.map(String.fromCharCode);

  @override
  int get length => _at.length;
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
