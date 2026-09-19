# Signal Forge PRO — XAUUSD M5 EA (v2.00)

A ground-up enhancement of *Signal Forge XAUUSD M5 EA*, rebuilt around one specific
reality: **a $200 Exness Raw Spread gold account where every 0.01 lot costs $0.07
round turn.**

| | v1 (original) | v2.00 PRO |
|---|---|---|
| Interface | ~20 static rectangle/label objects | Single **antialiased Canvas HUD**, 3 pages, gauge, meters, hover, hotkeys |
| Filters | 11, all equal, all-or-nothing | **14, individually weighted**, −100…+100 conviction score |
| Sizing | Fixed 0.01 lots | Risk %, ladder, or fixed — **commission folded into the risk budget** |
| Cost model | none | Spread + commission modelled **in price points**, enforced on SL/TP/BE |
| Sessions | none | London / Overlap / NY / Asia + rollover + weekend guard (GMT-aware) |
| Risk control | none | Daily loss cap, profit target, trade cap, loss-streak cooldown, DD kill-switch |
| Exits | Fixed TP + point trail | ATR / structure / cost-multiple TP, **true break-even**, partials, chandelier trail, time stop |
| Lines of code | 1,710 | 2,593 |

![HUD](docs/hud_core_preview.png)

---

## 1. The cost model (why this EA exists)

Exness Raw Spread charges **$3.50 per lot per side** on XAUUSD — $7.00 round turn,
or **$0.07 per 0.01 lot**. On a 3-digit gold feed:

```
1 point (0.001) on 0.01 lot  =  $0.001
$0.07 commission             =  70 points of price movement
```

That **70-point tax is constant regardless of lot size**, which is the key insight:
commission can be treated as a fixed price distance and folded directly into stops,
targets and break-even. The EA computes this at runtime from `MODE_TICKVALUE`, so it
stays correct if your broker's spec differs.

Verified numbers from the shipped defaults:

| Spread | Round turn | Min TP (3×) |
|---|---|---|
| 10 pts | 80 pts ($0.08) | 240 pts ($0.24) |
| 40 pts | 110 pts ($0.11) | 330 pts ($0.33) |
| 130 pts | 200 pts ($0.20) | 600 pts ($0.60) |

Three places this is enforced:

- **`MinTPtoCostRatio`** — a target must clear 3× the full round turn, or the trade is
  mathematically negative-expectancy no matter the win rate.
- **Stop guard** — stops are floored at 1.5× round turn so cost alone can't stop you out.
- **True break-even** — `BreakEvenPrice()` shifts by spread + commission + lock, so "flat"
  means flat *after the broker is paid*, not flat on the chart.

### Commission drag on a $200 account

| Lots | Per trade | % of $200 | 30 trades/month |
|---|---|---|---|
| 0.01 | $0.07 | 0.035% | **1.05%** |
| 0.02 | $0.14 | 0.070% | **2.10%** |

This is precisely why `MaxTradesPerDay=6` and `MinBarsBetweenTrades=3` ship as defaults.
Overtrading a micro account is a slow bleed, not a dramatic blowup.

---

## 2. Position sizing for a $200 account

`SizingMode = SF_SIZE_RISK` solves for lots including commission:

```
lots × (pointValue × slPoints)  +  lots/0.01 × $0.07  =  equity × risk%
```

Validated output at 1% risk:

| Balance | SL 1500 pts | Lots | Actual risk |
|---|---|---|---|
| $200 | $1.50 | 0.01 | 0.79% |
| $500 | $1.50 | 0.03 | 0.94% |
| $1000 | $1.50 | 0.06 | 0.94% |
| $2000 | $1.50 | 0.12 | 0.94% |

**The micro-account guardian:** if even the 0.01 minimum lot would exceed
`MaxRiskPercentHardCap` (2%), the EA **refuses the trade** and reports
`MIN LOT RISK x% > CAP` rather than quietly over-leveraging. This is the single most
important safety behaviour for a $200 account — with a wide ATR stop, 0.01 lots can
easily be a 3–4% risk, and most EAs will take that trade anyway.

Margin is separately capped at 25% of free margin.

---

## 3. The confluence engine

14 filters each emit bull/bear and carry a **weight**. The score is normalised:

```
score = (Σ weight[bullish] − Σ weight[bearish]) / Σ weight[enabled] × 100
```

Entry arms at `|score| ≥ EntryScoreThreshold` (default 62). Default active set:

| Filter | Weight | Role |
|---|---|---|
| Supertrend | 3.0 | primary trend |
| HTF Bias (H1 EMA 21/55) | 2.5 | regime — *veto power* |
| EMA 9/21 | 2.0 | momentum |
| ADX/DI | 2.0 | trend strength gate |
| Structure (Donchian) | 2.0 | location |
| RSI / MACD / VWAP | 1.5 each | confirmation |

Three modes are available (`SF_CONF_SCORE` / `ALL` / `ANY`), so the original
all-must-align behaviour is still reachable. `RequireHTFAlignment` additionally
hard-vetoes any trade fighting the H1 trend.

**New filters over v1:** HTF Bias, Market Structure, and session-anchored VWAP.

---

## 4. Risk guardians

| Guardian | Default | Effect |
|---|---|---|
| `DailyLossLimitPercent` | 6% | halt for the day |
| `DailyProfitTargetPct` | 6% | bank the day, stop |
| `MaxTradesPerDay` | 6 | commission-drag control |
| `MaxConsecutiveLosses` | 3 | → 60 min cooldown |
| `MaxDailyDrawdownPct` | 10% | **kill switch — flattens positions** |
| `MinAccountBalanceUSD` | $150 | hard floor |
| `ReduceRiskAfterLoss` | on | risk × 0.6 per consecutive loss |

All reset automatically at the daily rollover.

---

## 5. Sessions (Exness servers are GMT+0)

Default windows, in GMT: **London 07–12, Overlap 12–17, NY 17–20.** Asia is **off**
(wide spreads, weak follow-through), rollover 20–22 is blacked out, and Friday
flattens at 19:00. `ServerGMTOffsetHours` retargets everything for a non-GMT broker.

---

## 6. Interface — the Quantum HUD

One `CCanvas` bitmap instead of hundreds of chart objects: antialiased, gradient-shaded,
and far cheaper to repaint.

**Page CORE** — semicircular conviction gauge with sweeping needle; cost-intelligence
readout (spread / commission / round turn / cost-as-%-of-ATR); balance-equity-float-day
chips; risk console with live budget meters; live trade ticket showing the true
break-even price.

**Page FILTERS** — all 14 filters with bias pills, weights, and proportional
contribution bars.

**Page JOURNAL** — trades, win rate, profit factor, max DD, **commission paid to date**,
equity sparkline, and a rolling event log.

Controls: click tabs/buttons, or hotkeys **P** pause · **H** collapse · **C** close all.
Three themes (Quantum / Carbon / Solar) re-skin both HUD and chart.

---

## 7. Install

1. Copy `Signal Forge PRO XAUUSD M5 EA.mq4` → `MQL4/Experts/`
2. Copy the `presets/*.set` files → `MQL4/Presets/`
3. Compile in MetaEditor (F7). Requires the stock `<Canvas\Canvas.mqh>`.
4. Attach to **XAUUSD M5**, enable AutoTrading, load a preset.

| Preset | For |
|---|---|
| `..._200USD.set` | $200–500 micro account |
| `..._1000USD.set` | $1000+, partial TP1 enabled |
| `..._Sniper-Overlap.set` | Overlap only, score ≥72, 3 trades/day |

**Verify before going live:** open Market Watch → Symbols → XAUUSD → Properties and
confirm digits (3) and tick value. If your symbol is 2-digit, point-based inputs
(`MinATRPoints`, `MaxSpreadPoints`, trailing distances) must be divided by 10. The EA
prints a warning in the journal if it detects a non-3-digit gold symbol.

Backtest with **Every tick** modelling and set the tester commission to **$7 per lot**
round turn, otherwise results will be optimistic.

---

## 8. Honest limitations

- **No backtest results are claimed here.** I built and statically verified this code;
  I could not run MetaTrader in this environment. The arithmetic (cost model, sizing,
  HUD geometry) was verified numerically, but *strategy profitability is unproven* —
  forward test on demo before risking money.
- No news-calendar filter; `ManualBlackout` is the manual substitute for NFP/CPI/FOMC.
- The volatility filter uses ATR ratio as a news proxy — it reacts, it doesn't predict.
- A $200 gold account is inherently fragile. A 6% daily loss limit is $12; a single
  0.01-lot trade with a $1.50 stop is already 0.79%. Expectations should be set
  accordingly.

## License

Derived from Signal Forge [LuxAlgo], **CC BY-NC-SA 4.0** — non-commercial, ShareAlike.
Not financial advice.

## v2.01 — Raised HUD + Performance Tracker

**Solid raised styling.** Every panel is now drawn with `RaisedPlate()`: a drop
shadow, a light top/left bevel (`TLite`) and a dark bottom/right bevel (`TDark`),
so the panels physically sit above the chart instead of looking like flat
rectangles. Progress bars use `SunkenWell()` for an inset track with a raised
fill, and each section is tagged with a 3px glowing `AccentSpine()`.

**Vivid palette.** All three themes (QUANTUM / CARBON / SOLAR) were rebuilt at
higher chroma and are now fully opaque (alpha 255, previously 235–238), so
nothing washes out against a light or dark chart.

**Adaptive height.** Each page owns its natural height — CORE 652px,
FILTERS 500px, TRACKER 700px — so no page shows dead space at the bottom.

### Performance Tracker (new third tab)

The old JOURNAL tab is now **TRACKER**, with the exact columns requested:

| DATE | LOTS | PROFIT | GAIN% | WIN% | COMM |
|------|------|--------|-------|------|------|

- One row per trading day for the last `SF_TRACK_DAYS` (6) days, newest first,
  today's row highlighted and marked `*`.
- `PROFIT` is **net** — `OrderProfit() + OrderSwap() + OrderCommission()`.
- `GAIN%` is measured against the balance **at that day's open**, so each row
  answers "what did this day do to the account it started with" rather than
  being distorted by later days.
- `COMM` is the commission actually charged that day, shown negative.
- A **TOTAL** row aggregates lots, net, gain%, win rate and fees.
- A **FINAL P/L** plate shows net, gross, total fees and closing balance —
  colour-coded green/red with a matching deep-tint background.
- A KPI strip (TRADES / WIN RATE / P-FACTOR / MAX DD) and an equity sparkline
  sit above and below the table.

### On-chart result cards

`DrawResultPills()` was replaced with solid **raised box cards**
(`BORDER_RAISED` rectangle labels) — four stacked rows per closed trade:

```
WIN +2.31 USD            <- headline, net result
BUY  0.01 lot  +248p     <- side, size, points captured
GROSS +2.38  FEE -0.07   <- the Raw Spread cost story
GAIN +1.14%  35m         <- account impact and hold time
```

Font size, card width and padding are inputs (`ResultCardFontSize` default 9,
`ResultCardWidth` 172, `ResultCardPadding` 7). Cards re-anchor on every
`CHARTEVENT_CHART_CHANGE` and are culled once scrolled outside the viewport, so
they never freeze against the chart edge. `MaxResultPills` dropped 40 → 25
because each card is now four objects tall.

Previews: `docs/hud_core_preview.png`, `docs/hud_tracker_preview.png`,
`docs/result_card_preview.png`. All three are produced by renderers that parse
the geometry constants straight out of the `.mq4` and assert zero overlaps
(`docs/render_hud_preview.py`, `docs/render_tracker_preview.py`).

### v2.01a — corner-ring bug (found from live MT4 screenshots)

Live screenshots showed an 'O' bubble at every panel corner, which made the
header look overlapped. Root cause: `RoundRect()` built its rounded corners from
`CCanvas::Circle()`, which draws a **full ring**, not a quarter arc. Fixes:

- Added `ArcQuarter()` (midpoint circle restricted to one quadrant) and switched
  `RoundRect()` to it. 108 stray border pixels per panel -> 0.
- Header relaid out right-to-left; the PRO badge is now placed from the
  **measured** wordmark width (`CCanvas::TextWidth`) instead of a hardcoded
  offset, so it cannot land on the wordmark under different font metrics. The
  collapse button and state pill no longer collide.
- BIAS pill on the FILTERS page resized/recentred.

**Why the preview missed it:** the renderer drew panels with PIL's
`rounded_rectangle` — correct corners — so it could not reproduce a bug in the
EA's own corner algorithm. `docs/sfcanvas.py` now re-implements the EA's actual
primitives (`FillCircle`, `Circle`, `ArcQuarter`, `Line`, `RoundRect`) pixel for
pixel, and every renderer asserts zero wrong-quadrant corner pixels.

## v2.02 — live trade cards

The on-chart card is now a **live trade monitor**, not just a post-mortem.

**On trade open** a card appears immediately showing entry, TP, SL and running
P&L, and it **recolours as price moves**:

| state | header | meaning |
|-------|--------|---------|
| blue  | `LIVE +0.00 USD` | just opened, flat |
| green | `LIVE +1.84 USD` | currently in profit (net of commission) |
| red   | `LIVE -1.12 USD` | currently losing |

```
LIVE +1.84 USD              running net P&L, colour-coded
BUY  0.01 lot @ 4271.450    side, size, entry
TP 4274.050  260p           target and distance
SL 4269.850  160p           stop and distance
+184p  +0.92%  12m          points, account impact, time open
```

Live P&L is **net of commission** — if the broker has not yet posted the fee,
it is estimated from `CommissionPer001LotRT`, so the card never flatters the
trade. The live card refreshes on **every tick** (previously the repaint was
gated to `IsTesting()`, so in live trading it only moved when a bar closed).

**On close** the card rewrites itself into the final result:

```
WIN +2.31 USD            net result
BUY  0.01 lot  +248p     side, size, points
GROSS +2.38  FEE -0.07   the Raw Spread cost story
GAIN +1.14%  35m         account impact, hold time
```

### Placement — never on the candles

`FreeLaneY()` scans the high/low of every candle the card's x-span would cover
and parks it entirely above or below that range, `ResultCardGapPx` (18px) clear,
then nudges it further to dodge any card already placed. Wins prefer to sit
above the price, losses below; the live card is parked in the right margin. Each
card is tied back to its entry by a **dotted leader line** (horizontal run at
the entry price, plus a vertical riser when the card had to dodge), with a small
ring marking the exact entry.

`docs/render_chart_cards.py` simulates all of this over synthetic M5 candles and
asserts zero card/candle and card/card overlaps
(`docs/chart_cards_preview.png`, `docs/live_card_states.png`).

**Performance note:** closed cards are only rebuilt when history changes or the
chart moves (`gCardsDirty`); only the cheap live card redraws every tick.
Rebuilding ~125 chart objects at the HUD refresh rate would flicker badly.

## v2.03 — text metrics, working minimise, graded bars, solid bias cards

**Text positioning.** Every label was placed with a hand-tuned magic offset
(`y + SC(5)`, `y + h/2 - SC(7)`, ...) that was calibrated at
`HudScalePercent = 100` for one specific font. Any other scale or font and the
text drifted out of its box. Added `TextVC()` / `TextCenterVC()`, which measure
the real glyph box with `CCanvas::TextSize()` and centre on it. Buttons, chips,
filter rows, KPI cards and the tracker header now use them.

**Minimise / maximise button.** `EnsureHud()` called `DestroyHud()` and
re-created the bitmap label on *every* size change — and a collapse *is* a size
change. The click that triggered it was being dispatched against an object that
had just been deleted, so the toggle appeared dead. It now calls
`CCanvas::Resize()` in place, keeping the object (and the click target) alive.
The glyph is a clear `-` / `+` and the hit box grew to `SC(28)`.

**Strength-graded progress bars.** `MeterGraded()` + `StrengthColor()` blend the
fill colour with the level: weak signals read amber, mid cyan, strong resolves
to the filter's bull/bear colour. Conviction is now readable from colour, not
just bar length.

**BIAS cards — solid raised, white text.** Each filter's bias is a raised plate
whose *background* carries the state, with white `Segoe UI Black` text:

| state | background | text |
|-------|-----------|------|
| FLAT | grey (`TGreyDeep`) | white |
| BULLISH | green (`TBullDeep`) | white |
| BEARISH | red (`TBearDeep`) | white |

`TGreyDeep` was added to all three themes. Labels widened to
BULLISH/BEARISH/FLAT and the row pitch grew to `SC(27)` to fit.
