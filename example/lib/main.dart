import 'package:flutter/material.dart';
import 'package:fountain_pen/fountain_pen.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fountain_pen',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF16204A),
      useMaterial3: true,
    ),
    home: const Demo(),
  );
}

enum Show { paper, closeUp, sky, low, orbit }

/// What's written, in which hand.
enum Script {
  latin('Latin', 'This text is rendered\nwith Flutter'),
  japanese('日本語', 'このテキストは\nFlutterで描画されています'),
  arabic('العربية', 'هذا النص\nمرسوم بفلاتر');

  const Script(this.label, this.sample);

  final String label, sample;

  PenHand get hand => switch (this) {
    latin => homemadeApple,
    japanese => notoSansJapanese,
    arabic => notoNaskhArabic,
  };
}

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final _text = TextEditingController(text: Script.latin.sample);
  var _script = Script.latin;
  var _show = Show.paper;
  var _take = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Widget _stage() {
    final text = _text.text, hand = _script.hand;
    switch (_show) {
      case Show.paper:
        return ColoredBox(
          color: const Color(0xFFF7F3EA),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: LayoutBuilder(
                builder: (context, box) => FountainPenText(
                  text,
                  key: ValueKey(_take),
                  hand: hand,
                  fontSize: 64,
                  maxWidth: box.maxWidth,
                ),
              ),
            ),
          ),
        );
      case Show.closeUp:
        return PenShotView(
          PenCloseUp(PenWriting(text, hand: hand, fontSize: 64)),
          key: ValueKey(_take),
        );
      case Show.sky || Show.low || Show.orbit:
        final angle = {
          Show.sky: PenFilmAngle.sky,
          Show.low: PenFilmAngle.low,
          Show.orbit: PenFilmAngle.orbit,
        }[_show]!;
        return PenShotView(
          PenFilm(
            PenWriting(text, hand: hand, fontSize: 64, ink: PenInk.white),
            angle: angle,
          ),
          key: ValueKey(_take),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(child: _stage()),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => setState(() => _take++),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<Script>(
                segments: [
                  for (final s in Script.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {_script},
                onSelectionChanged: (s) => setState(() {
                  _script = s.first;
                  _text.text = _script.sample;
                  _take++;
                }),
              ),
              const SizedBox(width: 12),
              SegmentedButton<Show>(
                segments: const [
                  ButtonSegment(value: Show.paper, label: Text('Paper')),
                  ButtonSegment(value: Show.closeUp, label: Text('Close-up')),
                  ButtonSegment(value: Show.sky, label: Text('Sky')),
                  ButtonSegment(value: Show.low, label: Text('Low')),
                  ButtonSegment(value: Show.orbit, label: Text('Orbit')),
                ],
                selected: {_show},
                onSelectionChanged: (s) => setState(() {
                  _show = s.first;
                  _take++;
                }),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                tooltip: 'Write it again',
                icon: const Icon(Icons.replay),
                onPressed: () => setState(() => _take++),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
