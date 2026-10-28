"""arabic_forms.py <out.tsv>: what to rasterise for an Arabic hand: every
letter in each of its joined forms (isolated, final, initial, medial), kept
under its Unicode presentation-form code point, and the text that, shaped,
gives that form (the letter with zero-width joiners either side); the lam-alef
ligatures; Arabic and Persian digits and punctuation. For shaped_glyphs.swift.
"""
import sys, unicodedata

ZWJ = '‍'
CONTEXT = {'isolated': '{}', 'final': ZWJ + '{}', 'initial': '{}' + ZWJ, 'medial': ZWJ + '{}' + ZWJ}
rows = []
for cp in list(range(0xFB50, 0xFE00)) + list(range(0xFE70, 0xFF00)):
    d = unicodedata.decomposition(chr(cp))
    tag = d.split()[0] if d.startswith('<') else ''
    if tag.strip('<>') not in CONTEXT:
        continue
    base = ''.join(chr(int(h, 16)) for h in d.split()[1:])
    if not all(0x0600 <= ord(c) <= 0x06FF for c in base):
        continue
    if len(base) == 2 and not (base[0] == 'ل' and base[1] in 'آأإا'):
        continue  # (only the lam-alef ligatures, which every Arabic hand writes)
    if len(base) > 2:
        continue
    form = tag.strip('<>')
    rows.append((cp, CONTEXT[form].format(base)))
    if form == 'isolated' and len(base) == 1:
        rows.append((ord(base), base))  # (the letter itself, as it stands alone)
for c in '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹،؛؟ـ٪':
    rows.append((ord(c), c))
seen = set()
with open(sys.argv[1], 'w') as f:
    for cp, text in rows:
        if cp not in seen:
            seen.add(cp)
            f.write(f'{cp}\t{text}\n')
print(len(seen), 'glyphs to rasterise')
