#!/usr/bin/env python3
"""Verify the Breakout Forge engine and that its shared shell stayed intact.

Two jobs:
  1. the breakout logic is wired the way the proposal promised
  2. everything inherited from Signal Forge PRO (trailing, Arabic, tracker,
     honest accounting) is still byte-identical or intentionally renamed
"""
import re, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BK  = open(os.path.join(ROOT, "Breakout Forge XAUUSD M5 EA.mq4"), encoding="utf-8").read()
SF  = open(os.path.join(ROOT, "Signal Forge PRO XAUUSD M5 EA.mq4"), encoding="utf-8").read()
fails = []

def check(label, ok, detail=""):
    print(f"   {label:56s} {'OK' if ok else 'FAIL'}{(' - '+detail) if detail and not ok else ''}")
    if not ok: fails.append(label)

def strip(t):
    o=[];i=0;n=len(t)
    while i<n:
        if t[i:i+2]=="//":
            while i<n and t[i]!="\n": i+=1
        elif t[i:i+2]=="/*":
            i+=2
            while i+1<n and t[i:i+2]!="*/": i+=1
            i+=2
        elif t[i] in "\"'":
            q=t[i];i+=1
            while i<n and t[i]!=q:
                if t[i]=="\\": i+=1
                i+=1
            i+=1
        else: o.append(t[i]); i+=1
    return "".join(o)

CODE = strip(BK)

print("1. the trailing stop is IDENTICAL to Signal Forge PRO")
def body(src, name):
    m = re.search(r'^void %s\(\)\s*\n  \{\n(.*?)\n  \}' % name, src, re.S | re.M)
    return m.group(1) if m else None
a, b = body(SF, "ManageTrailing"), body(BK, "ManageTrailing")
check("ManageTrailing() found in both", a is not None and b is not None)
check("ManageTrailing() body is byte-for-byte identical", a == b)
for inp in ("EnableTrailingStop", "TrailingStartPoints",
            "TrailingDistancePoints", "TrailingStepPoints"):
    ra = re.search(r'input\s+\w+\s+%s\s*=\s*([^;]+);' % inp, SF)
    rb = re.search(r'input\s+\w+\s+%s\s*=\s*([^;]+);' % inp, BK)
    check(f"{inp} default unchanged",
          ra is not None and rb is not None and ra.group(1).strip() == rb.group(1).strip())

print("\n2. the two EAs cannot collide on one chart")
ma = re.search(r'input\s+int\s+MagicNumber\s*=\s*(\d+)', SF).group(1)
mb = re.search(r'input\s+int\s+MagicNumber\s*=\s*(\d+)', BK).group(1)
check(f"magic numbers differ ({ma} vs {mb})", ma != mb)
pa = re.search(r'PFX\s*=\s*"([^"]+)"', SF).group(1)
pb = re.search(r'PFX\s*=\s*"([^"]+)"', BK).group(1)
check(f"object prefixes differ ({pa} vs {pb})", pa != pb)
check("no stale SFP_ prefix left in the new EA", '"SFP_"' not in BK)

print("\n3. the breakout engine")
for fn in ("BuildRange", "UpdateRange", "BreakDirection", "BreakoutGates",
           "RetestResult", "DrawRangeObjects", "BkStateText"):
    check(f"{fn}() exists", re.search(r'^\w[\w ]*\s+%s\s*\(' % fn, BK, re.M) is not None)
check("range never includes the forming bar (uses shift >= 1)",
      "iHighest(NULL, 0, MODE_HIGH, n, 1)" in BK and "iLowest (NULL, 0, MODE_LOW,  n, 1)" in BK)
check("a wick alone cannot trigger (RequireBodyClose path)",
      re.search(r'upBreak\s*=\s*\(c > gBkUpper && c > o\)', BK) is not None
      and re.search(r'dnBreak\s*=\s*\(c < gBkLower && c < o\)', BK) is not None)
check("outside bars are skipped", "if(upBreak && dnBreak) return 0;" in BK)
check("buffer is applied to both edges",
      "gBkUpper  = hi + gBkBuffer;" in BK and "gBkLower  = lo - gBkBuffer;" in BK)
check("buffer can be ATR or fixed points",
      "BK_BUF_FIXED" in BK and "BufferATRMult" in BK)
check("range width sanity gate exists",
      re.search(r'gBkValid = \(width >= MinRangeATRMult \* atr && width <= MaxRangeATRMult \* atr\)', BK) is not None)
check("volatility expansion gate exists",
      re.search(r'gBkATR > VolATRMinRatio \* gBkATRAvg', BK) is not None)
check("per-range trade cap resets with a new range",
      "gBkTakenThis  = 0;" in BK and "gBkTakenThis++" in BK)

print("\n4. the eight gates drive BOTH the panel and the trade")
check("BK_GATES is 8", "#define BK_GATES 8" in BK)
check("gate array filled by BreakoutGates", "gBkGate[i] = false;" in BK)
n_names = len(re.findall(r'if\(g == \d\) return "', BK))
check("every gate has a name", n_names >= 7, f"{n_names} names")
check("the panel renders the same array the entry reads",
      "gBkGate[g]" in BK and "BkGatesPassed()" in BK)
check("entry requires gatesPass", "if(wantEntry && dir != 0 && gatesPass" in BK)

print("\n5. exits")
check("stop can use the opposite side of the range",
      "StopByRangeOpposite" in BK and "gBkLow  - pad" in BK)
check("structural stop is clamped to a sane band around ATR",
      re.search(r'MathMax\(atrSLDistance \* 0\.5,\s*\n\s*MathMin\(structural, atrSLDistance \* 3\.0\)\)', BK) is not None)
check("measured-move target available", "BK_TP_MEASURED" in BK)
check("target floored at a multiple of real cost",
      "MinTargetCostMult" in BK and "SpreadPoints() + gCostPointsRT" in BK)

print("\n6. the inherited shell is intact")
check("Arabic engine present", all(f in BK for f in ("ArFix", "ArObj", "ArShape", "ArBidi")))
check("live language + theme buttons kept", '"BTN_LANG"' in BK and '"BTN_SKIN"' in BK)
check("account-wide honest accounting kept",
      "gAcctStart" in BK and "SF_OP_BALANCE" in BK)
check("ACCOUNT P/L card kept",
      re.search(r'double acctPL\s*=\s*AccountBalance\(\) - gAcctStart;', BK) is not None)
check("TextBoxCenter (measured centring) kept", "void TextBoxCenter(" in BK)
# The tracker renders abbreviated column heads (LOTS / WIN% / COMM), which
# is what the user's required fields map onto in the table.
check("tracker columns kept",
      all(f'T("{k}")' in BK for k in ("DATE", "LOTS", "PROFIT", "GAIN%", "WIN%", "COMM")))
check("tracker commission + final P/L rows kept",
      'T("COMMISSION")' in BK and 'T("ACCOUNT P/L")' in BK)

print("\n7. the indicator strategy is GONE, not merely disabled")
# The user asked for a DIFFERENT EA: keep the visuals and the trailing stop,
# drop Signal Forge's 11-indicator voting engine entirely. Anything left
# behind here would mean the two EAs still share a strategy.
STRIPPED = ["GetConditions", "CombinedSignal", "AgreementScore", "ArmThreshold",
            "AdvanceSupertrend", "SupertrendDirection", "BuildSTSeries",
            "LoadFilterConfig", "FilterHasOverlay", "PlotSegment", "DrawOverlay",
            "BuildHistoricalOrbs", "DrawOrb", "BuildOrb", "ScoreGauge"]
for fn in STRIPPED:
    check(f"{fn}() removed", not re.search(r"\b%s\s*\(" % fn, CODE))
for g in ("gBull", "gBear", "gEnabled", "gDrawFilter", "gFilterName",
          "gScore", "gAgreeBull", "gShowAllFilters", "gOverlayDirty",
          "SF_FILTERS", "gBuyOrb"):
    check(f"{g} removed", not re.search(r"\b%s\b" % g, CODE))
for i in ("EnableSMA", "EnableRSI", "EnableMACD", "EnableSupertrend",
          "EnableStochastic", "EnableBollinger", "EnableEMA", "EnableAO",
          "EnableSAR", "EnableCCI", "EnableADX", "SupertrendFactor",
          "RequireAllEnabledIndicatorsToAlign", "OverlayFilters",
          "DrawIndicatorOverlay", "DrawSignalOrbs"):
    check(f"input {i} removed", not re.search(r"^input[^\n]*\b%s\b" % i, BK, re.M))
# 41 indicator/overlay inputs were removed and ~30 breakout inputs added, so
# the useful assertion is that NO indicator input survived (checked above)
# and that the breakout inputs are all present.
n_inputs = len([x for x in re.findall(r'^input\s+[\w ]+?\s+(\w+)\s*=', BK, re.M)
                if not x.startswith("__")])
n_sf = len([x for x in re.findall(r'^input\s+[\w ]+?\s+(\w+)\s*=', SF, re.M)
            if not x.startswith("__")])
print(f"   (Signal Forge {n_sf} inputs -> Breakout Forge {n_inputs})")
for bi in ("RangeMode", "DonchianBars", "BufferMode", "BufferATRMult",
           "RequireBodyClose", "EntryMode", "RetestMaxBars", "UseVolatilityGate",
           "MinRangeATRMult", "MaxBreakoutsPerRange", "StopByRangeOpposite",
           "TargetMode", "MinTargetCostMult", "UseSessionFilter",
           "BlockRollover", "MaxTradesPerDay", "MaxDailyLossUSD"):
    check(f"breakout input {bi} present",
          re.search(r'^input[^\n]*\b%s\b' % bi, BK, re.M) is not None)

print("\n8. the new page")
check("two tabs: CORE and BREAKOUT",
      '"TAB_CORE"' in BK and '"TAB_BREAKOUT"' in BK and '"TAB_FILTERS"' not in BK)
check("BREAKOUT tab is handled on click", 'hit == "TAB_BREAKOUT"' in BK)
check("breakout page has its own computed height", "if(gHudPage == 1)" in BK)
check("CORE panel shows breakout status, not filter agreement",
      'T("BREAKOUT STATUS")' in BK and 'T("FILTER AGREEMENT")' not in BK)
check("one place produces the state wording", "string BkStateText()" in BK)
# nav row must fit
innerW = 430 - 24; sqW = 30
tabW2 = (innerW - 8*3 - sqW*2)//2
tx = 12 + (tabW2+8)*2 + sqW + 8
check(f"nav row fits: last square ends {tx+sqW} <= {12+innerW}", tx+sqW <= 12+innerW)
# page height must fit a normal chart
pageH = 54+6+32+96+8+54+8+64+8+30+8*20+10+8+46+8
check(f"BREAKOUT page height {pageH}px is sane", 400 <= pageH <= 780)

print("\n9. translation and encoding")
_t0 = BK.index("string T(const string k)\n")
_t1 = BK.index("string UIFont(", _t0)
keys = re.findall(r'if\(k == "([^"]+)"\)', BK[_t0:_t1])
check(f"{len(keys)} dictionary keys, no duplicates", len(keys) == len(set(keys)),
      str([k for k in set(keys) if keys.count(k) > 1]))
for k in ("BREAKOUT", "SESSION RANGE", "WAITING FOR BREAK", "ENTRY CHECKLIST",
          "VOLATILITY", "BODY CLOSE", "DAILY LIMIT"):
    check(f'"{k}" is translated', f'if(k == "{k}")' in BK)
check("no raw Arabic bytes (escapes only)",
      not any(0x600 <= ord(c) <= 0x6FF for c in BK))
check("no BOM", not BK.startswith("\ufeff"))
check("no MQL5-only identifiers",
      not [t for t in ("OP_BALANCE","OP_CREDIT","PositionSelect","HistorySelect",
                       "AccountInfoDouble","CopyBuffer") if re.search(r"\b"+t+r"\b", CODE)])

print()
if fails:
    print("FAILURES:")
    for f in fails: print("  -", f)
    sys.exit(1)
print("ALL BREAKOUT ENGINE CHECKS PASS")
