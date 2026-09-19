#!/usr/bin/env python3
"""
Faithful port of FreeLaneY() + the caller's horizontal panel dodge, used to
prove the on-chart result-card placement invariants:

  1. no two cards that share an x-span come closer than ResultCardSeparationPx
  2. no card ever overlaps the HUD panel rect
  3. BUY cards sit above their anchor, SELL cards below (BuyCardsAbove=true)
     -- SOFT: falls back to the other side when the preferred one is blocked
        by the panel or another card. Invariants 1, 2 and 4 are HARD.
  4. every card stays inside the chart window

Constants are scraped from the .mq4 so this cannot drift from the EA.
"""
import re, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src  = open(os.path.join(ROOT, "Signal Forge PRO XAUUSD M5 EA.mq4"), encoding="utf-8").read()

def gi(pat, d):
    m = re.search(pat, src); return int(m.group(1)) if m else d

SEP = gi(r'input int\s+ResultCardSeparationPx\s*=\s*(\d+)', 40)
GAP = gi(r'input int\s+ResultCardGapPx\s*=\s*(\d+)', 18)
HM  = gi(r'input int\s+HudMargin\s*=\s*(\d+)', 12)
CW  = gi(r'input int\s+ResultCardWidth\s*=\s*(\d+)', 172)
FS  = gi(r'input int\s+ResultCardFontSize\s*=\s*(\d+)', 9)
NO_LANE = -1000000
print(f"from source: sep={SEP} gap={GAP} hudMargin={HM} cardW={CW} font={FS}")

CHH, CHW = 800, 1400
HUDW, HUDH = 430, 656
HUD = (HM, HM, HM + HUDW, HM + HUDH)

W = max(150, CW + 14)
rowH = FS + 11; headH = rowH + 3
H_CLOSED = headH + rowH * 3

def free_lane(cx, cw, ch, anchorY, prefer_above, occ):
    sep = SEP
    yUp = anchorY - ch - GAP
    yDn = anchorY + GAP
    hx1, hy1, hx2, hy2 = HUD
    hud_x = (hx2 > hx1) and (cx < hx2 + sep) and (cx + cw > hx1 - sep)
    cand = [yUp, yDn] if prefer_above else [yDn, yUp]
    for y0 in cand:
        y = y0; up = (y0 == yUp)
        if y < 4 or y + ch > CHH - 4: continue
        placed = False
        for _ in range(40):
            clash = False
            if hud_x and y < hy2 + sep and y + ch > hy1 - sep:
                y = hy1 - sep - ch if up else hy2 + sep
                clash = True
            if not clash:
                for (ox1, oy1, ox2, oy2) in occ:
                    if (cx < ox2 + sep and cx + cw > ox1 - sep and
                        y  < oy2 + sep and y + ch  > oy1 - sep):
                        y = oy1 - sep - ch if up else oy2 + sep
                        clash = True; break
            if not clash: placed = True; break
            if y < 4 or y + ch > CHH - 4: break
        if placed and 4 <= y and y + ch <= CHH - 4: return y
    # last resort A
    y2 = 4
    while y2 + ch <= CHH - 4:
        clash = False
        if hud_x and y2 < hy2 + sep and y2 + ch > hy1 - sep: clash = True
        if not clash:
            for (ox1, oy1, ox2, oy2) in occ:
                if (cx < ox2 + sep and cx + cw > ox1 - sep and
                    y2 < oy2 + sep and y2 + ch > oy1 - sep):
                    clash = True; break
        if not clash: return y2
        y2 += 6
    return NO_LANE          # caller must skip this card

SEPX = max(4, SEP // 2)

def place_closed(ax, ay, is_buy, occ):
    """mirrors DrawClosedTradeCards(): x choice, panel dodge, stagger, lane"""
    x = ax + 12
    if x + W > CHW - 4: x = ax - W - 12
    if x < 2: x = 2
    hx1, hy1, hx2, hy2 = HUD
    if hx2 > hx1 and x < hx2 + SEPX and x + W > hx1 - SEPX:
        altR = hx2 + SEPX
        altL = hx1 - SEPX - W
        if altR + W <= CHW - 4: x = altR
        elif altL >= 2:         x = altL
    for _ in range(8):
        tight = False
        for (ox1, oy1, ox2, oy2) in occ:
            if x < ox2 + SEPX and x + W > ox1 - SEPX:
                stack = sum(1 for (q1, _a, q2, _b) in occ
                            if x < q2 + SEPX and x + W > q1 - SEPX)
                if stack * (H_CLOSED + SEP) > CHH - 8: tight = True
                break
        if not tight: break
        step = W + SEPX
        if x + step + W <= CHW - 4: x += step
        elif x - step >= 2:         x -= step
        else: break
    y = free_lane(x, W, H_CLOSED, ay, is_buy, occ)
    if y == NO_LANE: return None      # EA does `continue`
    return (x, y, x + W, y + H_CLOSED)

def vgap(a, b):
    if a[0] >= b[2] or b[0] >= a[2]: return None
    return b[1] - a[3] if a[3] <= b[1] else a[1] - b[3]

def on_panel(r):
    return not (r[2] <= HUD[0] or r[0] >= HUD[2] or r[3] <= HUD[1] or r[1] >= HUD[3])

fails = 0

print("\nCASE 1  five trades closing on the SAME pixel")
occ = []
skipped = 0
for i in range(5):
    r = place_closed(600, 400, True, occ)
    if r is None: skipped += 1
    else: occ.append(r)
for i, r in enumerate(occ): print(f"   card{i}: y={r[1]:4d}..{r[3]:4d}")
for i in range(len(occ)):
    for j in range(i + 1, len(occ)):
        g = vgap(occ[i], occ[j])
        if g is not None and g < SEP:
            print(f"   FAIL {i},{j} gap={g}"); fails += 1
print(f"   placed={len(occ)} skipped={skipped}")
print(f"   -> separation >= {SEP}px" if fails == 0 else "   -> FAILED")

print("\nCASE 2  card anchored on top of the panel")
r = place_closed(60, 300, True, [])
print(f"   panel x={HUD[0]}..{HUD[2]} y={HUD[1]}..{HUD[3]}")
print(f"   card  x={r[0]}..{r[2]} y={r[1]}..{r[3]}  onPanel={on_panel(r)}")
if on_panel(r): fails += 1

print("\nCASE 3  BUY above / SELL below (anchor y=400)")
rb = place_closed(900, 400, True,  [])
rs = place_closed(900, 400, False, [])
print(f"   BUY  y={rb[1]}..{rb[3]}  {'ABOVE' if rb[3] <= 400 else 'BELOW'}")
print(f"   SELL y={rs[1]}..{rs[3]}  {'BELOW' if rs[1] >= 400 else 'ABOVE'}")
if rb[3] > 400: print("   FAIL: buy not above");  fails += 1
if rs[1] < 400: print("   FAIL: sell not below"); fails += 1

print("\nCASE 4  25 cards (MaxResultPills) marching across the chart")
occ = []
skipped4 = 0
for i in range(25):
    ax = 80 + i * 52
    r = place_closed(ax, 360 + (i % 5) * 18, (i % 2 == 0), occ)
    if r is None: skipped4 += 1
    else: occ.append(r)
bad = sum(1 for i in range(len(occ)) for j in range(i + 1, len(occ))
          if (vgap(occ[i], occ[j]) is not None and vgap(occ[i], occ[j]) < SEP))
onp = sum(1 for r in occ if on_panel(r))
oob = sum(1 for r in occ if r[1] < 4 or r[3] > CHH - 4)
print(f"   pairs closer than {SEP}px : {bad}")
print(f"   cards overlapping panel  : {onp}")
print(f"   cards outside window     : {oob}")
print(f"   placed={len(occ)} skipped={skipped4} (skipped rather than stacked)")
fails += bad + onp + oob

print("\nRESULT:", "ALL PLACEMENT INVARIANTS HOLD" if fails == 0 else f"{fails} FAILURES")
sys.exit(1 if fails else 0)
