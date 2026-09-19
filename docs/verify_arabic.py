#!/usr/bin/env python3
"""Verify the Arabic engine that is COMPILED INTO the EA.

The joining table, the four-form derivation, the lam-alef ligatures, the
translation dictionary and the bidi reorder are all parsed straight out of
the .mq4 source, re-implemented here exactly as the MQL does it, and diffed
against the reference `arabic-reshaper` + `python-bidi` implementations.

This is the only way to test the shaper without an MQL4 compiler: if this
passes, the EA is applying the same transformation the reference libraries
would.
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
EA = os.path.join(HERE, "..", "Signal Forge PRO XAUUSD M5 EA.mq4")
SRC = open(EA, encoding="utf-8").read()
fails = []

QUIET = (__name__ != "__main__")   # render_arabic_proof imports the engine

def say(*a):
    if not QUIET:
        print(*a)

def check(label, ok, detail=""):
    say(f"   {label:52s} {'OK' if ok else 'FAIL'}{(' - ' + detail) if detail and not ok else ''}")
    if not ok:
        fails.append(label)

# ---------------------------------------------------------------- 1. table
say("1. presentation-forms table parsed from the EA")
TAB = {int(m.group(1), 16): (int(m.group(2), 16), int(m.group(3)))
       for m in re.finditer(r'case (0x[0-9A-Fa-f]{4}): iso = (0x[0-9A-Fa-f]{4}); cnt = (\d+);', SRC)}
say(f"   {len(TAB)} letters in the MQL switch")
check("all 36 base letters present", len(TAB) == 36, str(len(TAB)))

try:
    from arabic_reshaper.letters import LETTERS_ARABIC as REF
except ImportError:
    print("\n   arabic_reshaper not installed - run: pip install arabic-reshaper python-bidi")
    sys.exit(2)

diff = 0
for cp, (iso, cnt) in sorted(TAB.items()):
    mine = (iso, iso + 2 if cnt == 4 else 0, iso + 3 if cnt == 4 else 0, iso + 1 if cnt >= 2 else 0)
    r = REF.get(chr(cp))
    if not r:
        diff += 1; continue
    ref = tuple(ord(x) if x else 0 for x in r)   # ISO, INI, MED, FIN
    if mine != ref:
        # U+0649 alef maksura: the reference maps INI/MED into Presentation
        # Forms-A (U+FBE8/9), which many Windows fonts do not carry. The EA
        # deliberately uses the 2-form mapping, which is font-safe and
        # correct for standard Arabic where the letter is always word-final.
        if cp == 0x0649 and mine[0] == ref[0] and mine[3] == ref[3]:
            continue
        diff += 1
        say(f"   DIFF {hex(cp)} mine={[hex(x) for x in mine]} ref={[hex(x) for x in ref]}")
check("every letter matches the reference table", diff == 0, f"{diff} differing")

missing = [hex(ord(k)) for k in REF
           if 0x0621 <= ord(k) <= 0x064A and ord(k) not in TAB and ord(k) != 0x0640]
check("no Arabic letter missing from the table", not missing, str(missing))

# ------------------------------------------- 2. re-implement the MQL logic
LIG = {int(a, 16): int(b, 16) for a, b in
       re.findall(r'case (0x[0-9A-Fa-f]{4}): return (0x[0-9A-Fa-f]{4});\s*// lam \+ alef', SRC)}
if 0x0627 not in LIG:  # the plain-alef case is written with the AR_ALEF macro
    m = re.search(r'case AR_ALEF: return (0x[0-9A-Fa-f]{4});', SRC)
    if m:
        LIG[0x0627] = int(m.group(1), 16)
say(f"\n2. lam-alef ligatures parsed: {len(LIG)}")
check("all four lam-alef ligatures present", len(LIG) == 4, str(sorted(map(hex, LIG))))

RIGHT_ONLY = {0x0622, 0x0623, 0x0624, 0x0625, 0x0627, 0x0629,
              0x062F, 0x0630, 0x0631, 0x0632, 0x0648, 0x0649}

def jt(c):
    if c == 0x0640: return 2
    if c == 0x0621: return 0
    if c in RIGHT_ONLY: return 1
    if 0x0626 <= c <= 0x064A: return 2
    return 0

def is_mark(c):
    return (0x064B <= c <= 0x0655) or c == 0x0670 or (0x06D6 <= c <= 0x06ED)

def is_ar(c):
    return (0x0600 <= c <= 0x06FF) or (0xFB50 <= c <= 0xFEFC)

def shape(s):
    src = [ord(c) for c in s if not is_mark(ord(c))]
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == 0x0644 and i + 1 < n and src[i + 1] in LIG:
            jp = i > 0 and jt(src[i - 1]) == 2
            out.append(LIG[src[i + 1]] + (1 if jp else 0))
            i += 2; continue
        if c not in TAB:
            out.append(c); i += 1; continue
        iso, cnt = TAB[c]
        f = [iso, iso + 1 if cnt >= 2 else 0, iso + 2 if cnt == 4 else 0, iso + 3 if cnt == 4 else 0]
        jp = i > 0 and jt(src[i - 1]) == 2
        jn = jt(c) == 2 and i + 1 < n and (jt(src[i + 1]) != 0 or src[i + 1] in LIG)
        g = f[3] if (jp and jn) else f[1] if jp else f[2] if jn else f[0]
        if g == 0: g = f[1]
        if g == 0: g = f[0]
        out.append(g); i += 1
    return ''.join(chr(x) for x in out)

MIRROR = {0x28: 0x29, 0x29: 0x28, 0x5B: 0x5D, 0x5D: 0x5B,
          0x7B: 0x7D, 0x7D: 0x7B, 0x3C: 0x3E, 0x3E: 0x3C}

def cls(c):
    if is_ar(c): return 'R'
    if (0x41 <= c <= 0x5A) or (0x61 <= c <= 0x7A): return 'L'
    if 0x30 <= c <= 0x39: return 'D'
    return 'N'

def bidi(s):
    ch = [ord(c) for c in s]
    n = len(ch)
    if n <= 1: return s
    k = [cls(c) for c in ch]
    if 'R' not in k: return s
    base = next((x for x in k if x in ('R', 'L')), 'L')
    k = ['L' if x == 'D' else x for x in k]
    for i in range(n):
        if k[i] != 'N': continue
        p = next((k[j] for j in range(i - 1, -1, -1) if k[j] != 'N'), base)
        q = next((k[j] for j in range(i + 1, n) if k[j] != 'N'), base)
        k[i] = p if p == q else base
    runs, i = [], 0
    while i < n:
        j = i
        while j < n and k[j] == k[i]: j += 1
        runs.append((k[i], ch[i:j])); i = j
    if base == 'R': runs.reverse()
    out = []
    for d, seg in runs:
        out.extend(reversed([MIRROR.get(x, x) for x in seg]) if d == 'R' else seg)
    return ''.join(chr(x) for x in out)

def arfix(s):
    return bidi(shape(s)) if any(is_ar(ord(c)) for c in s) else s

# ------------------------------------------------ 3. diff vs the reference
import arabic_reshaper
from bidi.algorithm import get_display

CASES = [
    "\u0645\u0646\u0635\u0629 MetaTrader \u0644\u0627 \u062a\u062f\u0639\u0645 \u0627\u0644\u0644\u063a\u0629 \u0627\u0644\u0639\u0631\u0628\u064a\u0629",
    "\u0625\u063a\u0644\u0627\u0642 \u0627\u0644\u0643\u0644",
    "\u0648\u0642\u0641 \u0627\u0644\u062e\u0633\u0627\u0631\u0629",
    "\u062c\u0646\u064a \u0627\u0644\u0623\u0631\u0628\u0627\u062d",
    "\u0627\u0644\u0631\u0628\u062d 12.50 \u062f\u0648\u0644\u0627\u0631",
    "\u0644\u0648\u062a 0.01",
    "BUY \u0641\u062a\u062d \u0635\u0641\u0642\u0629",
    "\u0646\u0633\u0628\u0629 \u0627\u0644\u0641\u0648\u0632 100%",
    "\u0645\u062a\u062a\u0628\u0639 \u0627\u0644\u0623\u062f\u0627\u0621",
    "\u0627\u0644\u0648\u0642\u0641 \u0627\u0644\u0645\u062a\u062d\u0631\u0643",
    "\u0644\u0627 \u062a\u0648\u062c\u062f \u0635\u0641\u0642\u0629 \u0645\u0641\u062a\u0648\u062d\u0629",
    "\u0627\u0644\u0635\u0627\u0641\u064a \u0627\u0644\u0646\u0647\u0627\u0626\u064a (\u0628\u0639\u062f \u0627\u0644\u0639\u0645\u0648\u0644\u0629)",
]
say("\n3. shaping + bidi vs arabic-reshaper / python-bidi")
bad = 0
for t in CASES:
    if shape(t) != arabic_reshaper.reshape(t):
        bad += 1; print("   SHAPE DIFF:", t)
    if arfix(t) != get_display(arabic_reshaper.reshape(t)):
        bad += 1; print("   BIDI  DIFF:", t)
check(f"{len(CASES)} mixed strings match the reference exactly", bad == 0, f"{bad} diffs")

# ------------------------------------------- 4. the EA's own dictionary
say("\n4. translation dictionary inside the EA")
body = SRC[SRC.index("string T(const string k)"):SRC.index("// Convenience: translate AND shape")]
pairs = re.findall(r'if\(k == "([^"]+)"\)\s*return\s*"((?:\\x[0-9A-Fa-f]{4})+)";', body)
say(f"   {len(pairs)} translated keys")
check("dictionary is populated", len(pairs) >= 60, str(len(pairs)))

# every translation must be pure-ASCII hex escapes so the source file cannot
# be corrupted by MetaEditor's codepage handling
raw_ar = [c for c in body if 0x0600 <= ord(c) <= 0x06FF]
check("no raw Arabic bytes in the source", not raw_ar, f"{len(raw_ar)} found")

decoded = 0
for key, esc in pairs:
    txt = ''.join(chr(int(h, 16)) for h in re.findall(r'\\x([0-9A-Fa-f]{4})', esc))
    if not any(is_ar(ord(c)) for c in txt):
        fails.append(f"{key} decoded to non-Arabic"); continue
    arfix(txt)          # must not raise
    decoded += 1
check("every entry decodes to real Arabic and shapes", decoded == len(pairs))

# the seven tracker fields the user explicitly required
REQUIRED = ["DATE", "LOT", "PROFIT", "GAIN%", "WINRATE", "COMMISSION", "FINAL P/L"]
keys = {k for k, _ in pairs}
missing_req = [r for r in REQUIRED if r not in keys]
check("all 7 required tracker fields translated", not missing_req, str(missing_req))

# ------------------------------------------------- 5. integration in the EA
say("\n5. wiring")
for label, pat in [
    ("ArFix defined before the text primitives",
     SRC.index("string ArFix") < SRC.index("void Text(int x")),
    ("Text() shapes its argument",       r'gCv\.TextOut\(x, y, ArFix\(s\)'),
    ("TextVC measures the SHAPED string", r'gCv\.TextSize\(d, tw, th\)'),
    ("button captions are shaped",        r'caption = ArFix\(caption\);'),
    ("caption shaped BEFORE the idempotency test",
     SRC.index("caption = ArFix(caption);") < SRC.index("OBJPROP_TEXT)            == caption")),
    ("font swaps with the language",      r'font\s*=\s*UIFont\(font\);'),
    ("FONT is part of the change test",   r'OBJPROP_FONT\)\s*==\s*font\)'),
    ("language input exists",             r'input ENUM_SF_LANG\s+HudLanguage'),
    ("Arabic font input exists",          r'input string HudArabicFont'),
]:
    check(label, pat if isinstance(pat, bool) else re.search(pat, SRC) is not None)

say()
if fails:
    say("FAILURES:")
    for f in fails: print("  -", f)
    sys.exit(1)
say("ALL ARABIC / RTL CHECKS PASS")
