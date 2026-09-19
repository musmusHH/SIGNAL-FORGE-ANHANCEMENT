#!/usr/bin/env python3
"""Visual proof of the Arabic shaping + bidi engine compiled into the EA.

PIL, like MetaTrader's canvas, has NO shaping engine and NO bidi: it paints
the code points it is given, left to right. That makes it an accurate stand-in
for MT4's renderer - so the LEFT column below (raw logical text, what MT4
draws today) shows the exact breakage the user reported, and the RIGHT column
(the output of the EA's ArFix) shows what the panel will look like.

Run:  python3 docs/render_arabic_proof.py  ->  docs/arabic_rtl_proof.png
"""
import os, sys, re
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from verify_arabic import arfix, shape, TAB   # reuse the parsed-from-EA engine

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# theme (matches the EA's Quantum palette)
BG, PANEL, EDGE = (11, 15, 26), (18, 24, 40), (37, 48, 74)
CYAN, TXT, DIM = (34, 211, 238), (226, 232, 240), (148, 163, 184)
BAD, GOOD = (248, 113, 113), (52, 211, 153)

ROWS = [
    ("PERFORMANCE TRACKER", "\u0645\u062a\u062a\u0628\u0639 \u0627\u0644\u0623\u062f\u0627\u0621"),
    ("CLOSE ALL",           "\u0625\u063a\u0644\u0627\u0642 \u0627\u0644\u0643\u0644"),
    ("STOP LOSS",           "\u0648\u0642\u0641 \u0627\u0644\u062e\u0633\u0627\u0631\u0629"),
    ("TAKE PROFIT",         "\u062c\u0646\u064a \u0627\u0644\u0623\u0631\u0628\u0627\u062d"),
    ("NO OPEN POSITION",    "\u0644\u0627 \u062a\u0648\u062c\u062f \u0635\u0641\u0642\u0629 \u0645\u0641\u062a\u0648\u062d\u0629"),
    ("FILTER AGREEMENT",    "\u062a\u0648\u0627\u0641\u0642 \u0627\u0644\u0641\u0644\u0627\u062a\u0631"),
    ("FINAL P/L (NET)",     "\u0627\u0644\u0635\u0627\u0641\u064a \u0627\u0644\u0646\u0647\u0627\u0626\u064a (\u0628\u0639\u062f \u0627\u0644\u0639\u0645\u0648\u0644\u0629)"),
    ("MIXED + NUMBERS",     "\u0627\u0644\u0631\u0628\u062d 12.50 \u062f\u0648\u0644\u0627\u0631"),
    ("LATIN FIRST",         "BUY \u0641\u062a\u062d \u0635\u0641\u0642\u0629"),
    ("LAM-ALEF LIGATURE",   "\u0625\u063a\u0644\u0627\u0642"),
]

W, H = 1180, 150 + len(ROWS) * 46 + 70
img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)
fb = ImageFont.truetype(BOLD, 19)
fh = ImageFont.truetype(BOLD, 13)
fr = ImageFont.truetype(FONT, 18)
fs = ImageFont.truetype(FONT, 12)

d.text((28, 24), "ARABIC RTL ENGINE  -  what MetaTrader draws, before and after", font=fb, fill=CYAN)
d.text((28, 52), "PIL has no shaping and no bidi, exactly like MT4's canvas: it paints code points left to right.",
       font=fs, fill=DIM)
d.text((28, 70), "So the left column IS the bug, and the right column IS the fix.", font=fs, fill=DIM)

x0, x1, x2 = 28, 300, 730
ytop = 104
d.rectangle([x0 - 8, ytop - 6, W - 20, H - 40], fill=PANEL, outline=EDGE)
d.text((x0 + 4, ytop + 4), "LABEL", font=fh, fill=DIM)
d.text((x1, ytop + 4), "RAW  (MT4 today)", font=fh, fill=BAD)
d.text((x2, ytop + 4), "ArFix()  (this build)", font=fh, fill=GOOD)
d.line([x0 - 8, ytop + 24, W - 20, ytop + 24], fill=EDGE)

y = ytop + 34
for label, ar in ROWS:
    d.text((x0 + 4, y + 4), label, font=fs, fill=TXT)
    d.text((x1, y), ar, font=fr, fill=BAD)          # logical order, unshaped
    d.text((x2, y), arfix(ar), font=fr, fill=GOOD)  # shaped + reordered
    y += 46
    d.line([x0 - 8, y - 6, W - 20, y - 6], fill=(28, 36, 58))

d.text((28, H - 32),
       f"engine parsed from the EA source: {len(TAB)} letters x 4 contextual forms, 4 lam-alef ligatures, UAX#9 P2/P3+N1/N2+L2",
       font=fs, fill=DIM)

out = os.path.join(HERE, "arabic_rtl_proof.png")
img.save(out)
print("saved", out)

# ---------------------------------------------------------------- figure 2
# Chart objects (OBJ_BUTTON / OBJ_LABEL) are Windows controls and run their
# OWN bidi. PIL cannot emulate that, so instead of drawing raw glyphs this
# figure SIMULATES the Windows control: it takes the string the EA sends and
# applies bidi to it, which is exactly what the control does before painting.
from verify_arabic import bidi as _bidi

def windows_control(sent):
    """What a Windows control displays for a string the EA hands it."""
    return _bidi(sent)

BTN = [
    ("CORE",          "\u0627\u0644\u0631\u0626\u064a\u0633\u064a\u0629"),
    ("FILTERS",       "\u0627\u0644\u0641\u0644\u0627\u062a\u0631"),
    ("PAUSE TRADING", "\u0625\u064a\u0642\u0627\u0641 \u0627\u0644\u062a\u062f\u0627\u0648\u0644"),
    ("ACTIVE ONLY",   "\u0627\u0644\u0646\u0634\u0637\u0629 \u0641\u0642\u0637"),
]
W2, H2 = 1180, 162 + len(BTN) * 46 + 60
im2 = Image.new("RGB", (W2, H2), BG)
d2 = ImageDraw.Draw(im2)
d2.text((28, 24), "WHY BUTTONS NEEDED A DIFFERENT FIX FROM THE CANVAS", font=fb, fill=CYAN)
d2.text((28, 52), "An OBJ_BUTTON is a real Windows control: it applies its OWN bidi to whatever text it is given.", font=fs, fill=DIM)
d2.text((28, 70), "Both columns below are run through that control, so this shows what MT4 actually displays.", font=fs, fill=DIM)
d2.text((28, 88), "v2.13 sent visual order and the control reversed it a second time. v2.14 sends shaped LOGICAL order.", font=fs, fill=DIM)

yb = 116
d2.rectangle([x0 - 8, yb - 6, W2 - 20, H2 - 36], fill=PANEL, outline=EDGE)
d2.text((x0 + 4, yb + 4), "BUTTON", font=fh, fill=DIM)
d2.text((x1, yb + 4), "v2.13  sent ArFix (visual)", font=fh, fill=BAD)
d2.text((x2, yb + 4), "v2.14  sends ArObj (shaped)", font=fh, fill=GOOD)
d2.line([x0 - 8, yb + 24, W2 - 20, yb + 24], fill=EDGE)

y = yb + 34
for label, ar in BTN:
    d2.text((x0 + 4, y + 4), label, font=fs, fill=TXT)
    d2.text((x1, y), windows_control(arfix(ar)), font=fr, fill=BAD)
    d2.text((x2, y), windows_control(shape(ar)), font=fr, fill=GOOD)
    y += 46
    d2.line([x0 - 8, y - 6, W2 - 20, y - 6], fill=(28, 36, 58))

d2.text((28, H2 - 28),
        "both columns simulate the Windows control - only the string the EA sends differs",
        font=fs, fill=DIM)
out2 = os.path.join(HERE, "arabic_button_fix.png")
im2.save(out2)
print("saved", out2)
