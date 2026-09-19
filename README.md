# Signal Forge PRO — XAUUSD M5 EA (v2.09)

> **v2.05 — the ORIGINAL v1 trading strategy has been restored.**
> The trading engine is now exactly the v1 engine. The entire v2 risk layer
> (sessions, daily loss cap, equity kill-switch, cooldown, adaptive spread,
> cost-aware TP floor, partials, break-even stop, chandelier trail, time stop,
> risk/ladder sizing, weighted confluence scoring) has been **deleted**.
> What is kept from v2 is the **interface only**: the Quantum HUD, the chart
> visuals and the performance tracker, re-pointed at v1 concepts.
> Sections 2–5 below describe the v2 engine and are retained for history —
> **they no longer reflect what the EA does.** See the v2.05 section at the
> bottom for the current behaviour.

A visual rebuild of *Signal Forge XAUUSD M5 EA* for a **$200 Exness Raw Spread
gold account where every 0.01 lot costs $0.07 round turn.**

| | v1 (original) | v2.05 (current) |
|---|---|---|
| **Trading logic** | 11 equal-vote filters, AND/OR | **identical — v1 restored** |
| Interface | ~20 static rectangle/label objects | Single **antialiased Canvas HUD**, 3 pages, gauge, meters, hover, hotkeys |
| Result cards | one-line price tag | **solid raised multi-row cards**, live + closed, overlap-free placement |
| Tracker | none | **DATE · LOT · PROFIT · GAIN% · WINRATE · COMMISSION · FINAL P/L** |
| Sizing | Fixed 0.01 lots | **identical — fixed lots** |
| Risk layer | none | **none (removed in v2.05)** |
| Cost model | none | **reporting only** — never gates a trade |
| Lines of code | 1,710 | 2,714 |

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

## v2.04 — GAIN% and FEE always showed 0.00 on the result cards

Two separate bugs with the same symptom.

**GAIN% stuck at 0.00%.** `gainPct` divided by `gTrkStartBal`, which is written
**only** inside `RebuildStats()` — and the only caller of `RebuildStats()` was
the TRACKER page render block. If you never opened that tab, `gTrkStartBal`
stayed `0`, the `> 0` guard forced `gainPct = 0.0`, and because closed cards are
latched by `gKnownResultHistory` they were never redrawn once that zero was
baked in. Fixes: `DrawResultPills()` now calls `RebuildStats()` itself (it
early-outs unless the history count changed, so it is cheap), plus a fallback to
`AccountBalance()` so the figure is never a silent zero.

**FEE stuck at -0.00.** `MathAbs(OrderCommission())` is genuinely `0` whenever
the broker has not posted the fee — and in the **Strategy Tester** it is always
`0` unless commission is configured in the symbol settings, which is exactly
what the screenshots showed. Added `TradeCommissionUSD()`, which falls back to
`CommissionPer001LotRT × (lots / 0.01)`.

Because an estimated fee is *not* included in `OrderProfit()` either, net is
computed as `gross − comm` in that case rather than `gross + OrderCommission()`
— otherwise the card would show a fee while quietly omitting it from the net.
Estimated fees are rendered as `FEE ~-0.07`; the tilde marks a derived number so
an estimate is never passed off as reported fact. The live card uses the same
helper.

Verified across five cases (broker-reported, tester-zero, tracker-never-opened,
0.10 lot, and a losing trade where the fee must deepen the loss).

---

## v2.05 — ORIGINAL STRATEGY RESTORED

Requested verbatim: *"RESTORE THE LOGIC TRADING THE ORIGINAL STRATEGY KEEP ONLY
THE VISUAL CHANGES."* Scope confirmed as **pure v1 logic** with an **adapted panel**.

### What the EA trades now

The engine is a line-for-line restoration of v1. Verified mechanically: the
functions `GetConditions`, `AdvanceSupertrend`, `SupertrendDirection` and
`RiskStopDistance` are **token-identical** to v1 after normalising whitespace and
three renamed globals; `ManageTrailing` differs only by an
`if(select){...}` → `if(!select) continue;` inversion.

* **11 filters, one equal vote each** — SMA, RSI, MACD, **Supertrend**,
  Stochastic, Bollinger midline, EMA, Awesome Oscillator, Parabolic SAR, CCI,
  ADX/DI. Only **Supertrend is enabled by default** (factor 2.5, length 10),
  which is the original shipped strategy.
* **Combination** — `RequireAllEnabledIndicatorsToAlign` selects AND (default) or OR.
* **Entry** — fires on the bar the combined signal *first* turns true
  (`signal && !previousSignal`), evaluated on the closed bar by default.
* **Stop** — `SL_By_ATR` (1.8 × ATR14, default) or `SL_By_Risk_Percent`.
* **Target** — `TP_By_Points` (5000 pts, default) or `TP_By_ATR` (2.4 ×).
* **Trailing** — points-based, start 700 / distance 100 / step 100.
* **Flip** — `CloseOnOppositeSignal` closes and reverses.
* **Only hard gate** — `MaximumSpreadPoints` (91), plus `IsTradeAllowed()` and
  the manual PAUSE button.

### What was deleted

Sessions and the GMT session map · daily loss cap · daily profit target ·
max trades per day · loss-streak cooldown · equity drawdown kill-switch ·
adaptive spread · cost-aware TP floor · partial take-profit · break-even stop ·
chandelier trail · time stop · risk-percent and ladder sizing · weighted
confluence scoring · HTF bias · structure channel · VWAP · news blackouts.

Input count went **185 → 95**. `SF_FILTERS` went **14 → 11**.

### What the panel shows instead

The dashboard keeps its v2 look and is re-pointed at v1 concepts:

| v2 widget | v2.05 meaning |
|---|---|
| Conviction gauge | **FILTER AGREEMENT** — `(bullVotes − bearVotes) / enabled × 100` |
| `ARM ±62` marker | **MODE: ALL / ANY**, plus a live `n▲ / n▼ of n` vote tally |
| Weight column | **VOTE** — equal share, `100 / enabled %` |
| Contribution bar | **AGREEMENT** — full when the filter sides with the live signal |
| Risk console | **EXECUTION CONSOLE** — SL mode, TP mode, trailing, lots, spread headroom |
| Daily-budget meters | replaced by a spread-headroom meter against `MaximumSpreadPoints` |

The gauge's arm line is now derived, not an input: **100 %** in ALL mode (every
enabled filter must agree), or **`100 / enabled` %** in ANY mode (a single vote
fires). With the default Supertrend-only setup the gauge therefore reads
exactly ±100 whenever a trade can trigger.

### Fixes carried in the same release

* **Commission is now estimated consistently everywhere.** v2.04 taught the
  *cards* to fall back to `CommissionPer001LotRT` when `OrderCommission()`
  reports 0 (common in the tester), but the tracker and equity curve still used
  the raw value — so FEE could read `~-0.70` on a card while the tracker showed
  `0.00`. A single `SelectedNetUSD()` helper now backs the cards, the KPI strip,
  the daily buckets, the GAIN% baseline and the equity curve.
* **`AlertOnEntry` / `PushOnEntry` were dead** after the OnTick rewrite —
  restored inside `OpenPosition`.
* **The five `Show*Panel` inputs never did anything** (dead since v2.00).
  They now genuinely add/remove their block, and the CORE page height is the
  **sum of the enabled panels** rather than a hardcoded 652 px, so switching a
  panel off closes the gap instead of leaving a hole.

### Presets regenerated

The three `.set` files were invalid against the new input list and have been
rebuilt — **86 keys each, validator clean** (no invalid, missing or duplicate keys):

| Preset | Configuration |
|---|---|
| `..._200USD.set` | Stock Supertrend-only, 0.01 lot, spread cap tightened to 60 pts |
| `..._1000USD.set` | 0.05 lot, risk-% stop (0.5 %), ATR target |
| `..._Sniper-Overlap.set` | Supertrend **+ EMA + ADX must all align**, spread cap 45 pts |

### Verification

* Brace / paren / bracket balance: **0 delta**.
* Undefined calls and undefined globals: **none**.
* Duplicate function definitions: **none**. Duplicate inputs: **none**.
* Inputs never read: **none** (was 7 before this release).
* All three renderers pass: HUD text overlaps **NONE**, corner-arc stray pixels
  **0**, tracker fits **692/700 px**, chart cards **no card/candle or card/card
  overlap**.

---

## v2.06 — on-chart result cards: layering, anchoring, separation, sides

Four reported faults, four distinct root causes.

### 1. Cards painted on top of the dashboard

`OBJPROP_ZORDER` was already set to 500 for the HUD and 30 for cards, which
looked correct — but **in MT4 `OBJPROP_ZORDER` only decides which object
receives a mouse click. It does not control draw order.** No z-value would ever
have fixed this.

The fix is geometric: `HudScreenRect()` exposes the panel's pixel rect and the
card allocator treats it as occupied space, exactly like another card. Cards in
the panel's x-band are first moved **sideways** (to the free side of the panel);
only if that fails do they move vertically.

### 2. Cards did not follow the chart, and froze in the tester

The only thing that invalidated card positions was `CHARTEVENT_CHART_CHANGE` —
and **`OnChartEvent` is never delivered inside the Strategy Tester**, which is
precisely where the user saw cards "still in his place".

Replaced with `ViewportMoved()`, which polls a cheap signature of the visible
window — first visible bar, bar count, pixel width/height, and
`CHART_PRICE_MIN`/`CHART_PRICE_MAX` — and marks the cards dirty when it changes.
This covers scroll, zoom, resize **and** vertical price-scale drag, and works
identically live and in the tester.

### 3. Cards overlapped each other

The old nudge step was **4 px**, so cards ended up merely touching. Now a new
input **`ResultCardSeparationPx` (default 40)** is enforced as a hard minimum on
*all four sides*: every occupied rect is inflated by `sep` before the overlap
test, and each displacement clears the obstacle by at least `sep`.

When a column genuinely cannot hold another card with 40 px of daylight,
`FreeLaneY()` returns `SF_NO_LANE` and the card is **skipped rather than
stacked**. Cards are drawn newest-first, so what drops off is always the oldest
result. The LIVE card uses `ForcedLaneY()` and is never skipped.

### 4. BUY/SELL sides were inconsistent

The live card asked for `!isBuy` and closed cards for `isBuy` — contradictory,
and BUY ended up *below* price. Both now use
`above = BuyCardsAbove ? isBuy : !isBuy`, so **BUY sits above price and SELL
below**, switchable with the new `BuyCardsAbove` input.

Side is a **soft** constraint: if the preferred side is blocked by the panel or
another card, the card flips rather than disappearing. Separation, panel
avoidance and staying inside the window are **hard** constraints.

### Verification

`docs/verify_card_layout.py` is a faithful port of `FreeLaneY()` plus the
caller's horizontal dodge, with constants scraped from the `.mq4` so it cannot
drift. It asserts the invariants:

```
CASE 1  five trades closing on the SAME pixel   -> placed=5  separation >= 40px
CASE 2  card anchored on top of the panel       -> onPanel=False
CASE 3  BUY above / SELL below                  -> BUY ABOVE, SELL BELOW
CASE 4  25 cards (MaxResultPills)               -> 0 tight pairs, 0 on panel,
                                                   0 off-window, 10 skipped
RESULT: ALL PLACEMENT INVARIANTS HOLD
```

![card placement](docs/card_placement_proof.png)

The rendered proof (`docs/card_placement_proof.png`) draws the panel, synthetic
candles and 15 anchors, then reports the three hard invariants on the image
itself. Note the 3 "wrong side" cards: with a 656 px panel on an 800 px chart
only 8 px remain above it, so a card in that column is *forced* below — the soft
constraint yielding to the hard ones, as designed.

---

## v2.07 — live-chart overlay, per-filter plots, standalone tracker

Three issues reported against v2.06.

### 1. Indicators drew in the Strategy Tester but were invisible on a live chart

**Root cause.** `DrawOverlay()` was only ever called from *inside* the new-bar
branch of `OnTick()`:

```
if(Time[0] == gLastBar) { ...intrabar work...; return; }   // <-- returns here
gLastBar = Time[0];
...
if(graphics) { BuildHistoricalOrbs(); DrawOverlay(); }     // <-- only here
```

In the Strategy Tester a bar completes every few seconds, so the overlay
appeared instantly and looked correct. On a live **M5** chart that branch runs
once every **five minutes** — and never at all during `OnInit` — so after
attaching the EA the chart stayed bare. Nothing was wrong with the plotting
code itself; it simply was not being reached.

**Fix.**
* `OnInit()` now paints the chart immediately (overlay, orbs, level lines,
  cards, HUD) instead of waiting for a bar close.
* A new `gOverlayDirty` flag is serviced by `OnTimer()`, so any change
  repaints within one HUD refresh (~220 ms).
* The intrabar path of `OnTick()` services it too, because
  `EventSetMillisecondTimer` is **not armed in the tester**.

### 2. Per-indicator visibility control

Each filter row on the **FILTERS** page now carries a small **DRAW** toggle,
positioned between the filter name and the BIAS card, that adds or removes
just that indicator's plot:

| state | glyph | meaning |
|---|---|---|
| lit (cyan) | `O` | drawn on the chart |
| dark | `-` | available, currently hidden |
| flat grey | `-` | no chart representation — not clickable |

Visibility is driven by a **new** `gDrawFilter[]` array, deliberately
independent of `gEnabled[]`: an indicator can vote **without** cluttering the
chart, or be drawn **without** voting.

Only the five filters that have a price-chart representation can be plotted
(`FilterHasOverlay()`): **SMA CROSS, SUPERTREND, BOLLINGER MID, EMA CROSS,
PARABOLIC SAR**. The oscillators (RSI, MACD, Stochastic, Awesome, CCI, ADX/DI)
are read from buffers belonging in a separate sub-window, so there is nothing
meaningful to draw over the candles — their toggle shows `-` and is inert.

New input `OverlayFilters` seeds the startup state — a CSV of indices
(default `"3"` = Supertrend only), `"all"`, or `""` for none. The header
button also acts as a master all-on / all-off.

### 3. Tracker separated into its own panel

The performance tracker is no longer a tab. It is now a **standalone solid
raised panel pinned to the top-right corner**, so the running P/L and the
signal engine are readable at the same time. The HUD tab bar drops from three
tabs to two (**CORE**, **FILTERS**), each now wider.

All required fields are retained: **DATE, LOT, PROFIT, GAIN%, WINRATE,
COMMISSION, FINAL P/L**, plus the KPI strip and equity curve. It has its own
collapse button and pause button, and new inputs `ShowTrackerPanel`,
`TrackerWidthPx` (430), `TrackerHeightPx` (660).

**Implementation.** Both panels are `CCanvas` **pointers**, and every drawing
primitive writes to `gCv`, the current target, so one set of primitives serves
both. `RegisterButton` converts canvas-local coordinates to chart pixels via
the active panel origin (`gCvOx/gCvOy`), which keeps hit-testing correct for
the right-hand panel. `PaintAll()` repaints the HUD first — it owns the shared
button registry — then the tracker.

The button array was resized **16 → 40**: 11 filter rows could otherwise
overflow it. Worst case is now 12 registered buttons.

### Result cards treat the tracker as a second obstacle

`TrackerScreenRect()` joins `HudScreenRect()` in `FreeLaneY()`,
`ForcedLaneY()` and the caller's dodge, so no card lands on either panel.

Fixing this exposed a **latent bug in v2.06**: the horizontal dodge cleared a
panel by `sepX` (20 px) while `FreeLaneY()` tested that band inflated by the
full `sep` (40 px). Cards therefore dodged sideways and were *still* judged to
be in the band, and got shoved below the panel — which is why a BUY card could
appear below price. Both now use `sep`.

### Verification

```
brace / paren / bracket balance ........ 0 / 0 / 0
duplicate function definitions ......... none
used-before-defined (MQL4 is top-down) . none
inputs ................................. 92, all read
presets ................................ 3 files x 92 keys, no missing/extra
render_hud_preview ..................... 0 text overlaps, 0 corner artefacts
render_tracker_preview ................. 0 overlaps, fits 652/660 px
render_chart_cards ..................... no card/candle or card/card overlap
verify_card_layout ..................... ALL PLACEMENT INVARIANTS HOLD
render_two_panel_proof ................. 0 cards on either panel, 0 tight pairs
```

![two-panel proof](docs/two_panel_proof.png)

`docs/render_two_panel_proof.py` is new: it renders both panels over synthetic
candles, drives the **real** allocator, and exits non-zero if any card lands on
a panel, breaches the 40 px separation, or leaves the window.

> **Still unverified:** there is no MQL4 compiler in this environment. The
> structural audits above are static analysis, not a build.

---

## v2.08 — the REAL reason the overlay was invisible on a live chart

v2.07 fixed a genuine bug (the overlay was only drawn from the new-bar branch
of `OnTick`), but it was **not the whole story** — the report came back
unchanged. Digging further found the actual root cause.

### Root cause: `iMA()` returns `0.0`, not `EMPTY_VALUE`, during backfill

On a **live** chart MT4 downloads history **asynchronously**. Until the M5
series is fully backfilled, `iMA()` / `iSAR()` return **`0.0`** for the bars
that are not present yet — *not* `EMPTY_VALUE`.

`PlotSegment()` only rejected `EMPTY_VALUE`:

```cpp
if(v0 == EMPTY_VALUE || v1 == EMPTY_VALUE) return;   // 0.0 slips through
```

So the EA dutifully created `OBJ_TREND` objects **at price 0.0** — present on
the chart, correctly named, but drawn far below the visible price range.
Hence "no indicators on the chart" while `ObjectsTotal()` was non-zero.

In the **Strategy Tester** the history is fully materialised before the first
tick, so `iMA()` never returns `0.0`, every segment lands at a real price, and
all indicators appear. That asymmetry is the whole bug.

**Fix (three parts):**
1. `PlotSegment()` rejects non-positive and non-finite values.
2. New `SeriesReady()` probe gates both `DrawOverlay()` and
   `BuildHistoricalOrbs()` — the latter is a **one-shot latch**, so latching it
   mid-backfill would have frozen the orbs permanently.
3. `DrawOverlay()` **re-arms** `gOverlayDirty` instead of clearing it when the
   series is not ready, and `OnTimer` retries — so it self-heals within one
   refresh once data lands, rather than waiting 5 minutes for a bar close.

### Diagnostics

`OnInit` now prints the build and overlay state to the Experts log:

```
[SF-PRO] v2.08 build | overlay master=true | bars=5000 | seriesReady=true
         | drawing: SUPERTREND
```

If this line is missing or says `v2.07`, MT4 is running a stale `.ex4` —
recompile. If it says `drawing: (none ...)`, switch a filter ON.

### ON/OFF buttons made explicit

The toggle now reads **`ON` / `OFF`** (green when on) instead of a cryptic
`O`/`-`, and is wider (32×15) so it is easy to hit. Filters with no chart
representation read **`N/A`** and are inert.

Making it wider no longer fit, so four labels were shortened —
`STOCHASTIC→STOCH`, `BOLLINGER MID→BOLL MID`, `AWESOME OSC→AWESOME`,
`PARABOLIC SAR→PSAR` — and the BIAS card moved 142→148 px. Verified column
budget at 100 % scale: name→toggle 9 px, toggle→bias 10 px, bias→vote 6 px.

### Verification

```
brace / paren / bracket ................ 0 / 0 / 0
duplicate / forward-referenced fns ..... none
inputs ................................. 92, all read
presets ................................ 3 x 92 keys, no missing/extra
all five renderers/verifiers ........... pass
```

> Still no MQL4 compiler in this environment — static analysis, not a build.

---

## v2.09 — every button was dead (minimise, tabs, DRAW toggles)

### Root cause: there were no buttons

The HUD's "buttons" were never buttons. They were **pixels painted into a
`CCanvas` bitmap**, plus an in-memory list of rectangles:

```
grep -c OBJ_BUTTON "Signal Forge PRO XAUUSD M5 EA.mq4"   ->  0
```

Not one clickable object existed on the chart. Dispatch depended entirely on
MT4 handing back raw click coordinates, and both routes it used are
unreliable:

* `CHARTEVENT_CLICK` is **not** sent when the click lands on a chart object —
  and the HUD bitmap covers the whole panel, so it swallowed its own clicks.
* `CHARTEVENT_OBJECT_CLICK` is only raised for objects MT4 considers
  interactive. The bitmap is created `SELECTABLE=false` / `HIDDEN=true`, so it
  never qualified.

The result: the minimise button, the tabs and the new DRAW toggles all looked
alive (hover states worked, because those ride on `MOUSE_MOVE`) but no click
was ever delivered. This is why *v2.07's per-filter toggles appeared to do
nothing* — the toggle logic was correct, the click simply never arrived.

### Fix: a real transparent hotspot over every control

`RegisterButton()` now also creates a genuine **`OBJ_BUTTON`** at the same
rectangle, named `SFP_BTN_<id>`, fully transparent (`BGCOLOR`/`BORDER_COLOR`/
`COLOR` = `clrNONE`) with `ZORDER 1000` so it sits above the bitmap. The canvas
still supplies **all** the visuals; the button contributes only a hit target.

MT4 always reports a real button by **name**, so dispatch no longer guesses
coordinates:

```cpp
if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, PFX + "BTN_") == 0)
  {
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);   // un-latch
   HandleHudAction(StringSubstr(sparam, StringLen(PFX + "BTN_")));
  }
```

Supporting details that matter:

* **Un-latching** — an `OBJ_BUTTON` stays visually pressed after a click;
  without resetting `OBJPROP_STATE` it would fire once and then look stuck.
* **Pruning** — `PruneHotspots()` runs after both panels repaint and deletes
  hotspots whose control is no longer on screen. Otherwise switching CORE →
  FILTERS would leave 11 invisible buttons swallowing clicks over blank chart.
* **Ordering** — pruning happens *after* `PaintHud()` + `PaintTracker()` have
  re-registered, so the button currently being clicked always survives.
* **Cleanup** — hotspots are removed when `ShowHUD=false` and on deinit,
  including the "keep visuals after a visual test" path. An invisible button
  with no EA behind it would otherwise eat clicks forever.
* **Escape hatch** — new input `UseClickHotspots` (default `true`). If any
  broker's build renders the transparent button as a visible grey box, set it
  `false` to fall back to the old coordinate path.

The coordinate fallback is **retained**, so both routes are now live.

### Diagnostics

With `VerboseJournal=true` every dispatched action is logged:

```
[SF-PRO] click -> BTN_COLLAPSE
[SF-PRO] click -> DRAW_3
[SF-PRO] DRAW ON  SUPERTREND
```

If a click produces **no** `click ->` line, the event is not reaching the EA
(check that *AutoTrading* is on and the chart is not in a modal state). If it
logs but nothing changes, the handler is at fault — two very different bugs,
now trivially distinguishable.

### Verification

New `docs/verify_click_targets.py` statically proves the whole chain:

```
1. registration wiring ....... DrawButton/DrawMiniToggle -> hotspot   OK
2. every control has a handler  10/10 ids routed                      OK
3. dispatch path ............. by name, un-latched, fallback kept     OK
4. hotspot geometry .......... 0 overlaps, toggle ends 138 < bias 148 OK
5. tracker origin ............ gCvOx/gCvOy applied                    OK
6. cleanup ................... prune + wipe-on-off                    OK
```

Plus the existing suite: 93 inputs all read, 3 presets × 93 keys, and all five
renderers/verifiers pass.

> Still no MQL4 compiler here — static analysis, not a build.

