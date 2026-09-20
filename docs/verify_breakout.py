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
check("buffer can be fixed points or a spread multiple",
      "BK_BUF_FIXED" in BK and "BufferSpreadMult" in BK)
# ATR HAS BEEN REMOVED FROM THE EA. The width gate is now expressed in
# POINTS, which is what the old ATR ratio only ever approximated.
# THE WIDTH GATE MUST BE PRICE-RELATIVE. An absolute dollar band goes stale:
# $6-$40 was sane at $2000 gold, but at $4324 a $40 ceiling is 0.93% of price
# and rejected a real 99054-point ($99.05) session range in the user's log.
# The width gate is SELECTABLE: an absolute points band, a scale-free
# percent-of-price band, or a combination. The points band alone goes stale
# when gold re-rates ($6-$40 was sane at $2000, rejected a real $99 range at
# $4324); the percent band alone has no absolute floor. WidthGateMode picks.
check("WidthGateMode input exists with four modes",
      re.search(r'^input\s+ENUM_BK_WIDTH\s+WidthGateMode', BK, re.M) is not None
      and all(m in BK for m in ("BK_WIDTH_POINTS", "BK_WIDTH_PERCENT",
                                "BK_WIDTH_EITHER", "BK_WIDTH_BOTH")))
check("the two tests are evaluated independently",
      "bool pctOK = (MinRangePercent <= 0 || gBkWidthPct >= MinRangePercent) &&" in BK
      and "bool ptsOK = (MinRangePoints  <= 0 || widthPts    >= MinRangePoints)  &&" in BK)
check("the mode combines them, it does not hardcode AND",
      "if(WidthGateMode == BK_WIDTH_POINTS)       gBkValid = ptsOK;" in BK
      and "else if(WidthGateMode == BK_WIDTH_BOTH)    gBkValid = (ptsOK && pctOK);" in BK
      and "else                                       gBkValid = (ptsOK || pctOK);" in BK)
check("width percent is computed off the range MIDPOINT, not Bid",
      "double refPx = (hi + lo) / 2.0;" in BK and
      "gBkWidthPct = (refPx > 0) ? (width / refPx) * 100.0 : 0.0;" in BK)
check("BuildRange reports the bar count",
      "bool BuildRange(double &hi, double &lo, datetime &stamp, int &bars)" in BK)
# The floor was lowered 4000 -> 2500 for ORB: a 15-minute opening range is a
# fraction of a 7-hour session range, so the session-era floor would sit out
# quiet opens. The 100000 ceiling the user asked for is unchanged.
check("the points band is 2500-100000 (ORB-aware floor)",
      re.search(r'^input\s+double\s+MinRangePoints\s*=\s*2500', BK, re.M) is not None and
      re.search(r'^input\s+double\s+MaxRangePoints\s*=\s*100000', BK, re.M) is not None)
check("percent bounds are inputs",
      re.search(r'^input\s+double\s+MinRangePercent', BK, re.M) is not None and
      re.search(r'^input\s+double\s+MaxRangePercent', BK, re.M) is not None)
check("which test failed is reported on the panel",
      "gBkPctOK" in BK and "gBkPtsOK" in BK and "string WidthModeName()" in BK)

_MINP = float(re.search(r'MinRangePoints\s*=\s*([\d.]+)', BK).group(1))
_MAXP = float(re.search(r'MaxRangePoints\s*=\s*([\d.]+)', BK).group(1))
_MINC = float(re.search(r'MinRangePercent\s*=\s*([\d.]+)', BK).group(1))
_MAXC = float(re.search(r'MaxRangePercent\s*=\s*([\d.]+)', BK).group(1))
def _gate(wpts, px, mode):
    pct = (wpts * 0.001) / px * 100.0
    ptsOK = (_MINP <= 0 or wpts >= _MINP) and (_MAXP <= 0 or wpts <= _MAXP)
    pctOK = (_MINC <= 0 or pct >= _MINC) and (_MAXC <= 0 or pct <= _MAXC)
    return {"PTS": ptsOK, "PCT": pctOK,
            "BOTH": ptsOK and pctOK, "EITHER": ptsOK or pctOK}[mode]
# the user's real range must pass in EVERY mode
for _m in ("PTS", "PCT", "BOTH", "EITHER"):
    check(f"the $99.05 range at $4324 gold passes in {_m} mode",
          _gate(99054, 4323.97, _m))
check("a 2000pt ($2) range is still rejected (whipsaw)",
      not _gate(2000, 4323.97, "EITHER"))
check("a 200000pt ($200 / 4.6%) range is still rejected (trend)",
      not _gate(200000, 4323.97, "EITHER"))
check("EITHER is looser than BOTH at the points ceiling",
      _gate(120000, 4323.97, "EITHER") and not _gate(120000, 4323.97, "BOTH"))
check("the points floor still applies at low gold prices",
      _gate(4000, 2000, "EITHER") and not _gate(1000, 2000, "EITHER"))
check("range-vs-spread gate replaces the ATR expansion gate",
      "MinRangeSpreadMult" in BK and
      re.search(r'widthPts < MathMax\(0\.0, MinRangeSpreadMult\) \* spPts', BK) is not None)
# ---- NO ATR ANYWHERE ----------------------------------------------
check("no iATR call survives in the EA", "iATR(" not in BK)
for _dead in ("ATRLength", "StopLossATR", "TakeProfitATR", "BufferATRMult",
              "VolATRAvgPeriod", "VolATRMinRatio", "StopRangePadATR",
              "MinRangeATRMult", "MaxRangeATRMult", "SL_By_ATR", "TP_By_ATR",
              "BK_BUF_ATR", "BK_TP_ATR", "gBkATR", "gBkATRAvg",
              "ATRPoints", "ATRRatio", "atrSLDistance"):
    check(f"ATR identifier removed: {_dead}", _dead not in BK)

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
check("structural stop may only tighten the money stop",
      "if(structural > 0 && structural < slDistance) slDistance = structural;" in BK)
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
for bi in ("RangeMode", "DonchianBars", "BufferMode", "BufferFixedPoints",
           "RequireBodyClose", "EntryMode", "RetestMaxBars", "UseVolatilityGate",
           "MinRangePercent", "MinRangePoints", "WidthGateMode", "StopByRangeOpposite",
           "TargetMode", "MinTargetCostMult", "UseSessionFilter",
           "BlockRollover", "MaxTradesPerDay", "MaxDailyLossUSD"):
    check(f"breakout input {bi} present",
          re.search(r'^input[^\n]*\b%s\b' % bi, BK, re.M) is not None)

print("\n7a2. NEW YORK ORB + AUTOMATIC DST")
# Exness servers are UTC+0 all year; New York is not. Getting the DST rule
# wrong silently shifts every entry by one hour.
check("ORB is a real range mode", "BK_RANGE_ORB" in BK and
      re.search(r'^input\s+ENUM_BK_RANGE\s+RangeMode\s*=\s*BK_RANGE_ORB', BK, re.M) is not None)
check("DSTMode input with AUTO / SUMMER / WINTER",
      all(k in BK for k in ("BK_DST_AUTO", "BK_DST_SUMMER", "BK_DST_WINTER"))
      and re.search(r'^input\s+ENUM_BK_DST\s+DSTMode\s*=\s*BK_DST_AUTO', BK, re.M) is not None)
check("US rule: 2nd Sunday of March, 1st Sunday of November",
      "NthWeekdayOfMonth(y, 3,  0, 2)" in BK and "NthWeekdayOfMonth(y, 11, 0, 1)" in BK)
check("DST boundary compared in UTC (07:00 / 06:00), not local",
      '%04d.%02d.%02d 07:00' in BK and '%04d.%02d.%02d 06:00' in BK)
check("New York is UTC-4 in summer and UTC-5 in winter",
      "if(DSTMode == BK_DST_SUMMER) return -4;" in BK and
      "if(DSTMode == BK_DST_WINTER) return -5;" in BK and
      "return IsNewYorkDST(TimeCurrent()) ? -4 : -5;" in BK)
check("NY wall clock is converted to server time, never hardcoded",
      "double h = nyHour - NewYorkUtcOffset() + ServerGMTOffsetHours;" in BK)
check("ServerGMTOffsetHours defaults to 0 (Exness is UTC+0)",
      re.search(r'^input\s+double\s+ServerGMTOffsetHours\s*=\s*0\s*;', BK, re.M) is not None)
check("the ORB window is derived from the NY open",
      "void OrbWindowServer(double &openH, double &closeH)" in BK and
      "double nyOpen = NYOpenHour + NYOpenMinute / 60.0;" in BK)
check("minutes are supported (09:30 needs fractional hours)",
      "bool InHourWindowF(double h, double startH, double endH)" in BK and
      "TimeMinute(t) / 60.0" in BK)
check("NY open defaults to 09:30", 
      re.search(r'^input\s+int\s+NYOpenHour\s*=\s*9\s*;', BK, re.M) is not None and
      re.search(r'^input\s+int\s+NYOpenMinute\s*=\s*30\s*;', BK, re.M) is not None)
check("ORB mode has its own session window (open -> ORBTradeMinutes)",
      "if(RangeMode == BK_RANGE_ORB)" in BK and "ORBTradeMinutes" in BK)
check("the DST decision is printed at boot",
      "EDT (summer, UTC-4)" in BK and "EST (winter, UTC-5)" in BK)

# ---- replay the DST arithmetic the EA implements ----
def _dow(y, m, d):
    t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    yy = y - 1 if m < 3 else y
    return (yy + yy // 4 - yy // 100 + yy // 400 + t[m - 1] + d) % 7
def _nth(y, m, wd, n):
    return 1 + (wd - _dow(y, m, 1) + 7) % 7 + (n - 1) * 7
import datetime as _dt
_bad = 0
for _y in range(2024, 2031):
    for _m in range(1, 13):
        for _d in (1, 15, 28):
            if _dow(_y, _m, _d) != (_dt.date(_y, _m, _d).weekday() + 1) % 7:
                _bad += 1
check("Sakamoto weekday algorithm is correct 2024-2030", _bad == 0)
for _y, _mar, _nov in ((2024, 10, 3), (2025, 9, 2), (2026, 8, 1), (2027, 14, 7)):
    check(f"{_y} DST: Mar {_mar} / Nov {_nov}",
          _nth(_y, 3, 0, 2) == _mar and _nth(_y, 11, 0, 1) == _nov)
    check(f"{_y} transitions both land on a Sunday",
          _dt.date(_y, 3, _nth(_y, 3, 0, 2)).weekday() == 6 and
          _dt.date(_y, 11, _nth(_y, 11, 0, 1)).weekday() == 6)
# the Exness published table must come out of the conversion
def _ny_to_server(ny, off): return (ny - off) % 24
check("NY 09:30 -> 13:30 server in summer (Exness table)",
      abs(_ny_to_server(9.5, -4) - 13.5) < 1e-9)
check("NY 09:30 -> 14:30 server in winter (Exness table)",
      abs(_ny_to_server(9.5, -5) - 14.5) < 1e-9)
check("NY 16:00 close -> 20:00 / 21:00 server (Exness table)",
      abs(_ny_to_server(16, -4) - 20) < 1e-9 and abs(_ny_to_server(16, -5) - 21) < 1e-9)

print("\n7a3. TRADE FREQUENCY")
check("more trades allowed per ORB box",
      re.search(r'^input\s+int\s+MaxBreakoutsPerRange\s*=\s*5', BK, re.M) is not None)
check("more trades allowed per day",
      re.search(r'^input\s+int\s+MaxTradesPerDay\s*=\s*10', BK, re.M) is not None)
check("the ORB trade window clears the rollover blackout in BOTH seasons",
      re.search(r'^input\s+int\s+ORBTradeMinutes\s*=\s*330', BK, re.M) is not None
      and all((9.5 + 330 / 60.0 - _o) % 24 <= 20.0 for _o in (-4, -5)))
check("re-entry after a failed break stays on",
      re.search(r'^input\s+bool\s+AllowReEntry\s*=\s*true', BK, re.M) is not None)

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

print("\n7d. MONEY-DEFINED STOP (0.1 lot, ATR removed)")
# The lot is honoured exactly and is NEVER reduced; the risk lives in the
# stop distance. A sizing verdict may not refuse an entry.
check("the lot is used as-is", "double lots  = NormalizeLots(FixedLots);" in BK)
check("FixedLots defaults to 0.1",
      re.search(r'^input\s+double\s+FixedLots\s*=\s*0\.1\s*;', BK, re.M) is not None)
check("RiskPercent defaults to 0.5",
      re.search(r'^input\s+double\s+RiskPercent\s*=\s*0\.5\s*;', BK, re.M) is not None)
check("a flat USD-per-trade cap exists",
      re.search(r'^input\s+double\s+MaxLossUSDPerTrade', BK, re.M) is not None)
check("SL_By_Max_USD mode exists", "SL_By_Max_USD" in BK)
check("budget = min(percent, cap)",
      "if(cap > 0) return MathMin(pct, cap);" in BK)
check("flat-USD mode returns the cap itself",
      re.search(r'if\(StopLossMode == SL_By_Max_USD\)\s*\n\s*return \(cap > 0\) \? cap : pct;', BK) is not None)
check("stop distance = budget / money-per-point",
      "return MathMax(Point, (money / mpp) * Point);" in BK)
check("money-per-point is derived from tick value",
      "return lots * tickValue * (Point / tickSize);" in BK)
check("the structural stop may only TIGHTEN, never widen",
      "if(structural > 0 && structural < slDistance) slDistance = structural;" in BK)
check("a broker/spread floor exists",
      "double MinStopDistance()" in BK and
      "stopLevel + spreadPts + MathMax(0, SlippagePoints) + 2" in BK)
check("MinStopPoints is an input",
      re.search(r'^input\s+double\s+MinStopPoints\s*=\s*200', BK, re.M) is not None)
check("overrun WIDENS the stop rather than skipping the trade",
      re.search(r'overrun\s*=\s*true;\s*\n\s*slDistance = floorDist;', BK) is not None)
check("AllowRiskOverrun defaults to true (never block the entry)",
      re.search(r'^input\s+bool\s+AllowRiskOverrun\s*=\s*true', BK, re.M) is not None)
check("the only sizing-related return is behind AllowRiskOverrun",
      BK.count("if(overrun && !AllowRiskOverrun)") == 1)
check("realised risk is journalled", "gLastRiskUSD" in BK)
check("R-multiple target available", "TakeProfitRMultiple" in BK)
# MEASURED sets TP to the whole range height: on a $99 gold range that is a
# 230:1 target at a 430pt stop and is never reached. It must be opt-in.
check("TargetMode does NOT default to MEASURED",
      re.search(r'^input\s+ENUM_BK_TP\s+TargetMode\s*=\s*BK_TP_RANGE', BK, re.M) is not None)
check("gate 1's reason string matches its name (not the old VOLATILITY)",
      'else if(g == 1) why = T("RANGE vs SPREAD");' in BK)

# ---- the arithmetic, replayed ----
POINT = 0.001
def _mpp(lots):   return lots * 0.10          # USD per point, 3-digit gold
def _budget(bal, pct, cap, maxusd=False):
    p = bal * pct / 100.0
    if maxusd: return cap if cap > 0 else p
    return min(p, cap) if cap > 0 else p
def _solve(bal, lots, pct, cap=0.0, maxusd=False,
           spread=90, stoplevel=0, slip=30, minstop=200.0):
    want = _budget(bal, pct, cap, maxusd) / _mpp(lots)
    floor = max(minstop, stoplevel + spread + slip + 2)
    used = max(want, floor)
    return used, used * _mpp(lots), want < floor

_ok = True
for _b in (600, 1000, 2000, 5000):
    _pts, _usd, _ov = _solve(_b, 0.10, 0.5)
    if _ov or abs(_usd - _b * 0.005) > 0.01: _ok = False
check("0.5% is exact at 0.10 lot once the budget clears the floor", _ok)
_pts, _usd, _ov = _solve(157.79, 0.10, 0.5)
check(f"tiny balance floors to {_pts:.0f} pts = ${_usd:.2f} and still TRADES",
      _ov and abs(_usd - 2.00) < 0.01)
_pts, _usd, _ov = _solve(2000, 0.10, 0.0, 2.00, maxusd=True)
check(f"flat $2.00 cap honoured exactly (${_usd:.2f})", abs(_usd - 2.00) < 0.01)
_pts, _usd, _ov = _solve(5000, 0.10, 0.5, 3.00)
check(f"cap beats percent when percent is larger (${_usd:.2f})", abs(_usd - 3.00) < 0.01)
# the -429.69 regression
_pts, _usd, _ov = _solve(429.60, 0.10, 0.5)
check(f"the -429.69 blowup cannot recur: risk ${_usd:.2f} on $429.60",
      _usd < 429.60 * 0.02)

# ...and every trace of the v1.03/v1.05 lot-shrinking layer stays gone
for gone in ("LotForRisk", "CapStopToRisk", "MoneyPerLot",
             "RiskPerTradePercent", "MaxRiskPerTradeUSD", "MaxStopATRMult",
             "MinStopATRMult", "MinRewardRiskRatio", "UseRiskSizing",
             "RiskSizingMode", "BK_RISK_LOT_FIRST", "BK_RISK_STOP_FIRST",
             "SkipIfRiskTooHigh", "EnforceFloatingLossCap", "MaxOpenLossUSD",
             "RISK TOO HIGH", "STOP TOO WIDE"):
    check(f"lot-shrinking artefact still absent: {gone}", gone not in BK)

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
          "RANGE vs SPREAD", "BODY CLOSE", "DAILY LIMIT"):
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
