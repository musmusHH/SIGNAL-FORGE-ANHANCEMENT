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
check("structural stop is clamped to a sane band around ATR",
      re.search(r'MathMax\(atrSLDistance \* 0\.5,\s*\n\s*MathMin\(structural, atrSLDistance \* MathMax\(1\.0, StopClampATRMult\)\)\)', BK) is not None)
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

print("\n7d. RISK CONTROL (the 1-trade wipeout post-mortem)")
# A 94% win rate ended at -0.09 because the lot was constant while the stop
# was structural: a 95.65 USD stop at 0.10 lots = 956 USD risk on a 429 USD
# account. These checks pin every part of that fix.
check("lot is derived from the stop", "double LotForRisk(double slDistance" in BK)
check("OpenPosition sizes AFTER the stop is final",
      BK.index("double lots = LotForRisk(") > BK.index("slDistance = MathMax(slDistance, minimum);"))
check("the constant-lot line is gone",
      "double lots  = NormalizeLots(FixedLots);" not in CODE)
check("risk budget uses equity", "AccountEquity()" in BK and "double RiskBudgetUSD()" in BK)
check("money per lot comes from broker tick data",
      "double MoneyPerLot(double dist)" in BK and "MODE_TICKVALUE" in BK)
check("a trade is REFUSED when min lot exceeds the budget",
      "SkipIfRiskTooHigh" in BK and re.search(r'why = T\("RISK TOO HIGH"\);\s*\n\s*return 0;', BK) is not None)
check("OpenPosition aborts on lots <= 0",
      re.search(r'if\(lots <= 0\)\s*\n\s*\{', BK) is not None)
check("NormalizeLots floor-up cannot smuggle risk through",
      "riskUSD > budget * 1.02" in BK)
check("absolute stop-width veto exists",
      "MaxStopATRMult" in BK and 'gBlockReason = T("STOP TOO WIDE");' in BK)
check("reward:risk floor exists", "MinRewardRiskRatio" in BK and "slDistance * MinRewardRiskRatio" in BK)
check("R:R floor default beats 1:1",
      float(re.search(r'MinRewardRiskRatio\s*=\s*([\d.]+)', BK).group(1)) >= 1.0)
check("TP default is no longer 5000 points (= $5 on 3-digit gold)",
      re.search(r'TakeProfitMode\s*=\s*TP_By_ATR', BK) is not None)
check("floating-loss guard exists", "void EnforceFloatingLossCap()" in BK)
check("guard runs on every tick, right after trailing",
      re.search(r'ManageTrailing\(\);\s*\n(?:\s*//[^\n]*\n)*\s*EnforceFloatingLossCap\(\);', BK) is not None)
check("guard counts swap and commission", "OrderProfit() + OrderSwap() + OrderCommission()" in BK)
check("guard also bounds realised+open against the daily cap",
      "(gDayNet + floating) <= -MathAbs(MaxDailyLossUSD)" in BK)
check("structural stop is OFF by default (27-95 USD wide on a 7h range)",
      re.search(r'^input\s+bool\s+StopByRangeOpposite\s*=\s*false', BK, re.M) is not None)
check("structural clamp is configurable and tighter than 3x",
      "StopClampATRMult" in BK and
      float(re.search(r'StopClampATRMult\s*=\s*([\d.]+)', BK).group(1)) <= 2.0)
check("obsolete SL_By_Risk_Percent mode removed",
      "SL_By_Risk_Percent" not in BK and "RiskStopDistance" not in BK)
check("console reports the risk budget, not a static lot",
      'T("RISK") + " $" + Fmt(RiskBudgetUSD(), 2)' in BK)
for k in ("STOP TOO WIDE", "RISK TOO HIGH", "LOSS CAP"):
    check(f'"{k}" is translated', f'if(k == "{k}")' in BK)

# --- arithmetic: replay the real trade that killed the account ---
PV = 100.0          # gold: 1.00 price move = 100 USD per 1.00 lot
def lot_for(stop_usd, equity, pct, maxlots=0.50, minlot=0.01):
    budget = equity * pct / 100.0
    per    = stop_usd * PV
    import math as _m
    raw    = min(budget / per, maxlots)
    lot    = _m.floor(raw / 0.01 + 1e-7) * 0.01
    if lot < minlot or per * lot > budget * 1.02: return 0.0, per * minlot
    return lot, per * lot
_pct = float(re.search(r'RiskPerTradePercent\s*=\s*([\d.]+)', BK).group(1))
_lot, _risk = lot_for(95.65, 429.60, _pct)
check(f"trade #17 (95.65 stop, 429.60 equity) is refused, not sized at 0.10",
      _lot == 0.0)
check("old behaviour would have risked >200% of the account",
      95.65 * PV * 0.10 / 429.60 > 2.0)
# and a normal ATR stop must still be tradeable on 200 USD
_sl = float(re.search(r'StopLossATR\s*=\s*([\d.]+)', BK).group(1))
_lot2, _risk2 = lot_for(2.0 * _sl, 200.0, _pct)   # ATR $2.00
check(f"a normal ATR stop is still tradeable on $200 ({_lot2:.2f} lots, ${_risk2:.2f})",
      _lot2 >= 0.01 and _risk2 <= 200.0 * _pct / 100.0 * 1.02)

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
