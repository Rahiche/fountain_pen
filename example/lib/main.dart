import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fountain_pen/fountain_pen.dart';
import 'package:url_launcher/link.dart';

void main() => runApp(const GalleryApp());

const paperColor = Color(0xFFF7F3EA);
const darkPaper = Color(0xFF101114);

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fountain_pen',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF16204A),
      useMaterial3: true,
    ),
    home: const Home(),
  );
}

/// A script, and the hand that writes it.
enum Script {
  latin('Latin', 'Homemade Apple'),
  japanese('日本語', 'Noto Sans JP'),
  arabic('العربية', 'Noto Naskh Arabic'),
  persian('فارسی', 'Noto Naskh Arabic'),
  urdu('اردو', 'Noto Naskh Arabic');

  const Script(this.label, this.font);

  final String label, font;

  PenHand get hand => switch (this) {
    latin => homemadeApple,
    japanese => notoSansJapanese,
    arabic || persian || urdu => notoNaskhArabic,
  };

  String get handName => switch (this) {
    latin => 'homemadeApple',
    japanese => 'notoSansJapanese',
    arabic || persian || urdu => 'notoNaskhArabic',
  };

  /// The script [text] is written in: Arabic letters, else Japanese
  /// kana or kanji, else Latin.
  static Script of(String text) {
    var japanese = false;
    for (final r in text.runes) {
      if ((r >= 0x0600 && r <= 0x06FF) ||
          (r >= 0xFB50 && r <= 0xFDFF) ||
          (r >= 0xFE70 && r <= 0xFEFF)) {
        return arabic;
      }
      if ((r >= 0x3000 && r <= 0x30FF) ||
          (r >= 0x4E00 && r <= 0x9FFF) ||
          (r >= 0xFF00 && r <= 0xFFEF)) {
        japanese = true;
      }
    }
    return japanese ? Script.japanese : latin;
  }
}

/// How it's shown: on paper, close on the pen, or filmed in 3D.
enum Show {
  paper('Paper'),
  closeUp('Close-up'),
  sky('Sky'),
  low('Low'),
  orbit('Orbit');

  const Show(this.label);

  final String label;

  PenFilmAngle? get angle => switch (this) {
    sky => PenFilmAngle.sky,
    low => PenFilmAngle.low,
    orbit => PenFilmAngle.orbit,
    _ => null,
  };
}

/// An ink, by name.
class Ink {
  const Ink(this.name, this.color, this.code);

  final String name;
  final Color color;

  /// How it's written in Dart.
  final String code;

  bool get light => color.computeLuminance() > 0.5;
}

const inks = [
  Ink('Blue-black', Color(0xFF16204A), 'PenInk.blueBlack'),
  Ink('Black', Color(0xFF1A1A1A), 'Color(0xFF1A1A1A)'),
  Ink('Sepia', Color(0xFF5B3A1E), 'Color(0xFF5B3A1E)'),
  Ink('Crimson', Color(0xFF9E1B32), 'Color(0xFF9E1B32)'),
  Ink('Emerald', Color(0xFF0F5D46), 'Color(0xFF0F5D46)'),
  Ink('Violet', Color(0xFF4B2A7B), 'Color(0xFF4B2A7B)'),
  Ink('White', Color(0xFFF4EEE2), 'PenInk.white'),
];

/// One of the gallery's examples: what's written, how, and for how long
/// (s) on paper.
class Example {
  const Example(
    this.text,
    this.script, {
    this.ink = 0,
    this.show = Show.paper,
    this.seconds = 5,
    this.note,
  });

  final String text;
  final Script script;
  final int ink;
  final Show show;
  final double seconds;
  final String? note;
}

const examples = [
  Example('This text is rendered\nwith Flutter', Script.latin, seconds: 5),
  Example('Dear reader,', Script.latin, ink: 2, seconds: 2.5),
  Example(
    'The quick brown fox\njumps over the lazy dog',
    Script.latin,
    ink: 1,
    seconds: 7,
  ),
  Example(
    'Every letter goes\non a journey',
    Script.latin,
    ink: 6,
    show: Show.sky,
  ),
  Example('Never quite the\nsame twice', Script.latin, ink: 3, seconds: 4.5),
  Example(
    'Hope is the thing\nwith feathers',
    Script.latin,
    ink: 5,
    show: Show.closeUp,
    note: 'Emily Dickinson',
  ),
  Example('このテキストは\nFlutterで描画されています', Script.japanese, seconds: 8),
  Example('手書きの日本語', Script.japanese, ink: 6, show: Show.low),
  Example(
    '古池や\n蛙飛び込む\n水の音',
    Script.japanese,
    ink: 1,
    seconds: 8,
    note: 'Bashō',
  ),
  Example('ありがとう', Script.japanese, ink: 3, seconds: 3),
  Example(
    '永字八法',
    Script.japanese,
    ink: 1,
    show: Show.closeUp,
    note: 'The eight strokes of 永',
  ),
  Example('いろはにほへと\nちりぬるを', Script.japanese, ink: 2, seconds: 7),
  Example('هذا النص\nمرسوم بفلاتر', Script.arabic, seconds: 6),
  Example('مرحبا بالعالم', Script.arabic, ink: 6, show: Show.orbit),
  Example('بالقلم والحبر', Script.arabic, ink: 2, seconds: 4),
  Example('سلام دنیا', Script.persian, ink: 4, seconds: 3),
  Example('با قلم و جوهر', Script.persian, ink: 6, show: Show.sky),
  Example('یہ تحریر قلم سے\nلکھی گئی ہے', Script.urdu, seconds: 7),
  Example('شکریہ', Script.urdu, ink: 3, seconds: 2.5),
];

/// The writing for [text] in [script]'s hand, at [fontSize], in [ink].
PenWriting writingOf(
  String text,
  Script script, {
  double fontSize = 64,
  PenInk ink = PenInk.blueBlack,
  double speed = 6,
  double? seconds,
  int seed = 7,
}) => PenWriting(
  text,
  hand: script.hand,
  fontSize: fontSize,
  ink: ink,
  speed: speed,
  duration: seconds,
  seed: seed,
);

/// [writing] shown as [show] says, filling its box: paper (or dark paper,
/// for light ink), a close-up, or filmed.
Widget stage(PenWriting writing, Show show, {Key? key}) {
  final light = writing.ink.isLight;
  final angle = show.angle;
  if (angle != null) {
    return PenShotView(
      PenFilm(
        writing,
        angle: angle,
        done: 4.2,
        reveal: 3.4,
        paper: light ? const Color(0xFF050506) : paperColor,
        grain: light,
      ),
      key: key,
    );
  }
  if (show == Show.closeUp) {
    return PenShotView(
      PenCloseUp(writing, paper: light ? darkPaper : paperColor),
      key: key,
    );
  }
  return ColoredBox(
    color: light ? darkPaper : paperColor,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: _Written(writing, key: key),
        ),
      ),
    ),
  );
}

/// [writing] written out once, sized to it.
class _Written extends StatefulWidget {
  const _Written(this.writing, {super.key});

  final PenWriting writing;

  @override
  State<_Written> createState() => _WrittenState();
}

class _WrittenState extends State<_Written>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_Written old) {
    super.didUpdateWidget(old);
    if (old.writing != widget.writing) _start();
  }

  void _start() {
    _clock.duration = Duration(
      milliseconds: (widget.writing.duration * 1000).round().clamp(1, 600000),
    );
    _clock.forward(from: 0);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: widget.writing.size,
    painter: FountainPenPainter(widget.writing, _clock),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  // (The playground listens for what to open: on its first visit it isn't
  // built yet, and the tab view won't pass it new arguments mid-switch.)
  final _opened = ValueNotifier<Example?>(null);

  @override
  void dispose() {
    _tabs.dispose();
    _opened.dispose();
    super.dispose();
  }

  void _open(Example e) {
    _opened
      ..value = null
      ..value = e;
    _tabs.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 640;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('fountain_pen'),
            if (!narrow) ...[
              const SizedBox(width: 12),
              Text(
                'text written out by a fountain pen, in Flutter',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          _link('pub.dev', 'https://pub.dev/packages/fountain_pen'),
          _link('GitHub', 'https://github.com/Rahiche/fountain_pen'),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Gallery'),
            Tab(text: 'Playground'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _KeepAlive(Gallery(onOpen: _open)),
          _KeepAlive(Playground(opened: _opened)),
        ],
      ),
    );
  }

  Widget _link(String label, String url) => Link(
    uri: Uri.parse(url),
    target: LinkTarget.blank,
    builder: (context, follow) =>
        TextButton(onPressed: follow, child: Text(label)),
  );
}

/// Every example as a card, writing itself once it's on screen.
class Gallery extends StatelessWidget {
  const Gallery({super.key, required this.onOpen});

  final ValueChanged<Example> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        for (final script in Script.values) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${script.label} · ${script.font}',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 460,
              childAspectRatio: 1.45,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final e in examples)
                  if (e.script == script)
                    ExampleCard(e, onOpen: () => onOpen(e)),
              ],
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class ExampleCard extends StatefulWidget {
  const ExampleCard(this.example, {super.key, required this.onOpen});

  final Example example;
  final VoidCallback onOpen;

  @override
  State<ExampleCard> createState() => _ExampleCardState();
}

class _ExampleCardState extends State<ExampleCard> {
  var _take = 0;
  late PenWriting _writing = _write();

  PenWriting _write() {
    final e = widget.example;
    final ink = inks[e.ink];
    return writingOf(
      e.text,
      e.script,
      fontSize: 72,
      ink: PenInk(color: ink.color),
      seconds: e.show == Show.paper ? e.seconds : null,
    );
  }

  @override
  void didUpdateWidget(ExampleCard old) {
    super.didUpdateWidget(old);
    if (old.example != widget.example) _writing = _write();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.example;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: stage(_writing, e.show, key: ValueKey(_take))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      e.show == Show.paper ? inks[e.ink].name : e.show.label,
                      ?e.note,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Write it again',
                  icon: const Icon(Icons.replay),
                  onPressed: () => setState(() => _take++),
                ),
                IconButton(
                  tooltip: 'Open in the playground',
                  icon: const Icon(Icons.tune),
                  onPressed: widget.onOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Your own text, every setting to hand.
class Playground extends StatefulWidget {
  const Playground({super.key, required this.opened});

  /// An example to open: written once it's set.
  final ValueListenable<Example?> opened;

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  final _text = TextEditingController();
  Timer? _typing;
  var _written = '';
  Script? _hand; // null: from the text
  var _ink = 0;
  var _show = Show.paper;
  double _size = 72, _speed = 6, _heavy = 0.21;
  var _steady = false;
  var _seed = 7;
  var _take = 0;

  @override
  void initState() {
    super.initState();
    widget.opened.addListener(_open);
    load(widget.opened.value ?? examples.first);
  }

  void _open() {
    final e = widget.opened.value;
    if (e != null) load(e);
  }

  @override
  void dispose() {
    widget.opened.removeListener(_open);
    _typing?.cancel();
    _text.dispose();
    super.dispose();
  }

  /// Takes [e]'s text, ink and camera, and writes it.
  void load(Example e) => setState(() {
    _text.text = e.text;
    _written = e.text;
    _hand = null;
    _ink = e.ink;
    _show = e.show;
    _take++;
  });

  void _again() => setState(() => _take++);

  Script get _script => _hand ?? Script.of(_written);

  PenInk get _penInk =>
      PenInk(color: inks[_ink].color, heavy: _heavy, waver: _steady ? 0 : 1);

  String get _code {
    final ink = inks[_ink];
    final custom = _heavy != 0.21 || _steady;
    final color = ink.code.startsWith('PenInk.')
        ? (ink.code == 'PenInk.white'
              ? 'Color(0xFFF4EEE2)'
              : 'Color(0xFF16204A)')
        : ink.code;
    final inkCode = custom
        ? 'PenInk(color: $color${_heavy != 0.21 ? ', heavy: ${_heavy.toStringAsFixed(2)}' : ''}${_steady ? ', waver: 0' : ''})'
        : ink.code.startsWith('PenInk.')
        ? ink.code
        : 'PenInk(color: $color)';
    final text = _written
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    final args =
        "'$text',\n  hand: ${_script.handName},\n  fontSize: ${_size.round()},\n"
        '  speed: ${_speed.round()},\n  seed: $_seed,\n  ink: $inkCode,';
    final angle = _show.angle;
    if (_show == Show.paper) return 'FountainPenText(\n  $args\n)';
    final writing = 'PenWriting(\n  $args\n)';
    // (On the paper the stage shows it on: dark for light ink, else cream.)
    final light = ink.light;
    if (angle == null) {
      final paper = light ? 'Color(0xFF101114)' : 'Color(0xFFF7F3EA)';
      return 'PenShotView(PenCloseUp(\n  $writing,\n  paper: $paper,\n))';
    }
    final paper = light ? '' : '\n  paper: Color(0xFFF7F3EA),\n  grain: false,';
    return 'PenShotView(PenFilm(\n  $writing,\n  angle: $angle,\n  done: 4.2,\n  reveal: 3.4,$paper\n))';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final writing = writingOf(
        _written.isEmpty ? ' ' : _written,
        _script,
        fontSize: _size,
        ink: _penInk,
        speed: _speed,
        seed: _seed,
      );
      final view = stage(writing, _show, key: ValueKey(_take));
      final controls = _controls(context);
      if (box.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: view),
            SizedBox(width: 380, child: controls),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: (box.maxHeight * 0.45).clamp(220, 420), child: view),
          Expanded(child: controls),
        ],
      );
    },
  );

  Widget _controls(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(s, style: theme.textTheme.labelLarge),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _text,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Text',
            hintText: 'Type something to write',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Write it',
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() {
                _written = _text.text;
                _take++;
              }),
            ),
          ),
          onChanged: (s) {
            _typing?.cancel();
            _typing = Timer(const Duration(milliseconds: 700), () {
              if (mounted) {
                setState(() {
                  _written = s;
                  _take++;
                });
              }
            });
          },
        ),
        label('Examples'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in examples)
              ActionChip(
                label: Text(
                  e.text.split('\n').first,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => load(e),
              ),
          ],
        ),
        label('Hand'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: Text('From the text: ${Script.of(_written).font}'),
              selected: _hand == null,
              onSelected: (_) => setState(() {
                _hand = null;
                _take++;
              }),
            ),
            for (final s in [Script.latin, Script.japanese, Script.arabic])
              ChoiceChip(
                label: Text(s.font),
                selected: _hand == s,
                onSelected: (_) => setState(() {
                  _hand = s;
                  _take++;
                }),
              ),
          ],
        ),
        label('Ink'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (i, ink) in inks.indexed)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: ink.color, radius: 8),
                label: Text(ink.name),
                selected: _ink == i,
                onSelected: (_) => setState(() {
                  _ink = i;
                  _take++;
                }),
              ),
          ],
        ),
        label('Shown'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in Show.values)
              ChoiceChip(
                label: Text(s.label),
                selected: _show == s,
                onSelected: (_) => setState(() {
                  _show = s;
                  _take++;
                }),
              ),
          ],
        ),
        label('Size: ${_size.round()} px to the em'),
        Slider(
          value: _size,
          min: 24,
          max: 160,
          onChanged: (v) => setState(() => _size = v),
          onChangeEnd: (_) => _again(),
        ),
        label('Speed: ${_speed.round()} em a second (a hand: about 3)'),
        Slider(
          value: _speed,
          min: 1,
          max: 20,
          divisions: 19,
          onChanged: (v) => setState(() => _speed = v),
          onChangeEnd: (_) => _again(),
        ),
        label(
          'Nib: ${_heavy < 0.15 ? 'fine' : (_heavy > 0.28 ? 'broad' : 'medium')}',
        ),
        Slider(
          value: _heavy,
          min: 0.05,
          max: 0.4,
          onChanged: (v) => setState(() => _heavy = v),
          onChangeEnd: (_) => _again(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('A steady hand'),
          subtitle: const Text("No wavering: the letters' own shapes"),
          value: _steady,
          onChanged: (v) => setState(() {
            _steady = v;
            _take++;
          }),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Seed $_seed: the same seed, the same hand',
                style: theme.textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: 'Another hand',
              icon: const Icon(Icons.casino_outlined),
              onPressed: () => setState(() {
                _seed = (_seed * 7919 + 13) % 1000;
                _take++;
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _again,
          icon: const Icon(Icons.replay),
          label: const Text('Write it again'),
        ),
        label('The code'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            _code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: _code)),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ),
      ],
    );
  }
}

/// Keeps a tab's page (its scroll, what it's written) while another tab
/// is shown.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child);

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
