"""Verifies the v2.10 control layer.

MT4 has no transparent OBJ_BUTTON - clrNONE renders BLACK and the object is
drawn ON TOP of the canvas, which is why v2.09 covered the panel in black
boxes. v2.10 stops faking controls with pixels: every button is a REAL
OBJ_BUTTON styled with the theme colours, drawn and hit-tested by MT4 itself.

Checked statically:
  1. DrawButton / DrawMiniToggle emit a real control and register it
  2. no control paints a plate into the bitmap underneath itself
  3. every registered id has a branch in HandleHudAction
  4. dispatch is by object NAME, and the button is un-latched
  5. repaints are idempotent (no delete/recreate mid-click)
  6. geometry: toggle clears the bias card, rows do not overlap
  7. tracker controls use the tracker origin; stale controls are pruned

Exits non-zero on failure.
"""
import re
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = open(os.path.join(ROOT, "Signal Forge PRO XAUUSD M5 EA.mq4"), encoding="utf-8").read()

fails = []


def gi(pat, d):
    m = re.search(pat, SRC)
    return int(m.group(1)) if m else d


def SC(v):
    return v  # 100 % scale


# ---------------------------------------------------------------- 1. wiring
print("1. registration wiring")
for fn in ("DrawButton", "DrawMiniToggle"):
    body = re.search(r'^void ' + fn + r'\([^)]*\)\s*\n\s*\{(.*?)\n  \}', SRC, re.S | re.M)
    if not body:
        fails.append(f"{fn}: body not found")
        continue
    b = body.group(1)
    if "ChartButton" not in b:
        fails.append(f"{fn}: does not emit a real OBJ_BUTTON")
    elif "RegisterButton" not in b:
        fails.append(f"{fn}: does not register its rect")
    else:
        print(f"   {fn:15s} -> ChartButton + RegisterButton  OK")

# the clickable path must NOT paint a plate under itself (that is what the
# real button now draws); only the inert N/A branch may do so
db = re.search(r'^void DrawButton\(.*?\n  \}', SRC, re.S | re.M).group(0)
if "RaisedPlate" in db:
    fails.append("DrawButton still paints a plate into the bitmap")
else:
    print("   DrawButton paints nothing into the bitmap   OK")

cb = re.search(r'^void ChartButton\(.*?\n  \}', SRC, re.S | re.M).group(0)
if "OBJ_BUTTON" not in cb:
    fails.append("ChartButton does not create an OBJ_BUTTON")
if "clrNONE" in cb:
    fails.append("ChartButton uses clrNONE (renders BLACK in MT4)")
else:
    print("   ChartButton avoids clrNONE                  OK")
if "ObjectGetInteger" not in cb or "return;" not in cb:
    fails.append("ChartButton rewrites properties every repaint (click-eating)")
else:
    print("   ChartButton skips no-op updates             OK")

# ------------------------------------------------------- 2. every id handled
print("\n2. every control has a handler")
ids = set(re.findall(r'DrawButton\([^;]*?"([A-Z_]+)"', SRC, re.S))
ids |= {"DRAW_n"} if 'DRAW_" + IntegerToString(i)' in SRC else set()
handler = re.search(r'^void HandleHudAction\(.*?\n  \}', SRC, re.S | re.M).group(0)
for i in sorted(ids):
    if i == "DRAW_n":
        ok = 'StringSubstr(hit, 0, 5) == "DRAW_"' in handler
    else:
        ok = f'"{i}"' in handler
    print(f"   {i:15s} {'OK' if ok else 'NO HANDLER'}")
    if not ok:
        fails.append(f"{i} has no handler")

# --------------------------------------------------- 3. dispatch by name
print("\n3. dispatch path")
ev = re.search(r'^void OnChartEvent\(.*?\n  \}', SRC, re.S | re.M).group(0)
checks = [
    ('CHARTEVENT_OBJECT_CLICK', "listens for object clicks"),
    ('PFX + "BTN_"', "matches our control namespace"),
    ('StringSubstr(sparam', "recovers the id from the object name"),
    ('OBJPROP_STATE, false', "releases the latched button"),
]
if "PaintAll()" in re.search(r'if\(id == CHARTEVENT_MOUSE_MOVE\).*?\n     \}', SRC, re.S).group(0):
    fails.append("mouse-move still repaints (tears down buttons mid-click)")
else:
    print("   mouse-move does not repaint             OK")
for token, why in checks:
    ok = token in ev
    print(f"   {why:38s} {'OK' if ok else 'MISSING'}")
    if not ok:
        fails.append(f"OnChartEvent missing: {why}")
if "CHARTEVENT_CLICK" not in ev:
    fails.append("coordinate fallback removed")
else:
    print("   coordinate fallback retained            OK")

# ------------------------------------------ 4. geometry: filter-row hotspots
print("\n4. FILTERS row hotspot geometry (100 % scale)")
pad = SC(12)
W = SC(430)
innerW = W - pad * 2
rowH = gi(r'int rowH = SC\((\d+)\);\s*\n\s*for\(int i = 0; i < SF_FILTERS', 27)
tW = gi(r'int tW = SC\((\d+)\), tH', 32)
tH = gi(r'int tW = SC\(\d+\), tH = SC\((\d+)\);', 15)
tXoff = gi(r'int tX = pad \+ SC\((\d+)\)', 106)
biasX = gi(r'int bX = pad \+ SC\((\d+)\)', 148)
biasW = gi(r'int bW = SC\((\d+)\), bH', 62)
HM = gi(r'input int    HudMargin\s*=\s*(\d+)', 12)

print(f"   toggle {tW}x{tH} at pad+{tXoff}, bias card at pad+{biasX} w={biasW}")
if tXoff + tW > biasX:
    fails.append(f"toggle (ends {tXoff+tW}) overlaps bias card (starts {biasX})")
else:
    print(f"   toggle ends {tXoff+tW} < bias {biasX}            OK")

# simulate the 11 rows: hotspots must not overlap vertically
y = SC(54) + SC(6) + SC(32) + SC(30)
rects = []
for i in range(11):
    cellH = rowH - SC(3)
    tY = y + (cellH - tH) // 2
    rects.append((HM + pad + tXoff, HM + tY, tW, tH))
    y += rowH
bad = 0
for i in range(len(rects)):
    for j in range(i + 1, len(rects)):
        a, b = rects[i], rects[j]
        if not (a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or
                a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1]):
            bad += 1
print(f"   overlapping row hotspots: {bad}")
if bad:
    fails.append(f"{bad} overlapping hotspots")
print(f"   first row hotspot at chart px {rects[0][:2]}, last {rects[-1][:2]}")

# ------------------------------------------------- 5. tracker origin offset
print("\n5. tracker controls use the tracker origin")
pt = re.search(r'^void PaintTracker\(\).*?\n  \}', SRC, re.S | re.M).group(0)
if "gCvOx" not in pt or "gCvOy" not in pt:
    fails.append("PaintTracker does not set the canvas origin")
else:
    print("   PaintTracker sets gCvOx/gCvOy           OK")
if "gCvOx + x" not in db:
    fails.append("DrawButton ignores the panel origin")
else:
    print("   DrawButton applies gCvOx/gCvOy          OK")

# ------------------------------------------------------------- 6. cleanup
print("\n6. cleanup")
for what, pat in [("prune stale controls", r'PruneHotspots\(\)'),
                  ("wipe on HUD off", r'ObjectsDeleteAll\(0, PFX \+ "BTN_"\)')]:
    ok = re.search(pat, SRC) is not None
    print(f"   {what:24s} {'OK' if ok else 'MISSING'}")
    if not ok:
        fails.append(what + " missing")

print()
if fails:
    print("FAILURES:")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("ALL CONTROL-LAYER CHECKS PASS")
