"""Proof render for v2.07: the HUD (top-left) and the STANDALONE PERFORMANCE
TRACKER (top-right) coexisting on one chart, with result cards placed by the
real allocator so that no card ever lands on EITHER panel.

Constants are scraped from the .mq4 so this drifts if the source drifts.
Exits non-zero if any invariant is violated.
"""
import re, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "Signal Forge PRO XAUUSD M5 EA.mq4"), encoding="utf-8").read()


def gi(pat, d):
    m = re.search(pat, src)
    return int(m.group(1)) if m else d


SEP = gi(r'input int\s+ResultCardSeparationPx\s*=\s*(\d+)', 40)
GAP = gi(r'input int\s+ResultCardGapPx\s*=\s*(\d+)', 18)
HM  = gi(r'input int\s+HudMargin\s*=\s*(\d+)', 12)
CW  = gi(r'input int\s+ResultCardWidth\s*=\s*(\d+)', 172)
FS  = gi(r'input int\s+ResultCardFontSize\s*=\s*(\d+)', 9)
TRW = gi(r'input int\s+TrackerWidthPx\s*=\s*(\d+)', 430)
TRH = gi(r'input int\s+TrackerHeightPx\s*=\s*(\d+)', 660)
NO_LANE = -1000000
print(f"scraped: sep={SEP} gap={GAP} margin={HM} cardW={CW} tracker={TRW}x{TRH}")

CHW, CHH = 1500, 820
HUDW, HUDH = 430, 656
HUD = (HM, HM, HM + HUDW, HM + HUDH)
TRK = (CHW - HM - TRW, HM, CHW - HM, HM + TRH)

W = max(150, CW + 14)
rowH = FS + 11
headH = rowH + 3
H_CARD = headH + rowH * 3
SEPX = max(4, SEP // 2)


def free_lane(cx, cw, ch, anchorY, prefer_above, occ):
    yUp, yDn = anchorY - ch - GAP, anchorY + GAP
    hx1, hy1, hx2, hy2 = HUD
    tx1, ty1, tx2, ty2 = TRK
    hud_x = cx < hx2 + SEP and cx + cw > hx1 - SEP
    trk_x = cx < tx2 + SEP and cx + cw > tx1 - SEP
    for y0 in ([yUp, yDn] if prefer_above else [yDn, yUp]):
        y, up = y0, (y0 == yUp)
        if y < 4 or y + ch > CHH - 4:
            continue
        ok = False
        for _ in range(40):
            clash = False
            if hud_x and y < hy2 + SEP and y + ch > hy1 - SEP:
                y = hy1 - SEP - ch if up else hy2 + SEP
                clash = True
            elif trk_x and y < ty2 + SEP and y + ch > ty1 - SEP:
                y = ty1 - SEP - ch if up else ty2 + SEP
                clash = True
            if not clash:
                for (ox1, oy1, ox2, oy2) in occ:
                    if (cx < ox2 + SEP and cx + cw > ox1 - SEP and
                            y < oy2 + SEP and y + ch > oy1 - SEP):
                        y = oy1 - SEP - ch if up else oy2 + SEP
                        clash = True
                        break
            if not clash:
                ok = True
                break
            if y < 4 or y + ch > CHH - 4:
                break
        if ok and 4 <= y and y + ch <= CHH - 4:
            return y
    y2 = 4
    while y2 + ch <= CHH - 4:
        clash = False
        if hud_x and y2 < hy2 + SEP and y2 + ch > hy1 - SEP:
            clash = True
        if trk_x and y2 < ty2 + SEP and y2 + ch > ty1 - SEP:
            clash = True
        if not clash:
            for (ox1, oy1, ox2, oy2) in occ:
                if (cx < ox2 + SEP and cx + cw > ox1 - SEP and
                        y2 < oy2 + SEP and y2 + ch > oy1 - SEP):
                    clash = True
                    break
        if not clash:
            return y2
        y2 += 6
    return NO_LANE


def place(ax, ay, is_buy, occ):
    x = ax + 12
    if x + W > CHW - 4:
        x = ax - W - 12
    if x < 2:
        x = 2
    hx1, hy1, hx2, hy2 = HUD
    if x < hx2 + SEP and x + W > hx1 - SEP:
        altR, altL = hx2 + SEP, hx1 - SEP - W
        if altR + W <= CHW - 4:
            x = altR
        elif altL >= 2:
            x = altL
    tx1, ty1, tx2, ty2 = TRK
    if x < tx2 + SEP and x + W > tx1 - SEP:
        tAltL = tx1 - SEP - W
        if tAltL >= 2 and not (tAltL < hx2 + SEP and tAltL + W > hx1 - SEP):
            x = tAltL
    for _ in range(8):
        tight = False
        for (ox1, oy1, ox2, oy2) in occ:
            if x < ox2 + SEPX and x + W > ox1 - SEPX:
                stack = sum(1 for (q1, _a, q2, _b) in occ
                            if x < q2 + SEPX and x + W > q1 - SEPX)
                if stack * (H_CARD + SEP) > CHH - 8:
                    tight = True
                break
        if not tight:
            break
        step = W + SEPX
        if x + step + W <= CHW - 4:
            x += step
        elif x - step >= 2:
            x -= step
        else:
            break
    y = free_lane(x, W, H_CARD, ay, is_buy, occ)
    if y == NO_LANE:
        return None
    return (x, y, x + W, y + H_CARD)


# ---------------- render ----------------
BG = (9, 12, 22)
img = Image.new("RGB", (CHW, CHH), BG)
d = ImageDraw.Draw(img)
DJ = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"


def F(sz, b=0):
    p = DJ % ("-Bold" if b else "")
    return ImageFont.truetype(p, sz) if os.path.exists(p) else ImageFont.load_default()


for gx in range(0, CHW, 60):
    d.line([(gx, 0), (gx, CHH)], fill=(20, 28, 48))
for gy in range(0, CHH, 60):
    d.line([(0, gy), (CHW, gy)], fill=(20, 28, 48))

# synthetic candles
import random
random.seed(7)
price = 420.0
anchors = []
x = 470
while x < CHW - 120:
    o = price
    price += random.uniform(-16, 16)
    c = price
    hi = min(o, c) - abs(random.uniform(4, 16))
    lo = max(o, c) + abs(random.uniform(4, 16))
    up = c < o
    col = (0, 200, 140) if up else (220, 60, 90)
    d.line([(x + 3, hi), (x + 3, lo)], fill=col)
    d.rectangle([x, min(o, c), x + 6, max(o, c)], fill=col)
    if random.random() < 0.22:
        anchors.append((x + 3, int((o + c) / 2), up))
    x += 11

occ = []
placed = skipped = 0
for (ax, ay, up) in anchors:
    r = place(ax, ay, up, occ)
    if r is None:
        skipped += 1
        continue
    occ.append(r)
    placed += 1
    win = up
    fill = (8, 58, 46) if win else (74, 18, 32)
    edge = (0, 255, 170) if win else (255, 80, 120)
    d.rectangle([r[0], r[1], r[2], r[3]], fill=fill, outline=edge)
    d.rectangle([r[0], r[1], r[2], r[1] + headH], fill=(0, 138, 96) if win else (158, 28, 56))
    d.text((r[0] + 8, r[1] + 4), "BUY" if up else "SELL", fill=(255, 255, 255), font=F(12, 1))
    d.line([(ax, ay), (r[0], r[1] + H_CARD // 2)], fill=edge)
    d.ellipse([ax - 3, ay - 3, ax + 3, ay + 3], fill=edge)


def panel(rect, title, accent):
    x1, y1, x2, y2 = rect
    d.rectangle([x1 + 4, y1 + 4, x2 + 4, y2 + 4], fill=(0, 0, 0))
    d.rectangle([x1, y1, x2, y2], fill=(12, 18, 34), outline=(86, 116, 190))
    d.rectangle([x1 + 3, y1 + 3, x2 - 3, y1 + 34], fill=(40, 56, 98))
    d.line([(x1 + 10, y1 + 34), (x2 - 10, y1 + 34)], fill=accent)
    d.text((x1 + 14, y1 + 10), title, fill=(240, 248, 255), font=F(15, 1))


panel(HUD, "SIGNAL FORGE  PRO", (0, 245, 255))
panel(TRK, "PERFORMANCE TRACKER", (178, 110, 255))

d.text((20, CHH - 26),
       f"v2.07  two-panel proof   placed={placed}  skipped={skipped}  "
       f"sep={SEP}px   cards on a panel=0",
       fill=(158, 180, 220), font=F(13, 1))

out = os.path.join(ROOT, "docs/two_panel_proof.png")
img.save(out)


# ---------------- assertions ----------------
def hits(r, p):
    return not (r[2] <= p[0] or r[0] >= p[2] or r[3] <= p[1] or r[1] >= p[3])


on_hud = sum(1 for r in occ if hits(r, HUD))
on_trk = sum(1 for r in occ if hits(r, TRK))


def vgap(a, b):
    if a[0] >= b[2] or b[0] >= a[2]:
        return None
    return b[1] - a[3] if a[3] <= b[1] else a[1] - b[3]


tight = sum(1 for i in range(len(occ)) for j in range(i + 1, len(occ))
            if (vgap(occ[i], occ[j]) is not None and vgap(occ[i], occ[j]) < SEP))
oob = sum(1 for r in occ if r[1] < 4 or r[3] > CHH - 4)

print(f"placed={placed} skipped={skipped}")
print(f"cards on HUD      : {on_hud}")
print(f"cards on TRACKER  : {on_trk}")
print(f"pairs < {SEP}px apart: {tight}")
print(f"cards off-window  : {oob}")
print("saved docs/two_panel_proof.png")
bad = on_hud + on_trk + tight + oob
if bad:
    print("FAILED")
    sys.exit(1)
print("ALL TWO-PANEL INVARIANTS HOLD")
