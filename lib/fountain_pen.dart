/// Text written out by a fountain pen, stroke by stroke.
///
/// [FountainPenText] is the drop-in widget. For more control, lay the text
/// out with [PenWriting] and paint it at any moment of its writing; or film
/// it with a [PenCloseUp] (a camera following the pen) or a [PenFilm] (a
/// camera in 3D over the paper) and play that with a [PenShotView].
library;

export 'src/camera.dart';
export 'src/arabic.dart' show arabicShaped, isRightToLeft;
export 'src/hand.dart';
export 'src/hands/homemade_apple.dart' show homemadeApple;
export 'src/hands/noto_naskh_arabic.dart' show notoNaskhArabic;
export 'src/hands/noto_sans_japanese.dart' show notoSansJapanese;
export 'src/ink.dart';
export 'src/widgets.dart';
export 'src/writing.dart';
