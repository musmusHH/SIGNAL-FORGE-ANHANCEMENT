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
