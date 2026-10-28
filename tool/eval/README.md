# Measuring a traced hand

`kanjivg_eval.py` compares a traced Japanese hand with [KanjiVG](https://kanjivg.tagaini.net)'s stroke data: for each
character both have, whether it has the same number of strokes, whether they come in the same order (exactly, and as
Kendall's tau), whether each runs the same way, and how close their shapes are. It also scores a naive order (top
first, then left) of the same strokes, to show what the ordering rules add.

KanjiVG is licensed under CC BY-SA 3.0. It's only measured against here: none of it goes into a hand, and it isn't
part of this package. Download it yourself:

```sh
gh release download -R KanjiVG/kanjivg -p 'kanjivg-*.xml.gz' -D /tmp/kanjivg
python3 tool/eval/kanjivg_eval.py /tmp/kanjivg/kanjivg-*.xml.gz work/strokes.json results.json
```

`work/strokes.json` is what `tool/trace/strokes_cjk.py` writes; `results.json` has each character's scores.
