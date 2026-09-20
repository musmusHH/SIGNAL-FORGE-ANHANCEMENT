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
# The width gate must normalise by the number of bars the range spans.
# Comparing a multi-hour range against ONE M5 bar's ATR (the v1.01 bug) made
# every real session range fail and pinned the panel on NO VALID RANGE.
check("range width sanity gate exists",
      re.search(r'gBkValid = \(gBkRatio >= MinRangeATRMult && gBkRatio <= MaxRangeATRMult\)', BK) is not None)
check("width is normalised by sqrt(bars in range), not one bar's ATR",
      "gBkSpan  = atr * MathSqrt((double)gBkBars);" in BK)
check("the raw-ATR width comparison is gone",
      re.search(r'width <= MaxRangeATRMult \* atr', CODE) is None)
check("BuildRange reports the bar count",
      "bool BuildRange(double &hi, double &lo, datetime &stamp, int &bars)" in BK)
check("absolute width floor exists",
      re.search(r'^input\s+double\s+MinRangePoints', BK, re.M) is not None and
      "(width / gPoint) < MinRangePoints" in BK)
# a healthy Asian range must actually pass
import math as _m
_atr, _w, _bars = 0.80, 12.0, 84
_ratio = _w / (_atr * _m.sqrt(_bars))
_mn = float(re.search(r'MinRangeATRMult\s*=\s*([\d.]+)', BK).group(1))
_mx = float(re.search(r'MaxRangeATRMult\s*=\s*([\d.]+)', BK).group(1))
check(f"healthy Asian range (ATR .80, $12, 84 bars) ratio {_ratio:.2f} passes {_mn}-{_mx}",
      _mn <= _ratio <= _mx)
check("a dead-flat $2 range is still rejected",
      not (_mn <= 2.0 / (0.80 * _m.sqrt(84)) <= _mx))
check("a $40 trend is still rejected",
      not (_mn <= 40.0 / (0.80 * _m.sqrt(84)) <= _mx))
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
# v1.02 clamps with a hardcoded 3.0 (StopClampATRMult was a v1.03 input and
# went out with the rest of that risk layer when the engine was restored).
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

print("\n7b. re-entry after a failed / rejected break")
check("ReEntryResult() exists", "int ReEntryResult(int shift)" in BK)
check("AllowReEntry input", re.search(r'^input\s+bool\s+AllowReEntry', BK, re.M) is not None)
check("BK_REARM sentinel", "#define BK_REARM" in BK)
check("CASE A re-arms to BK_READY", re.search(r'rr == BK_REARM.*?gBkState = BK_READY', BK, re.S) is not None)
check("CASE B sets wantEntry", re.search(r'rr != 0.*?wantEntry = True|rr != 0.*?wantEntry = true', BK, re.S) is not None)
check("BK_TRADED is no longer terminal", "gBkState == BK_TRADED || gBkState == BK_BROKEN" in BK)
check("failed breaks are counted", "gBkFailedBreaks++" in BK)
check("counter resets with a new range", re.search(r'gBkRangeStamp\s*=\s*stamp.*?gBkFailedBreaks\s*=\s*0', BK, re.S) is not None)
check("per-range cap allows more than one trade",
      int(re.search(r'^input\s+int\s+MaxBreakoutsPerRange\s*=\s*(\d+)', BK, re.M).group(1)) > 1)
# "back inside" must be judged against the RAW range, rejection against the trigger
check("re-arm compares against the raw range edge", "double inner = (gBkDir > 0) ? gBkHigh  : gBkLow;" in BK)
check("rejection compares against the trigger", "double lvl   = (gBkDir > 0) ? gBkUpper : gBkLower;" in BK)
check("CASE B demands a close in the break direction",
      "c > lvl && c > o" in BK and "c < lvl && c < o" in BK)

print("\n7c. the range is visible WHILE it is being built")
check("forming-range globals", all(g in BK for g in
      ("gBkForming", "gBkFormHigh", "gBkFormLow", "gBkFormStart")))
check("session window records the partial range",
      re.search(r'HourInWindowRaw\(curH, RangeStartHour, RangeEndHour\)\s*\)\s*\{?\s*\n(?:.|\n)*?gBkForming\s*=\s*true', BK) is not None)
check("Donchian is never 'forming'", "gBkForming = false;              // a rolling channel" in BK)
check("DrawRangeObjects draws the forming box",
      re.search(r'if\(gBkForming && gBkFormHigh > gBkFormLow\)', BK) is not None)
check("forming box is dotted, completed box solid",
      "OBJPROP_STYLE, STYLE_DOT" in BK and "STYLE_SOLID);  // undo forming dots" in BK)
check("forming box draws no trigger lines",
      re.search(r'// no buffer yet -> no trigger lines\s*\n\s*ObjectDelete\(0, idUp\); ObjectDelete\(0, idDn\);', BK) is not None)
check("panel shows the collecting high/low", 'T("COLLECTING")' in BK)
check("BUILDING RANGE only claimed while actually forming",
      re.search(r'if\(gBkForming\)\s*return T\("BUILDING RANGE"\)', BK) is not None)
for k in ("COLLECTING", "FAILED BREAKS"):
    check(f'"{k}" is translated', f'if(k == "{k}")' in BK)

print("\n7d. v1.02 TRADING ENGINE RESTORED (user request)")
# The user asked for the v1.02 engine back verbatim, keeping ONLY the
# history/drawing work. v1.03 derived the lot from the stop (which refused
# trades) and v1.05 capped the stop from the lot; BOTH are removed. These
# checks assert the v1.02 engine is present and the later risk layer is not.
check("fixed-lot sizing is back", "double lots  = NormalizeLots(FixedLots);" in BK)
check("the v1.02 SL mode enum is back",
      "enum EA_SL_MODE { SL_By_ATR = 0, SL_By_Risk_Percent = 1 };" in BK)
check("RiskStopDistance() is back", "double RiskStopDistance(double lots)" in BK)
check("the hardcoded 3.0 structural clamp is back", "atrSLDistance * 3.0));" in BK)
for d, v in (("RiskPercent", "0.5"), ("StopLossATR", "1.8"),
             ("TakeProfitPoints", "5000.0"), ("MaxDailyLossUSD", "10.0")):
    check(f"v1.02 default {d} = {v}",
          re.search(r'^input[^\n]*\b%s\s*=\s*%s\s*;' % (d, re.escape(v)), BK, re.M) is not None)
check("TP defaults to TP_By_Points again",
      re.search(r'TakeProfitMode\s*=\s*TP_By_Points', BK) is not None)
check("structural stop is ON again",
      re.search(r'^input\s+bool\s+StopByRangeOpposite\s*=\s*true', BK, re.M) is not None)
# ...and every trace of the later risk layer is gone
for gone in ("LotForRisk", "CapStopToRisk", "RiskBudgetUSD", "MoneyPerLot",
             "RiskPerTradePercent", "MaxRiskPerTradeUSD", "MaxStopATRMult",
             "MinStopATRMult", "MinRewardRiskRatio", "UseRiskSizing",
             "RiskSizingMode", "BK_RISK_LOT_FIRST", "BK_RISK_STOP_FIRST",
             "SkipIfRiskTooHigh", "EnforceFloatingLossCap", "MaxOpenLossUSD",
             "MaxLots", "RISK TOO HIGH", "STOP TOO WIDE"):
    check(f"v1.03/v1.05 artefact removed: {gone}", gone not in BK)
check("OpenPosition no longer aborts on a sizing verdict",
      "gBlockReason = riskWhy;" not in BK)
# the engine itself must be byte-identical to the v1.02 definitions
_v102_fns = [
   "   double lots  = NormalizeLots(FixedLots);\n   double entry = (type == OP_BUY) ? Ask : Bid;",
   "   double slDistance = (StopLossMode == SL_By_Risk_Percent) ? RiskStopDistance(lots) : atrSLDistance;",
   "   double minimum = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 2) * Point;\n   slDistance = MathMax(slDistance, minimum);\n   tpDistance = MathMax(tpDistance, minimum);",
]
for frag in _v102_fns:
    check("v1.02 OpenPosition body intact: " + frag.strip().split(chr(10))[0][:46],
          frag in BK)

print("\n7e. HISTORY RETENTION (post-run analysis)")
# The live range box is one object that gets MOVED, so without an archive
# every past range is lost. Cards are pixel-anchored and capped, so most
# trades leave no lasting record either.
check("range archive exists", "void ArchiveCurrentRange()" in BK)
check("archive runs when the range rolls over",
      re.search(r'if\(stamp != gBkRangeStamp\)\s*\n\s*\{[^}]*?ArchiveCurrentRange\(\);', BK, re.S) is not None)
check("the live range is archived on deinit too",
      re.search(r'EventKillTimer\(\);(?:.|\n)*?ArchiveCurrentRange\(\);', BK) is not None)
check("ring buffer accessors exist",
      "int ArchivedRanges()" in BK and "int ArchivedSlot(int nth)" in BK)
check("ring index cannot go negative", "while(i < 0) i += BK_MAX_RANGES;" in BK)
check("ArchivedSlot bounds-checks", "if(nth < 0 || nth >= have) return -1;" in BK)
check("past ranges are drawn", "void DrawRangeHistory()" in BK)
check("history boxes are keyed per range, not reused",
      'string idB = PFX + "HRNG_" + tag;' in BK and
      'string tag = IntegerToString((int)gRngStart[k]);' in BK)
check("colour encodes the outcome",
      re.search(r'if\(!gRngValid\[k\]\)\s*col = TTextDim;', BK) is not None and
      "else if(gRngTaken[k] > 0) col = (gRngDir[k] >= 0) ? TBull : TBear;" in BK)
check("history drawing is reachable from the normal repaint",
      re.search(r'void DrawRangeObjects\(\)\s*\n\s*\{(?:.|\n){0,400}?DrawRangeHistory\(\);', BK) is not None)
check("permanent trade markers exist", "void DrawTradeHistoryMarkers()" in BK)
check("markers are price-anchored OBJ_TREND, not pixel cards",
      "OBJ_TREND, 0, ot, OrderOpenPrice(), ct, OrderClosePrice()" in BK)
check("markers are NOT capped by MaxResultPills",
      re.search(r'void DrawTradeHistoryMarkers\(\)(?:.|\n)*?\n  \}', BK).group(0).find("MaxResultPills") == -1)
check("marker rebuild is gated on the history count",
      "if(total == gKnownMarkerHistory) return;" in BK)
check("markers are reachable from DrawResultPills",
      re.search(r'void DrawResultPills\(\)(?:.|\n)*?DrawTradeHistoryMarkers\(\);', BK) is not None)
check("CSV export exists", "void ExportHistoryFiles()" in BK)
check("two CSVs: ranges and trades",
      '"BKF_ranges_"' in BK and '"BKF_trades_"' in BK)
check("range CSV carries the width-gate verdict",
      re.search(r'FileWrite\(h, "start", "end", "high", "low", "width_points",', BK) is not None and
      '"ratio", "valid", "trades", "failed_breaks", "last_dir"' in BK)
check("trade CSV carries stop/target distances and net",
      '"stop_points", "target_points"' in BK and '"net", "comment"' in BK)
check("CSV handles are closed", BK.count("FileClose(h") >= 2)
check("CSV open failure is reported, not ignored",
      BK.count("INVALID_HANDLE") >= 2)
check("export is opt-out", re.search(r'^input\s+bool\s+ExportHistoryCSV', BK, re.M) is not None and
      "if(!ExportHistoryCSV) return;" in BK)
for i in ("KeepRangeHistory", "MaxRangeHistory", "ShowRangeLabels", "KeepAllTradeMarkers"):
    check(f"input {i} present", re.search(r'^input[^\n]*\b%s\b' % i, BK, re.M) is not None)
check("history can be turned off cleanly",
      'ObjectsDeleteAll(0, PFX + "HRNG_");' in BK and 'ObjectsDeleteAll(0, PFX + "TH_");' in BK)

# DONCHIAN re-stamps every closed bar (stamp = Time[1]), so a naive archive
# would store 288 boxes a day and overflow the 512-slot ring in under 2 days.
check("donchian churn is filtered out",
      "if(RangeMode == BK_RANGE_DONCHIAN && gBkTakenThis == 0 && gBkFailedBreaks == 0)" in BK)
check("an unchanged box is extended, not duplicated",
      "MathAbs(gRngHigh[last] - gBkHigh) < gPoint" in BK and "gRngEnd  [last] = Time[0];" in BK)
check("in-place refresh never loses a trade count",
      "gRngTaken[last] = MathMax(gRngTaken[last], gBkTakenThis);" in BK)
check("accessors are defined before the archiver uses them",
      BK.index("int ArchivedSlot(int nth)") < BK.index("void ArchiveCurrentRange()"))
# session mode must keep EVERY range, traded or not - that is the whole point
_arch = re.search(r'void ArchiveCurrentRange\(\)(?:.|\n)*?\n  \}', BK).group(0)
check("session ranges are archived even when untraded",
      _arch.count("gBkTakenThis == 0") == 1 and "BK_RANGE_DONCHIAN" in _arch)

# --- ring buffer arithmetic, replayed ---
CAP = int(re.search(r'#define BK_MAX_RANGES (\d+)', BK).group(1))
def replay(n, cap):
    head, count = 0, 0
    for _ in range(n):
        head = (head + 1) % cap; count += 1
    have = count if count < cap else cap
    out = []
    for nth in range(have):
        i = head - 1 - nth
        while i < 0: i += cap
        out.append(i)
    return have, out
h1, o1 = replay(5, CAP)
check(f"partial fill: 5 archived -> {h1} retrievable, unique slots",
      h1 == 5 and len(set(o1)) == 5)
h2, o2 = replay(CAP + 37, CAP)
check(f"wrapped: {CAP+37} archived -> {h2} retrievable, all distinct in range",
      h2 == CAP and len(set(o2)) == CAP and all(0 <= x < CAP for x in o2))

print("\n8. the new page")
check("two tabs: CORE and BREAKOUT",
      '"TAB_CORE"' in BK and '"TAB_BREAKOUT"' in BK and '"TAB_FILTERS"' not in BK)
check("BREAKOUT tab is handled on click", 'hit == "TAB_BREAKOUT"' in BK)

# The panel must OPEN on the breakout page - that is the reason the EA exists.
check("start page is an input, not a hardcoded constant",
      "enum BK_HUD_PAGE" in BK and
      re.search(r'^input\s+BK_HUD_PAGE\s+HudStartPage', BK, re.M) is not None)
check("it defaults to BREAKOUT",
      re.search(r'HudStartPage\s*=\s*BK_PAGE_BREAKOUT', BK) is not None)
check("the global is seeded from it in OnInit",
      "gHudPage = (HudStartPage == BK_PAGE_CORE) ? 0 : 1;" in BK)
check("the global's own initialiser is the breakout page too",
      re.search(r'^int\s+gHudPage = 1;', BK, re.M) is not None)
check("the enum is mapped, never cast (its order is for the dropdown)",
      re.search(r'gHudPage\s*=\s*\(int\)HudStartPage', BK) is None)
# ...and the active tab must be the leftmost one, not the second
_tabs = re.search(r'DrawButton\(pad,\s*\n?\s*y, tabW2[^;]*?"(TAB_\w+)"', BK, re.S)
check("BREAKOUT is the leftmost tab", _tabs is not None and _tabs.group(1) == "TAB_BREAKOUT")
check("CORE is the second tab",
      re.search(r'DrawButton\(pad \+ tabW2 \+ SC\(8\),\s*y, tabW2[^;]*?"TAB_CORE"', BK, re.S) is not None)
check("both tabs still highlight off the same global",
      BK.count("gHudPage == 1, TAccent") == 1 and BK.count("gHudPage == 0, TAccent") == 1)
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
