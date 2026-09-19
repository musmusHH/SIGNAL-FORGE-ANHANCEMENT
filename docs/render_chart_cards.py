"""Simulates the EA's on-chart trade cards over synthetic M5 candles and
asserts the two hard requirements:
  1. no card overlaps any candle (body or wick)
  2. no card overlaps another card
The placement logic mirrors FreeLaneY() / DrawLiveTradeCard() /
DrawClosedTradeCards() from the .mq4, with constants parsed from source.
"""
import re, os, sys, random
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "Signal Forge PRO XAUUSD M5 EA.mq4"), encoding="utf-8").read()
def g(pat, d):
    m = re.search(pat, src); return int(m.group(1)) if m else d
FS   = g(r'input int    ResultCardFontSize\s*=\s*(\d+)', 9)
CW   = g(r'input int    ResultCardWidth\s*=\s*(\d+)', 172)
PAD  = g(r'input int    ResultCardPadding\s*=\s*(\d+)', 7)
GAP  = g(r'input int    ResultCardGapPx\s*=\s*(\d+)', 18)
print(f"parsed: font={FS} width={CW} pad={PAD} gap={GAP}")

ROWH  = FS + 11
HEADH = ROWH + 3
CARDW = max(150, CW + 14)
W, H  = 1000, 560
DJ = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
def F(sz, b=0):
    p = DJ % ("-Bold" if b else "")
    return ImageFont.truetype(p, sz) if os.path.exists(p) else ImageFont.load_default()

# ---- synthetic candles ----
random.seed(11)
N = 110
price = 4270.0
bars = []
for i in range(N):
    o = price
    c = o + random.uniform(-2.2, 2.4)
    hi = max(o, c) + random.uniform(0.1, 1.3)
    lo = min(o, c) - random.uniform(0.1, 1.3)
    bars.append((o, hi, lo, c)); price = c
pmin = min(b[2] for b in bars) - 1
pmax = max(b[1] for b in bars) + 1
def py(p): return int(H - 30 - (p - pmin) / (pmax - pmin) * (H - 70))
BARW, LEFT = 8, 20
def bx(i): return LEFT + i * BARW

img = Image.new("RGB", (W, H), (11, 15, 26))
d = ImageDraw.Draw(img)
for i in range(0, W, 80): d.line([i, 0, i, H], fill=(22, 29, 46))
for i in range(0, H, 60): d.line([0, i, W, i], fill=(22, 29, 46))

candle_boxes = []
for i, (o, hi, lo, c) in enumerate(bars):
    x = bx(i)
    if x > W - 120: break
    col = (0, 200, 140) if c >= o else (225, 60, 95)
    d.line([x + BARW // 2, py(hi), x + BARW // 2, py(lo)], fill=col)
    y1, y2 = py(max(o, c)), py(min(o, c))
    d.rectangle([x + 1, y1, x + BARW - 2, max(y2, y1 + 1)], fill=col)
    candle_boxes.append((x, py(hi), x + BARW - 1, py(lo)))

def candles_extremes(x1, x2):
    """highest/lowest pixel of every candle whose x-span intersects [x1,x2]"""
    top, bot = None, None
    for (cx1, cy1, cx2, cy2) in candle_boxes:
        if cx2 < x1 or cx1 > x2: continue
        top = cy1 if top is None else min(top, cy1)
        bot = cy2 if bot is None else max(bot, cy2)
    return top, bot

placed = []   # (x1,y1,x2,y2)

def free_lane(cx, cw, ch, anchor_y, prefer_above):
    """mirrors FreeLaneY()"""
    top, bot = candles_extremes(cx, cx + cw)
    y_up = (top - ch - GAP) if top is not None else anchor_y - ch - GAP
    y_dn = (bot + GAP)      if bot is not None else anchor_y + GAP
    cand = [y_up, y_dn] if prefer_above else [y_dn, y_up]
    for y in cand:
        if y < 4 or y + ch > H - 4: continue
        for _ in range(24):
            clash = False
            for (ox1, oy1, ox2, oy2) in placed:
                if cx < ox2 and cx + cw > ox1 and y < oy2 and y + ch > oy1:
                    clash = True
                    y = (oy1 - ch - 4) if prefer_above else (oy2 + 4)
                    break
            if not clash: break
            if y < 4 or y + ch > H - 4: break
        if y >= 4 and y + ch <= H - 4:
            return y
    fy = max(4, min(anchor_y - ch // 2, H - ch - 4))
    return fy

def card(x, y, rows, won, live=False):
    if won is None:   head, body, edge, tb = (30,64,132),(18,32,62),(120,180,255),(185,210,255)
    elif won:         head, body, edge, tb = (0,138,96),(8,58,46),(0,255,170),(150,255,215)
    else:             head, body, edge, tb = (158,28,56),(74,18,32),(255,80,120),(255,180,195)
    h = HEADH + ROWH * (len(rows) - 1)
    for i, txt in enumerate(rows):
        ish = (i == 0)
        rh = HEADH if ish else ROWH
        y0 = y + (0 if ish else HEADH + (i - 1) * ROWH)
        d.rectangle([x, y0, x + CARDW, y0 + rh], fill=head if ish else body, outline=edge)
        d.line([x+1, y0+1, x+CARDW-1, y0+1], fill=(255,255,255) if ish else edge)
        d.text((x + PAD, y0 + rh // 2), txt,
               fill=(255,255,255) if ish else tb,
               font=F(int((FS+1 if ish else FS) * 1.35), 1 if ish else 0), anchor="lm")
    placed.append((x, y, x + CARDW, y + h))
    return h

def leader(ax, ay, cx, cy, ch, col):
    ym = cy + ch // 2
    for xx in range(min(ax, cx - 2), max(ax, cx - 2), 4):
        d.line([xx, ay, xx + 2, ay], fill=col)
    if abs(ym - ay) > 2:
        for yy in range(min(ay, ym), max(ay, ym), 4):
            d.line([cx - 2, yy, cx - 2, yy + 2], fill=col)
    d.ellipse([ax-3, ay-3, ax+3, ay+3], outline=col, width=2)

# ---- three closed trades ----
CLOSED = [
    (16, True,  ["WIN +2.31 USD", "BUY  0.01 lot  +248p", "GROSS +2.38  FEE -0.07", "GAIN +1.14%  35m"]),
    (44, False, ["LOSS -1.62 USD", "SELL 0.01 lot  -155p", "GROSS -1.55  FEE -0.07", "GAIN -0.80%  22m"]),
    (72, True,  ["WIN +3.05 USD", "BUY  0.01 lot  +312p", "GROSS +3.12  FEE -0.07", "GAIN +1.53%  48m"]),
]
for (bi, won, rows) in CLOSED:
    o, hi, lo, c = bars[bi]
    ax, ay = bx(bi) + BARW // 2, py(c)
    x = ax + 12
    if x + CARDW > W - 4: x = ax - CARDW - 12
    ch = HEADH + ROWH * 3
    y = free_lane(x, CARDW, ch, ay, won)
    leader(ax, ay, x, y, ch, (0,255,170) if won else (255,80,120))
    card(x, y, rows, won)

# ---- the live card, parked in the right margin ----
LIVE_BAR = 92
o, hi, lo, c = bars[LIVE_BAR]
ax, ay = bx(LIVE_BAR) + BARW // 2, py(c)
lch = HEADH + ROWH * 4
lx = W - CARDW - 16
ly = free_lane(lx, CARDW, lch, ay, True)
leader(ax, ay, lx, ly, lch, (0,255,170))
card(lx, ly, ["LIVE +1.84 USD", "BUY  0.01 lot @ 4271.450",
              "TP 4274.050  260p", "SL 4269.850  160p",
              "+184p  +0.92%  12m"], None, live=True)

# ================= ASSERTIONS =================
fails = []
for idx, (x1, y1, x2, y2) in enumerate(placed):
    for (cx1, cy1, cx2, cy2) in candle_boxes:
        if x1 < cx2 and x2 > cx1 and y1 < cy2 and y2 > cy1:
            fails.append(f"card{idx} overlaps candle at x={cx1}")
            break
for i in range(len(placed)):
    for j in range(i + 1, len(placed)):
        a, b = placed[i], placed[j]
        if a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]:
            fails.append(f"card{i} overlaps card{j}")
print("card/candle + card/card overlaps:", fails if fails else "NONE")
img.save(os.path.join(ROOT, "docs/chart_cards_preview.png"))
assert not fails, fails
print("saved docs/chart_cards_preview.png")
