//+------------------------------------------------------------------+
//|                                Breakout Forge XAUUSD M5 EA       |
//|                    QUANTUM HUD  .  v1.04  .  MQL4 / MetaTrader 4 |
//|                                                                  |
//| A RANGE BREAKOUT engine wearing the Signal Forge PRO interface.  |
//|                                                                  |
//| WHY IT IS BUILT TO REJECT, NOT TO CHASE                          |
//| Gold false-breaks 60-70% of the time, and the most repeatable    |
//| trap of the day is the sweep of the Asian range minutes before   |
//| London opens. A breakout EA that simply buys a new high on gold  |
//| is a machine for donating spread. So every rule here exists to   |
//| throw setups AWAY:                                               |
//|                                                                  |
//|   1. the candle BODY must close beyond the level - a wick        |
//|      through it is a liquidity sweep, not a breakout             |
//|   2. the level is the range edge PLUS a buffer of 0.25 x ATR,    |
//|      so the bar has to commit, and the buffer scales with        |
//|      volatility instead of being a fixed pip count               |
//|   3. ATR(14) must exceed 0.8 x its own SMA50 - if volatility is  |
//|      not expanding, the "break" is noise inside a dead range     |
//|   4. spread <= MaxSpread, checked at the moment of entry         |
//|   5. inside the session window (London / NY overlap by default)  |
//|   6. the range width itself must be sane - too tight is noise,   |
//|      too wide and the stop is further than the trade is worth    |
//|   7. never in the 20:00-22:00 rollover blackout                  |
//|   8. the daily loss limit has not been reached                   |
//|                                                                  |
//| All eight, or no trade. Optionally the EA can also wait for the  |
//| broken level to be RETESTED and hold before entering: fewer      |
//| trades, better fills, tighter stops.                             |
//|                                                                  |
//| WHAT IS SHARED WITH SIGNAL FORGE PRO                             |
//| The Quantum HUD, every theme, the Arabic engine (ArFix for the   |
//| canvas / ArObj for real controls), the live LANGUAGE and THEME   |
//| buttons, the on-chart result cards, the performance tracker with |
//| its account-wide honest accounting, the cost model, and          |
//| ManageTrailing() - copied byte for byte, same inputs, same       |
//| stop-level clamp, same step logic.                               |
//|                                                                  |
//| Runs happily on the SAME chart as Signal Forge PRO: the magic    |
//| number, the object prefix and the panel corner all differ, so    |
//| neither EA can see or disturb the other's trades or objects.     |
//|                                                                  |
//| Exness Raw Spread, 3-digit gold, commission 0.07 USD per 0.01    |
//| lot round turn. Designed to be survivable on a 200 USD account:  |
//| 0.01 lot, one position at a time, hard daily loss limit, and a   |
//| target floored at 3x the full round-turn cost so a winner is     |
//| never eaten by fees.                                             |
//+------------------------------------------------------------------+
#property strict

#include <Canvas\Canvas.mqh>

//==================================================================//
//                          E N U M S                               //
//==================================================================//
// ---- ORIGINAL v1 STRATEGY ENUMS -------------------------------------
enum EA_TP_MODE { TP_By_Points = 0, TP_By_ATR = 1 };

enum ENUM_SF_LANG
  {
   SF_LANG_EN = 0, // English
   SF_LANG_AR = 1  // Arabic (RTL, shaped)
  };

enum ENUM_SF_THEME
  {
   SF_THEME_QUANTUM = 0, // Quantum (cyan / violet on navy)
   SF_THEME_CARBON  = 1, // Carbon (lime / amber on graphite)
   SF_THEME_SOLAR   = 2  // Solar (gold / orange on charcoal)
  };

// ---- breakout engine enums ---------------------------------------
enum ENUM_BK_RANGE
  {
   BK_RANGE_SESSION = 0,   // Session window (Asian range)
   BK_RANGE_DONCHIAN = 1   // Donchian (last N bars)
  };

enum ENUM_BK_BUFFER
  {
   BK_BUF_ATR = 0,         // Buffer = ATR x multiplier
   BK_BUF_FIXED = 1        // Buffer = fixed points
  };

enum ENUM_BK_TP
  {
   BK_TP_ATR = 0,          // Target = ATR x TakeProfitATR
   BK_TP_MEASURED = 1      // Target = range height x multiplier
  };

enum ENUM_BK_ENTRY
  {
   BK_ENTRY_BREAK = 0,     // Enter on the breakout close
   BK_ENTRY_RETEST = 1     // Wait for a retest that holds
  };

enum ENUM_SF_FILTERVIEW
  {
   SF_VIEW_ACTIVE = 0, // Active filters only
   SF_VIEW_ALL    = 1  // All filters
  };

//==================================================================//
//                          I N P U T S                             //
//==================================================================//
input string __01 = "======== IDENTITY / EXECUTION ========"; // .
input int    MagicNumber            = 260915;   // Magic number (differs from Signal Forge PRO)
input double FixedLots              = 0.01;     // Fixed lot size
input int    SlippagePoints         = 50;       // Slippage (points)
input int    MaximumSpreadPoints    = 91;       // Max spread (points, 0=off)
input bool   OnePositionOnly        = true;     // Only one position at a time
input bool   CloseOnOppositeSignal  = true;     // Close when the signal flips
input bool   TradeOnClosedBar       = true;     // Evaluate on the closed bar
input string TradeComment           = "Breakout Forge"; // Order comment

input string __02 = "======== STOP LOSS / TAKE PROFIT ========"; // .
input EA_TP_MODE TakeProfitMode     = TP_By_ATR;    // Take profit mode
input int    ATRLength              = 14;       // ATR length
input double StopLossATR            = 1.5;      // Stop loss = ATR x
input double TakeProfitATR          = 2.4;      // Take profit = ATR x
input double TakeProfitPoints       = 5000.0;   // Take profit (points, TP_By_Points only)
// The target must beat the stop or a high win rate still loses money. The
// engine enforces this ratio as a FLOOR on the target, after every other
// target rule has run. 1.5 means "never aim for less than 1.5x the risk".
input double MinRewardRiskRatio     = 1.5;      // Minimum target / stop ratio (0=off)
input double RiskReferenceBalance   = 0.0;      // 0 = current account balance

// ---- HARD RISK CONTROL (added v1.04 after a 1-trade account wipeout) ----
// The lot used to be a constant while the stop was structural, so risk per
// trade floated with the range width. A 95 USD stop on 0.10 lots is 956 USD
// of risk - on a 429 USD account that is a margin call, and that is exactly
// how a 16-win streak ended at -0.09. The lot is now DERIVED from the stop.
input bool   UseRiskSizing          = true;     // Size the lot from the stop distance
input double RiskPerTradePercent    = 2.0;      // Risk per trade (% of equity)
input double MaxRiskPerTradeUSD     = 0.0;      // Hard cap in USD (0 = off)
input double MaxLots                = 0.50;     // Never exceed this lot
// If even the broker minimum lot risks more than the budget, the only safe
// action is to SKIP the trade. Leave this true; setting it false restores
// the old behaviour of trading anyway at minimum lot.
input bool   SkipIfRiskTooHigh      = true;     // Refuse trades that exceed the budget
// A stop wider than this many ATRs means the structure is too far away to
// pay for. Independent of the clamp, because the clamp scales WITH atr.
input double MaxStopATRMult         = 3.0;      // Reject stops wider than ATR x this

input string __03 = "======== TRAILING STOP ========"; // .
input bool   EnableTrailingStop     = true;     // Enable trailing stop
input double TrailingStartPoints    = 700.0;    // Start trailing after (points)
input double TrailingDistancePoints = 100.0;    // Trailing distance (points)
input double TrailingStepPoints     = 100.0;    // Trailing step (points)

input string __04 = "======== BREAKOUT ENGINE ========"; // .
// ---- how the range is built --------------------------------------
// SESSION : the high/low of a clock window (the Asian range by default).
//           This is the classic London-open breakout.
// DONCHIAN: the highest high / lowest low of the last N closed bars.
//           Always available, so the EA still trades outside session hours.
input ENUM_BK_RANGE RangeMode         = BK_RANGE_SESSION; // Range source
input int    RangeStartHour           = 0;      // SESSION: window start hour (server)
input int    RangeEndHour             = 7;      // SESSION: window end hour (server)
input int    DonchianBars             = 20;     // DONCHIAN: lookback in bars
input bool   ShowRangeBox             = true;   // Draw the range box on the chart

// ---- what counts as a break --------------------------------------
// The body must close beyond the edge PLUS a buffer. A wick through the
// level is a liquidity sweep and is deliberately ignored.
input ENUM_BK_BUFFER BufferMode       = BK_BUF_ATR;  // Buffer type
input double BufferATRMult            = 0.25;   // Buffer = ATR x this
input double BufferFixedPoints        = 250.0;  // Buffer when mode is FIXED (points)
input bool   RequireBodyClose         = true;   // Body close beyond level (not just a wick)

// ---- entry style --------------------------------------------------
// BREAK : enter on the close of the breakout bar - more trades.
// RETEST: wait for price to come back to the broken level and hold -
//         fewer trades, better price, tighter stop.
input ENUM_BK_ENTRY EntryMode         = BK_ENTRY_BREAK; // Entry style
input int    RetestMaxBars            = 12;     // RETEST: give up after N bars
input double RetestTolerancePoints    = 150.0;  // RETEST: how close counts as a touch

// ---- quality gates -------------------------------------------------
input bool   UseVolatilityGate        = true;   // ATR must be expanding
input int    VolATRAvgPeriod          = 50;     // ATR average period
input double VolATRMinRatio           = 0.8;    // ATR > ratio x average ATR
// Width is tested as  width / (ATR * sqrt(barsInRange)), so these are a
// FRACTION OF THE EXPECTED TRAVEL over the range, not a raw ATR multiple.
// 1.0 = exactly the textbook envelope. Below 0.40 the range is dead flat,
// above 3.00 it is a trend, not a range.
input double MinRangeATRMult          = 0.40;   // Min width / expected travel
input double MaxRangeATRMult          = 3.00;   // Max width / expected travel
// The ratio above is relative, so on a very quiet day a 3 USD "range" can
// still look proportionate. Research on the Asian range is blunt about the
// absolute floor: under 6-8 USD the break is whipsaw. 6000 points = 6 USD on
// 3-digit gold. Set to 0 to disable the absolute test.
input double MinRangePoints           = 6000;   // Absolute min width, points
input bool   AllowReEntry             = true;   // Re-enter after a failed / rejected break
input int    MaxBreakoutsPerRange     = 3;      // Max TRADES one range may produce

input string __04c = "======== BREAKOUT EXITS ========"; // .
// OFF by default. The far side of a 7-hour Asian range is 27-95 USD away;
// at the 0.01 lot minimum that IS 27-95 USD of risk, which no small account
// can carry. Switch it on only above ~2000 USD equity.
input bool   StopByRangeOpposite      = false;  // Stop at the far side of the range
input double StopRangePadATR          = 0.5;    // ...padded by ATR x this
input double StopClampATRMult         = 1.5;    // Clamp structural stop to ATRstop x this
input ENUM_BK_TP TargetMode           = BK_TP_ATR; // Target style
input double MeasuredMoveMult         = 1.0;    // MEASURED: range height x this
input double MinTargetCostMult        = 3.0;    // Target >= (spread+commission) x this

input string __04b = "======== SESSION & RISK ========"; // .
// Exness MT4 server time is fixed GMT+0 all year - no DST - so these hours
// are UTC on that broker. London 08:00-16:30, New York 13:30-20:00, and the
// overlap 13:00-17:00 produces most of gold's daily range.
input bool   UseSessionFilter         = true;   // Trade only inside the window
input int    TradeStartHour           = 8;      // Trading window start (server hour)
input int    TradeEndHour             = 20;     // Trading window end (server hour)
input bool   BlockRollover            = true;   // Skip the 20:00-22:00 swap window
input int    RolloverStartHour        = 20;     // Rollover blackout start
input int    RolloverEndHour          = 22;     // Rollover blackout end
input int    MaxTradesPerDay          = 6;      // 0 = unlimited
input double MaxDailyLossUSD          = 10.0;   // Realised daily loss cap
// Checked on every tick against the OPEN position, because a pre-trade
// daily cap cannot stop a trade that is already running.
input double MaxOpenLossUSD           = 8.0;    // Emergency close at this open loss (0=off)

input string __10 = "======== BROKER COST (DISPLAY ONLY) ========"; // .
// Commission never gates a trade in the original strategy - it is used only
// so the result cards and the tracker can report the true cost of a fill.
input double CommissionPer001LotRT  = 0.07;     // Commission per 0.01 lot, round turn

input string __11 = "======== QUANTUM HUD (INTERFACE) ========"; // .
input bool   ShowHUD                = true;     // Master HUD switch
input ENUM_SF_LANG  HudLanguage     = SF_LANG_EN;        // Interface language (EN / AR)
input string HudArabicFont          = "Tahoma";  // Arabic font (Tahoma/Arial/Segoe UI)
input ENUM_SF_THEME HudTheme        = SF_THEME_QUANTUM; // Colour theme
input bool   ApplyChartSkin         = true;     // Re-skin the chart
input bool   ShowHeaderPanel        = true;     // Top command bar
input bool   ShowSignalPanel        = true;     // Signal / agreement panel
input bool   ShowRiskPanel          = true;     // Risk console
input bool   ShowPerformancePanel   = true;     // Performance + equity curve
input bool   ShowTradePanel         = true;     // Live trade ticket
input bool   ShowTrackerPanel       = true;     // Standalone tracker (top-right)
input int    TrackerWidthPx         = 430;      // Tracker panel width (px)
input int    TrackerHeightPx        = 660;      // Tracker panel height (px)
input int    HudMargin              = 12;       // Outer margin (px)
input int    HudRefreshMs           = 220;      // Repaint interval (ms)
input bool   HudInteractive         = true;     // Buttons + hover + hotkeys
input int    HudScalePercent        = 100;      // 80..130 UI scale

input string __12 = "======== CHART VISUALS ========"; // .
// ---- HISTORY / POST-ANALYSIS ----------------------------------------
// The live range box is ONE object that gets moved when a new range is
// built, so yesterday's range used to simply vanish. These keep every past
// range and every closed trade on the chart so a run can be reviewed.
input bool   KeepRangeHistory        = true;    // Keep every past range on the chart
input int    MaxRangeHistory         = 80;      // Past ranges to keep (0 = unlimited)
input bool   ShowRangeLabels         = true;    // Label each past range with its stats
input bool   KeepAllTradeMarkers     = true;    // Entry->exit line for EVERY closed trade
input bool   ExportHistoryCSV        = true;    // Write ranges + trades to CSV on deinit
input bool   DrawTradeLevels        = true;     // Entry/SL/TP lines
input bool   DrawTradeResults       = true;     // Closed trade result cards
// Cards are big, pixel-anchored and would overlap into mush past ~30, so
// this stays capped. The permanent markers (KeepAllTradeMarkers) are the
// uncapped record; the cards are just the detailed readout for recent trades.
input int    MaxResultPills         = 25;       // Max result CARDS on chart (markers are uncapped)
input int    ResultCardFontSize     = 9;        // Result card font size
input int    ResultCardWidth        = 172;      // Result card width (px)
input int    ResultCardPadding      = 7;        // Result card text padding (px)
input bool   ShowLiveTradeCard      = true;     // Live card while a trade is open
input int    ResultCardGapPx        = 18;       // Min gap from candles (px)
input int    ResultCardSeparationPx = 40;       // Min gap BETWEEN result cards (px)
input bool   BuyCardsAbove          = true;     // BUY cards above price, SELL below
input bool   KeepVisualsAfterTest   = true;     // Keep graphics after a visual test

input string __13 = "======== ALERTS ========"; // .
input bool   AlertOnEntry           = false;    // Popup/sound on entry
input bool   PushOnEntry            = false;    // Push notification on entry
input bool   VerboseJournal         = true;     // Detailed journal logging

//==================================================================//
//                    G L O B A L   S T A T E                       //
//==================================================================//

// MQL4 has no OP_BALANCE / OP_CREDIT constants - those belong to MQL5. In
// MQL4 the non-trade rows in the account history report these bare values
// from OrderType(), so name them here rather than leaving 6 and 7 loose in
// the statistics code.
#define SF_OP_BALANCE 6   // deposit or withdrawal
#define SF_OP_CREDIT  7   // credit in or out

// Win32 GDI text-alignment and font-weight values, spelled out so the EA
// compiles on every MT4 build regardless of which TA_/FW_ enums it exposes.
#define SF_AL_LEFT     0
#define SF_AL_RIGHT    2
#define SF_AL_CENTER   6
#define SF_AL_TOP      0
#define SF_FW_NORMAL   400
#define SF_FW_SEMI     600
#define SF_FW_BLACK    900

string   PFX = "BKF_";   // object prefix - must differ from Signal Forge PRO

//--- signal state: the live breakout direction, read by the shared HUD
bool     gLongSignal = false, gShortSignal = false;

//--- symbol / cost cache
double   gPoint = 0.001;
int      gDigits = 3;
double   gTickValue = 0.0, gTickSize = 0.0;
double   gMinLot = 0.01, gMaxLot = 200.0, gLotStep = 0.01;
int      gStopLevel = 0, gFreezeLevel = 0;
double   gCostPointsRT = 70.0;   // commission expressed in price points, round turn
double   gSpreadSamples[64];
int      gSpreadIdx = 0, gSpreadCount = 0;
double   gMedianSpread = 0.0;

//--- runtime state
// The v2 risk layer (sessions, daily loss cap, equity kill-switch, cooldown,
// partial/BE bookkeeping, news blackouts) has been removed: the original
// strategy trades every valid signal. What remains is bookkeeping the
// dashboard reports on.
datetime gLastBar = 0;
datetime gLastTradeBar = 0;
datetime gDayStamp = 0;
double   gDayStartEquity = 0.0;
int      gDayTrades = 0;
double   gDayNet = 0.0;
int      gConsecLosses = 0;
string   gLastAction = "EA INITIALISED";
// Forward declaration: the trade gate translates its block reasons, and that
// code sits well above the UI string table where T() is defined. MQL4
// resolves identifiers strictly top-down, so it must be declared here.
string T(const string k);
// MQL4 resolves top-down: the breakout engine sits far above these, so they
// need forward declarations.
bool MayOpenNewTrade(string &why);

string   gBlockReason = "";

// LIVE look-and-feel state. MQL4 `input` variables cannot be written at
// runtime, so the language and theme buttons drive these copies instead.
// Seeded from the inputs in OnInit, then owned by the HUD buttons.
int      gLang  = 0;    // 0 = English, 1 = Arabic  (see ENUM_SF_LANG)
int      gTheme = 0;    // see ENUM_SF_THEME
int      gLastHistoryCount = -1;

//--- supertrend incremental cache

//--- HUD
// Two independent bitmap panels: the main HUD (top-left) and the standalone
// PERFORMANCE TRACKER (top-right). Every drawing primitive writes to gCv,
// the CURRENT target, so the same primitives serve both panels. Pointers are
// required because GetPointer() is only valid for new-allocated objects.
CCanvas *gHud = NULL;    // main HUD canvas
CCanvas *gTrk = NULL;    // tracker canvas
CCanvas *gCv  = NULL;    // current draw target
// Screen-space origin of the current target, so RegisterButton() can convert
// canvas-local coordinates into chart pixels for hit-testing.
int      gCvOx = 0, gCvOy = 0;
bool     gHudReady = false;
int      gHudW = 0, gHudH = 0;
bool     gTrkReady = false;
int      gTrkW = 0, gTrkH = 0;
uint     gLastHudPaint = 0;
bool     gHudCollapsed = false;
// ---- breakout engine state ---------------------------------------
// gBkState is what the BREAKOUT page renders and what the entry logic
// switches on. It only ever moves forward: IDLE -> READY -> ARMED ->
// (RETEST) -> TRADED, and resets to IDLE when a new range is built.
#define BK_IDLE    0   // no valid range yet
#define BK_READY   1   // range built, price inside it, waiting
#define BK_BROKEN  2   // body closed beyond the level
#define BK_RETEST  3   // waiting for the retest to hold
#define BK_TRADED  4   // this range already produced its trade(s)

bool     gShowRangeBox = true;  // live copy of ShowRangeBox (inputs are read-only)
int      gBkState      = BK_IDLE;
double   gBkHigh       = 0.0;   // range high
double   gBkLow        = 0.0;   // range low
double   gBkBuffer     = 0.0;   // buffer in PRICE, not points
double   gBkUpper      = 0.0;   // gBkHigh + buffer  (the actual trigger)
double   gBkLower      = 0.0;   // gBkLow  - buffer
bool     gBkValid      = false; // range passed the width sanity check
int      gBkDir        = 0;     // +1 broke up, -1 broke down, 0 none
double   gBkLevel      = 0.0;   // the level that was broken (for the retest)
int      gBkBreakBar   = 0;     // Bars value when the break happened
int      gBkTakenThis  = 0;     // trades already taken from this range
datetime gBkRangeStamp = 0;     // identifies the current range
double   gBkATR        = 0.0;   // ATR at the last evaluation
double   gBkATRAvg     = 0.0;   // its own moving average
double   gBkDistPct    = 0.0;   // how close price is to the trigger, 0..100
string   gBkGateFail   = "";    // which gate rejected the setup

// The range while it is still being COLLECTED. In SESSION mode the window
// (e.g. 00:00-07:00) is not usable for trading until it closes, but the user
// must still SEE it forming on the chart - otherwise the panel says
// "BUILDING RANGE" while the chart shows nothing at all.
int      gBkBars       = 0;     // bars the completed range spans
double   gBkSpan       = 0.0;   // ATR * sqrt(bars) = expected travel
double   gBkRatio      = 0.0;   // width / span, what the width gate tests
int      gBkFormBars   = 0;     // bars collected so far while forming
bool     gBkForming    = false; // inside the range window right now
double   gBkFormHigh   = 0.0;
double   gBkFormLow    = 0.0;
datetime gBkFormStart  = 0;

// Re-entry after a failed break. A break that closes back inside the range
// is not the end of the range - the level is still valid and very often gets
// hit again. gBkFailedBreaks counts those so the panel can show them, and
// MaxBreakoutsPerRange still caps how many TRADES one range may produce.
int      gBkFailedBreaks = 0;

// ---- RANGE HISTORY ------------------------------------------------
// Every completed range is archived here the moment it is superseded, so
// the chart can keep drawing it and the CSV can report it. Parallel arrays
// rather than a struct array because MQL4 struct arrays are awkward to
// resize and this is written once per range, read often.
#define BK_MAX_RANGES 512
datetime gRngStart[BK_MAX_RANGES];   // first bar of the range window
datetime gRngEnd  [BK_MAX_RANGES];   // when it stopped being the live range
double   gRngHigh [BK_MAX_RANGES];
double   gRngLow  [BK_MAX_RANGES];
double   gRngRatio[BK_MAX_RANGES];   // width / expected travel
int      gRngBars [BK_MAX_RANGES];
bool     gRngValid[BK_MAX_RANGES];   // did it pass the width gate
int      gRngTaken[BK_MAX_RANGES];   // trades it produced
int      gRngFails[BK_MAX_RANGES];   // failed breaks on it
int      gRngDir  [BK_MAX_RANGES];   // last break direction
int      gKnownMarkerHistory = -1;   // history count the markers were built for
int      gRngCount = 0;              // total ever archived (may exceed the ring)
int      gRngHead  = 0;              // next write slot

// The 8 entry gates, in the order the BREAKOUT page lists them.
#define BK_GATES 8
bool     gBkGate[BK_GATES];

int      gHudPage = 0;          // 0 = core, 1 = breakout
bool     gTrkCollapsed = false; // standalone tracker panel collapsed?
bool     gPaused = false;
int      gMouseX = -1, gMouseY = -1;   // chart-space cursor, for hover + click fallback
uint     gLastMouseMs = 0;             // when the pointer last moved/clicked
// A repaint rebuilds button objects. If that happens between mouse-DOWN and
// mouse-UP, MT4 discards the pending click - the button flashes and nothing
// fires. Freeze automatic repaints for a moment around any pointer activity.
bool RepaintLocked() { return (GetTickCount() - gLastMouseMs) < 600; }
// ONE physical press can be delivered TWICE: many builds send both
// CHARTEVENT_OBJECT_CLICK (named, id=1) and a plain CHARTEVENT_CLICK
// (coordinates, id=4) about 30 ms apart. Acting on both runs every action
// twice, which silently UNDOES it - pause then resume, draw on then off - so
// the HUD looks dead while actually working perfectly. Remember the last
// action and ignore a repeat of the same control inside this window.
uint     gLastActionMs = 0;            // when the last HUD action ran
string   gLastActionId = "";           // which control it was
#define  SF_CLICK_DEBOUNCE_MS 350
// True if this press is the echo of the one we just handled.
bool DuplicateClick(const string id)
  {
   if(id == "") return false;
   if(id == gLastActionId && (GetTickCount() - gLastActionMs) < SF_CLICK_DEBOUNCE_MS)
      return true;
   gLastActionId = id;
   gLastActionMs = GetTickCount();
   return false;
  }
int      gKnownResultHistory = -1;
bool     gCardsDirty = true;      // force a closed-card rebuild (chart moved)
// Cards are positioned in SCREEN pixels, so they must be re-laid-out whenever
// the viewport moves. CHARTEVENT_CHART_CHANGE is useless for this in the
// Strategy Tester (OnChartEvent is never called there), so instead we poll a
// cheap signature of the visible window and rebuild when it changes.
string   gViewSig = "";

//--- stats cache
int      gStatHistory = -1;
int      gStatTrades = 0, gStatWins = 0, gStatLosses = 0;
double   gStatNet = 0, gStatGP = 0, gStatGL = 0, gStatMaxDD = 0;
double   gStatBestTrade = 0, gStatWorstTrade = 0;
double   gStatCommission = 0;
double   gStatToday = 0, gStatWeek = 0, gStatMonth = 0;
// ACCOUNT-WIDE figures. The stats above are filtered to this EA's own magic
// number, which is what you want for judging the strategy - but it is NOT
// what the account actually did. A demo that was funded with 200 and now
// shows 157.79 is down 42.21 even if this EA's own trades are green, because
// manual trades, other EAs and other magics are all invisible to that filter.
// Reporting only the filtered figure made a losing account look profitable,
// so the tracker now carries both and shows the real one where it matters.
double   gAcctDeposits = 0;   // sum of balance/credit rows (the real funding)
double   gAcctNetAll   = 0;   // net of EVERY closed trade, any magic/symbol
double   gAcctStart    = 0;   // true opening balance of the account
bool     gAcctHasDep   = false;   // did we actually find a deposit record?
double   gEquityCurve[512];
int      gEquityPoints = 0;

//--- PERFORMANCE TRACKER: last N trading days, newest first
#define SF_TRACK_DAYS 6
#define SF_NO_LANE   (-1000000)   // FreeLaneY: no slot honours the separation
datetime gTrkDate[SF_TRACK_DAYS];
double   gTrkLots[SF_TRACK_DAYS];
double   gTrkProfit[SF_TRACK_DAYS];    // net, commission included
double   gTrkComm[SF_TRACK_DAYS];
double   gTrkGainPct[SF_TRACK_DAYS];
int      gTrkTrades[SF_TRACK_DAYS];
int      gTrkWins[SF_TRACK_DAYS];
double   gTrkStartBal = 0;             // reconstructed opening balance

//--- journal ring buffer for the HUD
string   gJournal[8];
int      gJournalCount = 0;

//==================================================================//
//                    T H E M E   E N G I N E                       //
//==================================================================//
uint TBg, TBg2, TPanel, TPanelHi, TBorder, TAccent, TAccent2;
uint TText, TTextDim, TBull, TBear, TFlat, TWarn, TGridC;
// Bevel pair: TLite is the top-left highlight, TDark the bottom-right shadow.
// Every raised surface is drawn with these so the HUD reads as physical.
uint TLite, TDark, TBullDeep, TBearDeep, TGreyDeep;

uint A(color c, uchar alpha) { return ColorToARGB(c, alpha); }

void LoadTheme()
  {
   switch(gTheme)
     {
      case SF_THEME_CARBON:
         TBg      = A(C'18,21,24',255); TBg2    = A(C'28,33,38',255);
         TPanel   = A(C'38,44,51',255); TPanelHi= A(C'52,60,69',255);
         TBorder  = A(C'92,104,119',255); TAccent = A(C'190,255,60',255);
         TAccent2 = A(C'255,200,40',255);
         TText    = A(C'245,250,255',255); TTextDim= A(C'165,178,194',255);
         TBull    = A(C'170,255,70',255); TBear   = A(C'255,80,80',255);
         TFlat    = A(C'255,215,60',255); TWarn   = A(C'255,150,40',255);
         TGridC   = A(C'70,80,92',255);
         TLite    = A(C'96,110,126',255); TDark = A(C'8,10,12',255);
         TBullDeep= A(C'58,110,20',255);  TBearDeep = A(C'120,26,26',255);
         TGreyDeep= A(C'78,86,96',255);
         break;
      case SF_THEME_SOLAR:
         TBg      = A(C'26,20,14',255); TBg2    = A(C'40,31,21',255);
         TPanel   = A(C'52,40,26',255); TPanelHi= A(C'72,56,34',255);
         TBorder  = A(C'132,102,58',255); TAccent = A(C'255,205,50',255);
         TAccent2 = A(C'255,130,30',255);
         TText    = A(C'255,248,235',255); TTextDim= A(C'205,182,150',255);
         TBull    = A(C'90,245,150',255); TBear   = A(C'255,95,80',255);
         TFlat    = A(C'255,215,80',255); TWarn   = A(C'255,160,35',255);
         TGridC   = A(C'102,80,50',255);
         TLite    = A(C'150,118,70',255); TDark = A(C'12,8,4',255);
         TBullDeep= A(C'20,110,62',255);  TBearDeep = A(C'128,32,24',255);
         TGreyDeep= A(C'96,80,60',255);
         break;
      default: // QUANTUM - high-chroma neon on deep navy
         TBg      = A(C'12,18,34',255); TBg2    = A(C'20,30,54',255);
         TPanel   = A(C'28,40,72',255); TPanelHi= A(C'40,56,98',255);
         TBorder  = A(C'86,116,190',255);TAccent = A(C'0,245,255',255);
         TAccent2 = A(C'178,110,255',255);
         TText    = A(C'240,248,255',255); TTextDim= A(C'158,180,220',255);
         TBull    = A(C'0,255,170',255); TBear   = A(C'255,60,110',255);
         TFlat    = A(C'255,215,70',255); TWarn   = A(C'255,160,50',255);
         TGridC   = A(C'58,80,132',255);
         TLite    = A(C'110,146,225',255); TDark = A(C'5,8,16',255);
         TBullDeep= A(C'0,104,74',255);   TBearDeep = A(C'128,20,50',255);
         TGreyDeep= A(C'86,92,104',255);
         break;
     }
  }

int SC(int v) { return (int)MathRound(v * MathMax(80, MathMin(130, HudScalePercent)) / 100.0); }

//==================================================================//
//                 S Y M B O L   +   C O S T   M O D E L            //
//==================================================================//
void CacheSymbolSpec()
  {
   gPoint      = MarketInfo(Symbol(), MODE_POINT);
   if(gPoint <= 0) gPoint = Point;
   gDigits     = (int)MarketInfo(Symbol(), MODE_DIGITS);
   gTickValue  = MarketInfo(Symbol(), MODE_TICKVALUE);
   gTickSize   = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(gTickSize <= 0) gTickSize = gPoint;
   gMinLot     = MarketInfo(Symbol(), MODE_MINLOT);
   gMaxLot     = MarketInfo(Symbol(), MODE_MAXLOT);
   gLotStep    = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(gMinLot  <= 0) gMinLot  = 0.01;
   if(gMaxLot  <= 0) gMaxLot  = 200.0;
   if(gLotStep <= 0) gLotStep = 0.01;
   gStopLevel  = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   gFreezeLevel= (int)MarketInfo(Symbol(), MODE_FREEZELEVEL);
  }

// Money value of one point for a given lot size.
double PointValue(double lots)
  {
   if(gTickSize <= 0 || gTickValue <= 0) return lots * 100.0 * gPoint; // gold fallback: 100oz
   return lots * gTickValue * (gPoint / gTickSize);
  }

// Round-turn commission in account currency for the given lots.
// The whole point of this block: express commission as PRICE DISTANCE.
// Exness Raw gold = 3.50/lot/side = 0.07 round turn per 0.01 lot.
// One point (0.001) on 0.01 lot is worth 0.001 USD, so 0.07 USD == 70 points.
// That 70-point tax is lot-size independent, which is why it can be folded
// straight into the stop, the target and the break-even level.
void RecalcCostPoints()
  {
   double lots = 0.01;
   double pv   = PointValue(lots);          // USD per point at 0.01 lot
   if(pv <= 0.0) { gCostPointsRT = 70.0; return; }
   gCostPointsRT = CommissionPer001LotRT / pv;
  }

double SpreadPoints()
  {
   double sp = (Ask - Bid) / gPoint;
   if(sp < 0) sp = 0;
   return sp;
  }

void PushSpreadSample()
  {
   double sp = SpreadPoints();
   if(sp <= 0) return;
   gSpreadSamples[gSpreadIdx] = sp;
   gSpreadIdx = (gSpreadIdx + 1) % 64;
   if(gSpreadCount < 64) gSpreadCount++;
   double tmp[64];
   ArrayInitialize(tmp, 0.0);
   for(int i = 0; i < gSpreadCount; i++) tmp[i] = gSpreadSamples[i];
   for(int a = 0; a < gSpreadCount - 1; a++)
      for(int b = a + 1; b < gSpreadCount; b++)
         if(tmp[b] < tmp[a]) { double t = tmp[a]; tmp[a] = tmp[b]; tmp[b] = t; }
   gMedianSpread = tmp[gSpreadCount / 2];
  }

// Commission actually charged for a trade. Brokers (and the Strategy Tester
// when no commission is configured in the symbol settings) frequently report
// OrderCommission() == 0. Falling back to the configured Raw Spread rate keeps
// the cost story honest instead of printing a flattering "FEE -0.00".
// `estimated` tells the caller the number was derived, not reported, so the
// card can mark it with a ~ rather than pass an estimate off as fact.
double TradeCommissionUSD(double lots, double reported, bool &estimated)
  {
   estimated = false;
   double c = MathAbs(reported);
   if(c > 0.0) return c;
   if(lots <= 0.0) return 0.0;
   estimated = true;
   return CommissionPer001LotRT * (lots / 0.01);
  }

// Net result of the CURRENTLY SELECTED order, using the same commission
// estimate as the cards so the tracker, the equity curve and the cards can
// never disagree with each other.
double SelectedNetUSD()
  {
   bool   est = false;
   double cm  = TradeCommissionUSD(OrderLots(), OrderCommission(), est);
   double gr  = OrderProfit() + OrderSwap();
   return est ? (gr - cm) : (gr + OrderCommission());
  }

// Full cost of a round turn, expressed in points: spread + commission.
double TotalCostPoints()
  {
   return SpreadPoints() + gCostPointsRT;
  }

//==================================================================//
//                    U T I L I T I E S                             //
//==================================================================//
void Journal(string msg)
  {
   gLastAction = msg;
   for(int i = 7; i > 0; i--) gJournal[i] = gJournal[i - 1];
   gJournal[0] = TimeToString(TimeCurrent(), TIME_MINUTES) + "  " + msg;
   if(gJournalCount < 8) gJournalCount++;
   if(VerboseJournal) Print("[BK-FORGE] ", msg);
  }

string Fmt(double v, int d) { return DoubleToString(v, d); }
string Signed(double v, int d) { return (v >= 0 ? "+" : "") + DoubleToString(v, d); }

// v1 sized risk off the balance, with an optional fixed reference balance so
// a small live account can be tuned as if it were larger (or smaller).
// Money value of one point per 1.00 lot - used by the cost readouts.
double PointValuePerLot()
  {
   double pv = PointValue(1.0);
   return (pv > 0) ? pv : 100.0 * gPoint;
  }

datetime DayStart(datetime t)
  {
   MqlDateTime d; TimeToStruct(t, d);
   d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
  }

datetime MonthStart(datetime t)
  {
   MqlDateTime d; TimeToStruct(t, d);
   d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
  }

//==================================================================//
//              O R I G I N A L   v1   S T R A T E G Y              //
//==================================================================//
// This block is the trading engine of "Signal Forge XAUUSD M5 EA"
// restored verbatim in behaviour: the same 11 filters, the same
// AND/OR combination, the same ATR/points stop and target, the same
// point-based trailing stop and the same one-position flip logic.
// The v2 risk layer (sessions, daily loss caps, equity kill-switch,
// cooldowns, cost-aware targets, adaptive spread) has been removed
// at the user's request.
//==================================================================//

//==================================================================//
//              P O S I T I O N   /   O R D E R S                   //
//==================================================================//
double NormalizeLots(double lots)
  {
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(MathFloor(lots / step + 0.0000001) * step, 2);
  }

// What one lot loses if `dist` (in PRICE) goes against it. Derived from the
// broker's own tick figures so it is correct for gold, FX or indices.
double MoneyPerLot(double dist)
  {
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0)  tickSize  = Point;
   if(tickValue <= 0) tickValue = 1.0;
   return (dist / tickSize) * tickValue;
  }

// The risk budget for one trade, in account currency.
double RiskBudgetUSD()
  {
   double base = (RiskReferenceBalance > 0) ? RiskReferenceBalance
                                            : AccountEquity();
   if(base <= 0) base = AccountBalance();
   double usd = base * MathMax(0.0, RiskPerTradePercent) / 100.0;
   if(MaxRiskPerTradeUSD > 0) usd = MathMin(usd, MaxRiskPerTradeUSD);
   return usd;
  }

// THE FIX. The lot is derived from the stop, never the other way round, so
// a wide structural stop produces a small position instead of a large loss.
// Returns 0 when even the minimum lot exceeds the budget, which means the
// trade must be skipped rather than taken at a size the account cannot pay.
double LotForRisk(double slDistance, double &riskUSD, string &why)
  {
   why = ""; riskUSD = 0;
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   if(MaxLots > 0) maxLot = MathMin(maxLot, MaxLots);

   if(!UseRiskSizing)
     {
      double fixed = NormalizeLots(MathMin(FixedLots, maxLot));
      riskUSD = MoneyPerLot(slDistance) * fixed;
      return fixed;
     }
   if(slDistance <= 0) { why = T("NO STOP"); return 0; }

   double perLot = MoneyPerLot(slDistance);
   if(perLot <= 0) { why = T("NO TICK VALUE"); return 0; }

   double budget = RiskBudgetUSD();
   if(budget <= 0) { why = T("NO RISK BUDGET"); return 0; }

   double raw = budget / perLot;               // lots the budget can afford
   double lots = NormalizeLots(MathMin(raw, maxLot));

   // NormalizeLots() floors up to minLot, so an affordable-looking lot can
   // still blow the budget. Check the REAL number, not the requested one.
   riskUSD = perLot * lots;
   if(lots < minLot || riskUSD > budget * 1.02)
     {
      if(SkipIfRiskTooHigh)
        {
         why = T("RISK TOO HIGH");
         return 0;
        }
      lots    = NormalizeLots(minLot);
      riskUSD = perLot * lots;
     }
   return lots;
  }

int CountOwnPositions(int &type, int &ticket)
  {
   type = -1; ticket = -1;
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(n == 0) { type = OrderType(); ticket = OrderTicket(); }
      n++;
     }
   return n;
  }

bool CloseAllOwn(string reason)
  {
   bool allClosed = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      RefreshRates();
      bool ok = false;
      if(OrderType() == OP_BUY)  ok = OrderClose(OrderTicket(), OrderLots(), Bid, SlippagePoints, C'255,80,100');
      if(OrderType() == OP_SELL) ok = OrderClose(OrderTicket(), OrderLots(), Ask, SlippagePoints, C'0,240,180');
      if(!ok) { Print("Breakout Forge close failed: ", GetLastError()); allClosed = false; }
     }
   if(allClosed) { gLastAction = "CLOSED: " + reason; Journal(gLastAction); }
   return allClosed;
  }

bool OpenPosition(int type)
  {
   RefreshRates();
   double spread = (Ask - Bid) / Point;
   if(MaximumSpreadPoints > 0 && spread > MaximumSpreadPoints)
     {
      gLastAction = "BLOCKED: SPREAD " + DoubleToString(spread, 0) + " PTS";
      gBlockReason = T("SPREAD") + " " + DoubleToString(spread, 0) + T("p");
      return false;
     }

   double entry = (type == OP_BUY) ? Ask : Bid;
   double atr   = iATR(NULL, 0, MathMax(1, ATRLength), 1);
   double atrSLDistance = atr * MathMax(0.1, StopLossATR);
   // The stop is decided FIRST and the lot is derived from it further down.
   // Doing it the other way round is what allowed a 95 USD structural stop
   // to be taken at a constant 0.10 lots = 956 USD of risk.
   double slDistance = atrSLDistance;
   double tpDistance = (TakeProfitMode == TP_By_Points)
                       ? MathMax(Point, TakeProfitPoints * Point)
                       : atr * MathMax(0.1, TakeProfitATR);

   //--- BREAKOUT-SPECIFIC STOP AND TARGET ---------------------------
   // The natural stop for a range break is the OTHER side of the range:
   // if price goes back through the whole box, the break has failed and
   // there is nothing left to be right about. A pure ATR stop ignores
   // where the structure actually is.
   if(StopByRangeOpposite && gBkValid && gBkHigh > gBkLow)
     {
      double pad  = MathMax(0.0, StopRangePadATR) * atr;
      double structural = (type == OP_BUY) ? (entry - (gBkLow  - pad))
                                           : ((gBkHigh + pad) - entry);
      // Never let the structural stop be sillier than the ATR one in
      // either direction: clamp it into a sane band around ATR.
      if(structural > 0)
         slDistance = MathMax(atrSLDistance * 0.5,
                              MathMin(structural, atrSLDistance * MathMax(1.0, StopClampATRMult)));
     }

   // Measured move: a range that was N wide often travels N again.
   if(TargetMode == BK_TP_MEASURED && gBkValid && gBkHigh > gBkLow)
      tpDistance = (gBkHigh - gBkLow) * MathMax(0.1, MeasuredMoveMult);

   //--- reject a stop that is simply too far away --------------------
   // The clamp above scales with ATR, so on a volatile day it still permits
   // an enormous stop. This is an absolute structural veto.
   if(MaxStopATRMult > 0 && atr > 0 && slDistance > atr * MaxStopATRMult)
     {
      gLastAction  = "BLOCKED: STOP " + DoubleToString(slDistance / Point, 0) + " PTS TOO WIDE";
      gBlockReason = T("STOP TOO WIDE");
      Journal(gLastAction);
      return false;
     }

   double minimum = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 2) * Point;
   slDistance = MathMax(slDistance, minimum);

   //--- SIZE THE POSITION FROM THE STOP ------------------------------
   // Everything above decided WHERE the stop goes. Only now is it known
   // how many lots that stop can be afforded at.
   double riskUSD = 0; string riskWhy = "";
   double lots = LotForRisk(slDistance, riskUSD, riskWhy);
   if(lots <= 0)
     {
      gLastAction  = "BLOCKED: " + riskWhy + " (stop " +
                     DoubleToString(slDistance / Point, 0) + " pts = $" +
                     DoubleToString(MoneyPerLot(slDistance) * MarketInfo(Symbol(), MODE_MINLOT), 2) +
                     " at min lot, budget $" + DoubleToString(RiskBudgetUSD(), 2) + ")";
      gBlockReason = riskWhy;
      Journal(gLastAction);
      return false;
     }

   //--- cost floor ---------------------------------------------------
   // Commission plus spread is a real hurdle on a 200 USD account. A
   // target that does not clear it by a healthy multiple is a losing
   // trade wearing a winner's clothes.
   double costPoints = SpreadPoints() + gCostPointsRT;
   double tpFloor    = costPoints * MathMax(1.0, MinTargetCostMult) * Point;
   if(tpDistance < tpFloor) tpDistance = tpFloor;

   //--- reward/risk floor --------------------------------------------
   // A 94% win rate still lost the account because every target was a
   // fraction of its stop. The target must beat the stop by this ratio.
   if(MinRewardRiskRatio > 0 && slDistance > 0)
     {
      double rrFloor = slDistance * MinRewardRiskRatio;
      if(tpDistance < rrFloor) tpDistance = rrFloor;
     }

   tpDistance = MathMax(tpDistance, minimum);
   double sl = (type == OP_BUY) ? entry - slDistance : entry + slDistance;
   double tp = (type == OP_BUY) ? entry + tpDistance : entry - tpDistance;
   sl = NormalizeDouble(sl, Digits);
   tp = NormalizeDouble(tp, Digits);

   string cmt  = TradeComment + ((type == OP_BUY) ? " BUY" : " SELL");
   color  arrw = (type == OP_BUY) ? C'0,255,170' : C'255,64,96';
   int ticket = OrderSend(Symbol(), type, lots, entry, SlippagePoints, sl, tp, cmt, MagicNumber, 0, arrw);
   if(ticket < 0 && GetLastError() == 130)
     {
      // ECN: send naked, then attach the stops
      RefreshRates();
      entry = (type == OP_BUY) ? Ask : Bid;
      ticket = OrderSend(Symbol(), type, lots, entry, SlippagePoints, 0, 0, cmt, MagicNumber, 0, arrw);
      if(ticket > 0 && OrderSelect(ticket, SELECT_BY_TICKET))
        {
         sl = (type == OP_BUY) ? entry - slDistance : entry + slDistance;
         tp = (type == OP_BUY) ? entry + tpDistance : entry - tpDistance;
         if(!OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, Digits),
                         NormalizeDouble(tp, Digits), 0, arrw))
            Print("Breakout Forge ECN SL/TP modify failed: ", GetLastError());
        }
     }
   if(ticket < 0)
     {
      int err = GetLastError();
      gLastAction = "ORDER ERROR " + IntegerToString(err);
      Print(gLastAction);
      Journal(gLastAction);
      return false;
     }
   gLastTradeBar = Time[0];
   gDayTrades++;
   gLastAction = (type == OP_BUY) ? "BUY OPENED" : "SELL OPENED";
   Journal(gLastAction + " " + DoubleToString(lots, 2) + " @ " + DoubleToString(entry, Digits));

   if(AlertOnEntry)
      Alert("Breakout Forge: ", (type == OP_BUY ? "BUY " : "SELL "), Symbol(), " ", lots);
   if(PushOnEntry)
      SendNotification("BK-FORGE " + (type == OP_BUY ? "BUY " : "SELL ") + Symbol() +
                       " " + DoubleToString(lots, 2) + " @ " + DoubleToString(entry, Digits));
   gCardsDirty = true;
   return true;
  }

// Gate names, in the order the checklist draws them. Kept next to the
// gate evaluation so the two can never drift apart.
string BkGateName(int g)
  {
   if(g == 0) return "RANGE OK";
   if(g == 1) return "VOLATILITY";
   if(g == 2) return "SPREAD";
   if(g == 3) return "SESSION";
   if(g == 4) return "RANGE WIDTH";
   if(g == 5) return "BODY CLOSE";
   if(g == 6) return "NO ROLLOVER";
   return "DAILY LIMIT";
  }

// One place that turns the state machine into words, so the CORE panel and
// the BREAKOUT page can never describe the same state differently.
string BkStateText()
  {
   if(gBkState == BK_TRADED)  return T("TRADE TAKEN");
   if(gBkState == BK_RETEST)  return T("WAITING RETEST");
   if(gBkState == BK_BROKEN)  return T("BROKEN");
   if(gBkValid)               return T("WAITING FOR BREAK");
   if(gBkForming)             return T("BUILDING RANGE");
   return T("NO VALID RANGE");
  }

int BkGatesPassed()
  {
   int n = 0;
   for(int i = 0; i < BK_GATES; i++) if(gBkGate[i]) n++;
   return n;
  }

//+------------------------------------------------------------------+
//| SESSION / RISK HELPERS                                           |
//| Exness server time is GMT+0 year round, so "hour" here is UTC on |
//| that broker. Both windows may wrap midnight.                     |
//+------------------------------------------------------------------+
bool HourInWindowRaw(int h, int startH, int endH)
  {
   if(startH == endH) return true;
   if(startH < endH)  return (h >= startH && h < endH);
   return (h >= startH || h < endH);
  }

bool SessionOpenNow()
  {
   if(!UseSessionFilter) return true;
   return HourInWindowRaw(TimeHour(TimeCurrent()), TradeStartHour, TradeEndHour);
  }

bool InRolloverBlackout()
  {
   if(!BlockRollover) return false;
   return HourInWindowRaw(TimeHour(TimeCurrent()), RolloverStartHour, RolloverEndHour);
  }

// Daily limiters. gDayNet is maintained by TrackClosedTrades(), so this
// counts realised loss only - a losing open position does not lock the EA
// out, the stop loss handles that.
bool DailyLimitsOK(string &why)
  {
   why = "";
   if(MaxTradesPerDay > 0 && gDayTrades >= MaxTradesPerDay)
     { why = T("MAX TRADES"); return false; }
   if(MaxDailyLossUSD > 0 && gDayNet <= -MathAbs(MaxDailyLossUSD))
     { why = T("DAILY LOSS"); return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| BREAKOUT ENGINE                                                  |
//| Build a range, decide whether a bar genuinely broke it, and hold |
//| the state the HUD renders. Everything here is deliberately       |
//| conservative: when in doubt, reject.                             |
//+------------------------------------------------------------------+

// Buffer in PRICE. Points are converted with Point so a 3-digit gold feed
// and a 5-digit FX feed both behave.
double BreakoutBuffer(double atr)
  {
   if(BufferMode == BK_BUF_FIXED) return MathMax(0.0, BufferFixedPoints) * Point;
   return MathMax(0.0, BufferATRMult) * atr;
  }

// Build the range. Returns false when there is nothing usable yet, which
// keeps the panel honest instead of drawing a stale box.
bool BuildRange(double &hi, double &lo, datetime &stamp, int &bars)
  {
   hi = 0; lo = 0; stamp = 0; bars = 0;

   if(RangeMode == BK_RANGE_DONCHIAN)
     {
      gBkForming = false;              // a rolling channel is always complete
      int n = MathMax(2, DonchianBars);
      if(Bars < n + 2) return false;
      // shift 1: the last CLOSED bar. Never include the forming bar or the
      // range would move under us on every tick.
      int hb = iHighest(NULL, 0, MODE_HIGH, n, 1);
      int lb = iLowest (NULL, 0, MODE_LOW,  n, 1);
      if(hb < 0 || lb < 0) return false;
      hi = High[hb]; lo = Low[lb];
      stamp = Time[1];                 // rolls every bar, by design
      bars  = n;
      return (hi > lo);
     }

   // ---- SESSION mode ------------------------------------------------
   // Walk back over closed bars collecting the high/low of the most recent
   // completed occurrence of the window.
   datetime now = TimeCurrent();
   int curH = TimeHour(now);
   // If we are still inside the window the range is not finished yet - but
   // record what it looks like SO FAR so the chart can draw it forming.
   if(HourInWindowRaw(curH, RangeStartHour, RangeEndHour))
     {
      double fh = -1, fl = -1; datetime fs = 0; int fc = 0;
      for(int k = 0; k < Bars && k < 2000; k++)
        {
         if(!HourInWindowRaw(TimeHour(Time[k]), RangeStartHour, RangeEndHour))
            break;                       // walked out of the live window
         if(fh < 0 || High[k] > fh) fh = High[k];
         if(fl < 0 || Low[k]  < fl) fl = Low[k];
         fs = Time[k];
         fc++;
        }
      gBkFormBars = fc;
      if(fh > 0 && fl > 0 && fh > fl)
        {
         gBkForming   = true;
         gBkFormHigh  = fh;
         gBkFormLow   = fl;
         gBkFormStart = fs;
        }
      return false;
     }
   gBkForming = false;

   double h = -1, l = -1;
   datetime st = 0;
   int scanned = 0, cnt = 0;
   for(int i = 1; i < Bars && scanned < 2000; i++, scanned++)
     {
      int bh = TimeHour(Time[i]);
      if(HourInWindowRaw(bh, RangeStartHour, RangeEndHour))
        {
         if(h < 0 || High[i] > h) h = High[i];
         if(l < 0 || Low[i]  < l) l = Low[i];
         st = Time[i];
         cnt++;
        }
      else if(h >= 0)
         break;      // we walked out of the most recent window - done
     }
   if(h < 0 || l < 0 || h <= l) return false;
   hi = h; lo = l; stamp = st; bars = MathMax(1, cnt);
   return true;
  }

// How many archived ranges are actually retrievable right now.
int ArchivedRanges()
  {
   return (gRngCount < BK_MAX_RANGES) ? gRngCount : BK_MAX_RANGES;
  }

// Map "n-th most recent archived range" (0 = newest) onto its ring slot.
int ArchivedSlot(int nth)
  {
   int have = ArchivedRanges();
   if(nth < 0 || nth >= have) return -1;
   int i = gRngHead - 1 - nth;
   while(i < 0) i += BK_MAX_RANGES;
   return i;
  }

// Archive the range that is about to be replaced, so the chart and the CSV
// can still show it. Called from UpdateRange() at the moment the stamp
// changes - that is the only place a range stops being the live one.
void ArchiveCurrentRange()
  {
   if(gBkRangeStamp <= 0 || gBkHigh <= gBkLow) return;   // nothing built yet

   // ---- DONCHIAN GUARD -----------------------------------------------
   // In DONCHIAN mode BuildRange() stamps the range with Time[1], so the
   // "range" is superseded on EVERY closed bar - 288 of them a day on M5.
   // Archiving each one would overflow the ring in under two days and bury
   // the chart in near-identical boxes. Two filters keep it meaningful:
   //   1. if the geometry is unchanged, just extend the existing entry;
   //   2. a rolling channel that produced neither a trade nor a failed
   //      break carries no analytical signal, so it is not kept.
   // SESSION mode is unaffected: its stamp only changes once per session,
   // and every session range is archived whether it traded or not.
   int last = (gRngCount > 0) ? ArchivedSlot(0) : -1;
   if(last >= 0 &&
      MathAbs(gRngHigh[last] - gBkHigh) < gPoint &&
      MathAbs(gRngLow [last] - gBkLow)  < gPoint)
     {
      // Same box as last time - extend it and refresh its stats in place.
      gRngEnd  [last] = Time[0];
      gRngRatio[last] = gBkRatio;
      gRngBars [last] = gBkBars;
      gRngValid[last] = gBkValid;
      gRngTaken[last] = MathMax(gRngTaken[last], gBkTakenThis);
      gRngFails[last] = MathMax(gRngFails[last], gBkFailedBreaks);
      if(gBkDir != 0) gRngDir[last] = gBkDir;
      return;
     }
   if(RangeMode == BK_RANGE_DONCHIAN && gBkTakenThis == 0 && gBkFailedBreaks == 0)
      return;   // uneventful rolling channel - nothing to learn from it

   int i = gRngHead;
   gRngStart[i] = gBkRangeStamp;
   gRngEnd  [i] = Time[0];
   gRngHigh [i] = gBkHigh;
   gRngLow  [i] = gBkLow;
   gRngRatio[i] = gBkRatio;
   gRngBars [i] = gBkBars;
   gRngValid[i] = gBkValid;
   gRngTaken[i] = gBkTakenThis;
   gRngFails[i] = gBkFailedBreaks;
   gRngDir  [i] = gBkDir;

   gRngHead = (gRngHead + 1) % BK_MAX_RANGES;
   gRngCount++;
  }

// Refresh the range, the buffer and the derived trigger levels.
void UpdateRange()
  {
   double atr = iATR(NULL, 0, MathMax(1, ATRLength), 1);
   if(atr <= 0) { gBkValid = false; return; }
   gBkATR = atr;

   double sum = 0; int n = MathMax(1, VolATRAvgPeriod), got = 0;
   for(int i = 1; i <= n; i++)
     {
      double a = iATR(NULL, 0, MathMax(1, ATRLength), i);
      if(a > 0) { sum += a; got++; }
     }
   gBkATRAvg = (got > 0) ? sum / got : atr;

   double hi = 0, lo = 0; datetime stamp = 0; int rbars = 0;
   if(!BuildRange(hi, lo, stamp, rbars)) { gBkValid = false; return; }
   gBkBars = MathMax(1, rbars);

   // A brand new range wipes the per-range trade counter and the state.
   if(stamp != gBkRangeStamp)
     {
      // ...but first preserve the one being replaced, for post-analysis.
      if(KeepRangeHistory) ArchiveCurrentRange();
      gBkRangeStamp   = stamp;
      gBkTakenThis    = 0;
      gBkFailedBreaks = 0;
      gBkState        = BK_READY;
      gBkDir          = 0;
      gBkLevel        = 0;
     }

   gBkHigh   = hi;
   gBkLow    = lo;
   gBkBuffer = BreakoutBuffer(atr);
   gBkUpper  = hi + gBkBuffer;
   gBkLower  = lo - gBkBuffer;

   // ---- WIDTH SANITY -------------------------------------------------
   // The range must be compared against what the market could PLAUSIBLY
   // travel over the bars the range actually spans - not against one M5
   // bar's ATR. A 7-hour Asian session is 84 M5 bars; a healthy gold Asian
   // range is 9-18 USD while 6x M5 ATR is only about 3-7 USD, so the old
   // "width <= MaxRangeATRMult * atr" test rejected virtually every real
   // session range and the panel sat on NO VALID RANGE forever.
   //
   // Over N bars a random walk covers roughly ATR * sqrt(N), so that is the
   // yardstick. The multipliers now mean "fraction of the expected envelope"
   // and behave identically in SESSION and DONCHIAN mode.
   double width = hi - lo;
   gBkSpan  = atr * MathSqrt((double)gBkBars);
   gBkRatio = (gBkSpan > 0) ? width / gBkSpan : 0.0;
   gBkValid = (gBkRatio >= MinRangeATRMult && gBkRatio <= MaxRangeATRMult);
   // ...plus an absolute floor, because a proportionate range can still be
   // too small in dollars to pay for spread + commission.
   if(gBkValid && MinRangePoints > 0 && (width / gPoint) < MinRangePoints)
      gBkValid = false;

   // Distance-to-break meter: 100% means price is sitting on the trigger.
   double px = (Bid + Ask) / 2.0;
   double up = gBkUpper - px, dn = px - gBkLower;
   double nearest = MathMin(MathMax(up, 0), MathMax(dn, 0));
   double span = MathMax(gBkUpper - gBkLower, Point);
   gBkDistPct = 100.0 * (1.0 - MathMin(1.0, nearest / (span / 2.0)));
   if(gBkDistPct < 0)   gBkDistPct = 0;
   if(gBkDistPct > 100) gBkDistPct = 100;
  }

// Did the bar at `shift` genuinely break the range? Returns +1/-1/0.
// RequireBodyClose is the difference between trading breakouts and
// donating spread to every wick that tags the level.
int BreakDirection(int shift)
  {
   if(!gBkValid) return 0;
   double c = Close[shift];
   double o = Open[shift];
   double h = High[shift];
   double l = Low[shift];

   bool upBreak, dnBreak;
   if(RequireBodyClose)
     {
      // body must close beyond, AND the bar must actually be in that
      // direction - a bearish bar closing above the level is not a
      // bullish break, it is a failed push.
      upBreak = (c > gBkUpper && c > o);
      dnBreak = (c < gBkLower && c < o);
     }
   else
     {
      upBreak = (h > gBkUpper);
      dnBreak = (l < gBkLower);
     }

   if(upBreak && dnBreak) return 0;   // outside-bar chaos, skip
   if(upBreak) return  1;
   if(dnBreak) return -1;
   return 0;
  }

// The eight gates. Fills gBkGate[] for the HUD and returns the overall
// verdict, so the panel and the trade decision can never disagree.
bool BreakoutGates(int dir, string &why)
  {
   for(int i = 0; i < BK_GATES; i++) gBkGate[i] = false;
   why = "";

   // 1 - a valid, sane range exists
   gBkGate[0] = gBkValid;

   // 2 - volatility is expanding
   gBkGate[1] = (!UseVolatilityGate) ||
                (gBkATRAvg > 0 && gBkATR > VolATRMinRatio * gBkATRAvg);

   // 3 - spread
   gBkGate[2] = (MaximumSpreadPoints <= 0 || SpreadPoints() <= MaximumSpreadPoints);

   // 4 - session window for TRADING (not the range window)
   gBkGate[3] = SessionOpenNow();

   // 5 - range width already folded into gBkValid, re-stated for the panel
   gBkGate[4] = gBkValid;

   // 6 - the break itself
   gBkGate[5] = (dir != 0);

   // 7 - rollover blackout
   gBkGate[6] = !InRolloverBlackout();

   // 8 - per-range cap and the daily limiters
   string dummy = "";
   gBkGate[7] = (gBkTakenThis < MathMax(1, MaxBreakoutsPerRange)) &&
                DailyLimitsOK(dummy) && MayOpenNewTrade(dummy);

   for(int g = 0; g < BK_GATES; g++)
      if(!gBkGate[g])
        {
         if(g == 0 || g == 4) why = T("RANGE");
         else if(g == 1) why = T("VOLATILITY");
         else if(g == 2) why = T("SPREAD");
         else if(g == 3) why = T("SESSION");
         else if(g == 5) why = T("NO BREAK");
         else if(g == 6) why = T("ROLLOVER");
         else            why = (dummy != "") ? dummy : T("LIMIT");
         return false;
        }
   return true;
  }

// Has the broken level been retested and held? Called only while the state
// is BK_RETEST. "Held" means the bar came back to touch the level within a
// tolerance and then closed back on the breakout side - a close through the
// level in the wrong direction kills the setup instead of arming it.
int RetestResult(int shift)
  {
   if(gBkDir == 0 || gBkLevel <= 0) return -1;     // -1 = abandon
   double tol = MathMax(1.0, RetestTolerancePoints) * Point;
   double c = Close[shift], h = High[shift], l = Low[shift];

   if(gBkDir > 0)
     {
      if(c < gBkLevel - tol) return -1;            // fell back inside, dead
      if(l <= gBkLevel + tol && c > gBkLevel) return 1;  // touched and held
     }
   else
     {
      if(c > gBkLevel + tol) return -1;
      if(h >= gBkLevel - tol && c < gBkLevel) return 1;
     }
   return 0;                                        // still waiting
  }

// ---- RE-ENTRY AFTER A BREAK -------------------------------------------
// A break that has already been traded does NOT retire the range. The level
// stays live and price keeps interacting with it. Two distinct things can
// happen on a later closed bar:
//
//   CASE A - the bar comes back inside and CLOSES INSIDE the range.
//            The break failed. The range itself is still perfectly good, so
//            the engine re-arms and the NEXT genuine break trades again.
//
//   CASE B - the bar dips back inside intrabar but is REJECTED and CLOSES
//            BACK OUTSIDE, leaving a wick through the level. The level held
//            under pressure, which is the strongest continuation tell there
//            is: re-enter immediately in the same direction.
//
// Returns +1 / -1 for a CASE B re-entry, BK_REARM for CASE A, 0 otherwise.
#define BK_REARM (-2)
int ReEntryResult(int shift)
  {
   if(!AllowReEntry || gBkDir == 0) return 0;

   double c = Close[shift], o = Open[shift];
   double h = High[shift],  l = Low[shift];
   // The trigger (range edge + buffer) is what has to be rejected...
   double lvl   = (gBkDir > 0) ? gBkUpper : gBkLower;
   // ...but "back inside" means back inside the RAW range, not the buffer
   // zone, otherwise every bar that merely drifts within the buffer would
   // count as a failed break.
   double inner = (gBkDir > 0) ? gBkHigh  : gBkLow;

   if(gBkDir > 0)
     {
      if(c < inner) return BK_REARM;                  // CASE A
      if(l <= lvl && c > lvl && c > o) return 1;      // CASE B
     }
   else
     {
      if(c > inner) return BK_REARM;                  // CASE A
      if(h >= lvl && c < lvl && c < o) return -1;     // CASE B
     }
   return 0;                                          // nothing yet
  }

// Optional confluence with the inherited 11 filters.
void ManageTrailing()
  {
   if(!EnableTrailingStop) return;
   double start    = MathMax(0, TrailingStartPoints) * Point;
   double distance = MathMax(1, TrailingDistancePoints) * Point;
   double step     = MathMax(1, TrailingStepPoints) * Point;
   double minStop  = (MarketInfo(Symbol(), MODE_STOPLEVEL) + 1) * Point;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      RefreshRates();
      if(OrderType() == OP_BUY && Bid - OrderOpenPrice() >= start)
        {
         double next = NormalizeDouble(Bid - MathMax(distance, minStop), Digits);
         if((OrderStopLoss() == 0 || next - OrderStopLoss() >= step) && next > OrderOpenPrice())
            if(!OrderModify(OrderTicket(), OrderOpenPrice(), next, OrderTakeProfit(), 0, C'41,150,255'))
               Print("Trailing BUY error: ", GetLastError());
        }
      if(OrderType() == OP_SELL && OrderOpenPrice() - Ask >= start)
        {
         double next = NormalizeDouble(Ask + MathMax(distance, minStop), Digits);
         if((OrderStopLoss() == 0 || OrderStopLoss() - next >= step) && next < OrderOpenPrice())
            if(!OrderModify(OrderTicket(), OrderOpenPrice(), next, OrderTakeProfit(), 0, C'41,150,255'))
               Print("Trailing SELL error: ", GetLastError());
        }
     }
  }

// True break-even price including the round-turn commission, used by the
// HUD's break-even line. Purely informational - it never moves a stop.
double BreakEvenPrice(int type, double entry, double lots)
  {
   double costPts = (lots > 0) ? (CommissionPer001LotRT * (lots / 0.01)) / (PointValuePerLot() * lots) : 0;
   if(costPts <= 0) return entry;
   return (type == OP_BUY) ? entry + costPts * gPoint : entry - costPts * gPoint;
  }
//==================================================================//
//              D A Y   +   A T R   R E A D O U T S                 //
//==================================================================//
// These feed the dashboard only. Nothing here can block a trade - the
// original strategy has no daily limits.

// ATR of the current symbol/timeframe expressed in points.
double ATRPoints(int shift)
  {
   double atr = iATR(NULL, 0, ATRLength, shift);
   return (gPoint > 0) ? atr / gPoint : 0.0;
  }

// Current ATR against its own 50-bar average: >1 = expanding volatility.
double ATRRatio(int shift)
  {
   double atr = iATR(NULL, 0, ATRLength, shift);
   if(atr <= 0) return 0.0;
   double sum = 0; int n = 0;
   for(int i = shift; i < shift + 50; i++)
     {
      double a = iATR(NULL, 0, ATRLength, i);
      if(a > 0) { sum += a; n++; }
     }
   if(n == 0) return 1.0;
   double avg = sum / n;
   return (avg > 0) ? atr / avg : 1.0;
  }

// The agreement level at which the combined signal actually fires.
// AND mode needs every enabled filter to agree, so the meter must hit +/-100.
// OR mode fires on a single vote, so the arm line sits at one filter's share.
// Today's realised P/L as a percentage of the day's opening equity.
double DayPnLPercent()
  {
   if(gDayStartEquity <= 0) return 0.0;
   return gDayNet / gDayStartEquity * 100.0;
  }

// Reset the per-day counters when the server date rolls over.
void RollDailyCounters()
  {
   datetime today = DayStart(TimeCurrent());
   if(today == gDayStamp) return;
   gDayStamp       = today;
   gDayStartEquity = AccountEquity();
   gDayTrades      = 0;
   gDayNet         = 0.0;
  }

// Watch the history list grow and fold each newly closed deal into the
// day tally, the losing streak and the journal.
void TrackClosedTrades()
  {
   int total = OrdersHistoryTotal();
   if(gLastHistoryCount < 0) { gLastHistoryCount = total; return; }
   if(total <= gLastHistoryCount) { gLastHistoryCount = total; return; }

   for(int i = gLastHistoryCount; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double net = SelectedNetUSD();
      gDayNet += net;
      if(net > 0) gConsecLosses = 0; else gConsecLosses++;
      gCardsDirty = true;
      Journal("CLOSED #" + IntegerToString(OrderTicket()) + "  " + Signed(net, 2));
     }
   gLastHistoryCount = total;
  }

//==================================================================//
//              S T A T I S T I C S                                 //
//==================================================================//
void RebuildStats()
  {
   int total = OrdersHistoryTotal();
   if(total == gStatHistory) return;
   gStatHistory = total;
   gStatTrades = 0; gStatWins = 0; gStatLosses = 0;
   gStatNet = 0; gStatGP = 0; gStatGL = 0; gStatCommission = 0;
   gStatBestTrade = 0; gStatWorstTrade = 0;
   gEquityPoints = 0;
   gStatToday = 0; gStatWeek = 0; gStatMonth = 0;

   //---- ACCOUNT-WIDE pass: every order, any magic, any symbol -------------
   // Balance/credit entries are deposits and withdrawals; everything else that is
   // a real BUY/SELL contributes its net result. Together they reconstruct
   // the true opening balance:  start = balance_now - all_trades - deposits
   // ...which is the figure the equity curve and GAIN% must be measured from.
   gAcctDeposits = 0; gAcctNetAll = 0; gAcctHasDep = false;
   for(int a = 0; a < total; a++)
     {
      if(!OrderSelect(a, SELECT_BY_POS, MODE_HISTORY)) continue;
      int at = OrderType();
      if(at == SF_OP_BALANCE || at == SF_OP_CREDIT)
        {
         gAcctDeposits += OrderProfit();
         gAcctHasDep = true;
         continue;
        }
      if(at != OP_BUY && at != OP_SELL) continue;
      gAcctNetAll += OrderProfit() + OrderSwap() + OrderCommission();
     }
   // If MT4 gave us the funding records, the opening balance is simply the
   // first deposit. Otherwise fall back to reconstructing it from the current
   // balance, which is still account-wide and therefore still honest.
   gAcctStart = gAcctHasDep ? gAcctDeposits
                            : (AccountBalance() - gAcctNetAll);

   datetime day = DayStart(TimeCurrent());
   MqlDateTime dt; TimeToStruct(day, dt);
   int fromMon = (dt.day_of_week == 0) ? 6 : dt.day_of_week - 1;
   datetime weekStart  = day - fromMon * 86400;
   datetime monthStart = MonthStart(TimeCurrent());

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      bool   ce  = false;                       // discarded: the estimate flag
      double cm  = TradeCommissionUSD(OrderLots(), OrderCommission(), ce);
      double net = SelectedNetUSD();
      gStatTrades++;
      gStatNet += net;
      gStatCommission += cm;
      if(net > 0) { gStatWins++; gStatGP += net; }
      else        { gStatLosses++; gStatGL += MathAbs(net); }
      gStatBestTrade  = MathMax(gStatBestTrade, net);
      gStatWorstTrade = MathMin(gStatWorstTrade, net);
      datetime ct = OrderCloseTime();
      if(ct >= day)        gStatToday += net;
      if(ct >= weekStart)  gStatWeek  += net;
      if(ct >= monthStart) gStatMonth += net;
     }

   //---- PERFORMANCE TRACKER: bucket the last SF_TRACK_DAYS trading days ----
   ArrayInitialize(gTrkLots, 0.0);   ArrayInitialize(gTrkProfit, 0.0);
   ArrayInitialize(gTrkComm, 0.0);   ArrayInitialize(gTrkGainPct, 0.0);
   ArrayInitialize(gTrkTrades, 0);   ArrayInitialize(gTrkWins, 0);
   for(int t = 0; t < SF_TRACK_DAYS; t++) gTrkDate[t] = day - t * 86400;

   for(int k = 0; k < total; k++)
     {
      if(!OrderSelect(k, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      datetime cd = DayStart(OrderCloseTime());
      for(int b = 0; b < SF_TRACK_DAYS; b++)
        {
         if(cd != gTrkDate[b]) continue;
         bool   tce = false;                    // discarded: the estimate flag
         double tcm = TradeCommissionUSD(OrderLots(), OrderCommission(), tce);
         double nt  = SelectedNetUSD();
         gTrkLots[b]   += OrderLots();
         gTrkProfit[b] += nt;
         gTrkComm[b]   += tcm;
         gTrkTrades[b]++;
         if(nt > 0) gTrkWins[b]++;
         break;
        }
     }

   double start = AccountBalance() - gStatNet;
   // Gain% for a day is measured against the balance at that day's open, so
   // each row answers "what did this day do to the account it started with".
   gTrkStartBal = start;
   double bal = start;
   double dayOpen[SF_TRACK_DAYS];
   ArrayInitialize(dayOpen, 0.0);
   for(int od = SF_TRACK_DAYS - 1; od >= 0; od--)
     {
      // walk history up to (not including) this day to find its opening balance
      double before = start;
      for(int h2 = 0; h2 < total; h2++)
        {
         if(!OrderSelect(h2, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
         if(OrderCloseTime() < gTrkDate[od])
            before += SelectedNetUSD();
        }
      dayOpen[od] = before;
      gTrkGainPct[od] = (before > 0) ? gTrkProfit[od] / before * 100.0 : 0.0;
     }

   // EQUITY CURVE: plot the REAL account, not just this EA's slice of it.
   // Filtering by magic here is what made a losing account draw a rising
   // curve - the trades that lost the money were simply not in the series.
   double run = gAcctStart, peak = gAcctStart;
   gStatMaxDD = 0;
   if(gEquityPoints < 512) gEquityCurve[gEquityPoints++] = run;
   for(int j = 0; j < total && gEquityPoints < 512; j++)
     {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY)) continue;
      int jt = OrderType();
      if(jt == SF_OP_BALANCE || jt == SF_OP_CREDIT) { run += OrderProfit(); } // funding
      else if(jt == OP_BUY || jt == OP_SELL)
         run += OrderProfit() + OrderSwap() + OrderCommission();
      else continue;
      peak = MathMax(peak, run);
      if(peak > 0) gStatMaxDD = MathMax(gStatMaxDD, (peak - run) / peak * 100.0);
      gEquityCurve[gEquityPoints++] = run;
     }
  }

//==================================================================//
//        A R A B I C   S H A P I N G   +   B I D I   (RTL)         //
//==================================================================//
// MetaTrader's canvas/GDI text layer has NO OpenType shaping engine and
// NO bidirectional algorithm. It paints the UTF-16 code points exactly as
// they sit in the string, strictly left to right. For Arabic that produces
// the classic double failure the user described:
//
//   1) DISCONNECTED letters - Arabic is cursive, and every letter has up to
//      four contextual forms (isolated / initial / medial / final). MT4 only
//      ever emits the isolated form, so words come out as loose characters.
//   2) REVERSED words - Arabic reads right to left, but MT4 lays the string
//      out left to right, so the text appears mirrored.
//
// Neither can be fixed with a font. The fix is to hand MT4 a string that is
// ALREADY shaped and ALREADY in visual order, so a dumb left-to-right
// renderer draws correct Arabic. That is what this section does:
//
//      logical text  ->  ArShape()  ->  ArBidi()  ->  MT4 draws it verbatim
//
// ArShape() swaps each letter for its correct presentation glyph from the
// Unicode Arabic Presentation Forms-B block (U+FE70..U+FEFC), which every
// Windows Arabic-capable font ships. ArBidi() then reorders the runs so the
// RTL text is stored in the order it must be PAINTED.
//
// This implementation was validated character-for-character against the
// reference `arabic-reshaper` + `python-bidi` implementations on a suite of
// mixed Arabic/Latin/numeric strings - see docs/verify_arabic.py.

#define AR_TAT    0x0640   // tatweel (kashida) - joins on both sides
#define AR_LAM    0x0644
#define AR_ALEF   0x0627

// Joining class of an Arabic letter.
//   0 = not an Arabic letter
//   1 = RIGHT-JOINING  (alef, dal, thal, reh, zain, waw: join backwards only)
//   2 = DUAL-JOINING   (connects on both sides: most letters)
int ArJoinType(const ushort c)
  {
   if(c == AR_TAT) return 2;
   switch(c)
     {
      // right-joining only
      case 0x0622: case 0x0623: case 0x0624: case 0x0625: case 0x0627:
      case 0x0629: case 0x062F: case 0x0630: case 0x0631: case 0x0632:
      case 0x0648: case 0x0649:
         return 1;
      // isolated only, never joins
      case 0x0621:
         return 0;
     }
   if(c >= 0x0626 && c <= 0x064A) return 2;   // the dual-joining bulk
   return 0;
  }

// The four presentation forms of one letter, written into f[].
// Order: 0 isolated, 1 final, 2 initial, 3 medial. A 0 entry means the
// letter has no such form and must fall back.
bool ArForms(const ushort c, ushort &f[])
  {
   ArrayResize(f, 4);
   f[0] = 0; f[1] = 0; f[2] = 0; f[3] = 0;
   // Letters 0x0621..0x063A and 0x0641..0x064A map onto Presentation
   // Forms-B in a strict, regular pattern, so the table is expressed as the
   // isolated code point plus how many forms that letter owns.
   ushort iso = 0; int cnt = 0;
   switch(c)
     {
      case 0x0621: iso = 0xFE80; cnt = 1; break;   // hamza
      case 0x0622: iso = 0xFE81; cnt = 2; break;   // alef madda
      case 0x0623: iso = 0xFE83; cnt = 2; break;   // alef hamza above
      case 0x0624: iso = 0xFE85; cnt = 2; break;   // waw hamza
      case 0x0625: iso = 0xFE87; cnt = 2; break;   // alef hamza below
      case 0x0626: iso = 0xFE89; cnt = 4; break;   // yeh hamza
      case 0x0627: iso = 0xFE8D; cnt = 2; break;   // alef
      case 0x0628: iso = 0xFE8F; cnt = 4; break;   // beh
      case 0x0629: iso = 0xFE93; cnt = 2; break;   // teh marbuta
      case 0x062A: iso = 0xFE95; cnt = 4; break;   // teh
      case 0x062B: iso = 0xFE99; cnt = 4; break;   // theh
      case 0x062C: iso = 0xFE9D; cnt = 4; break;   // jeem
      case 0x062D: iso = 0xFEA1; cnt = 4; break;   // hah
      case 0x062E: iso = 0xFEA5; cnt = 4; break;   // khah
      case 0x062F: iso = 0xFEA9; cnt = 2; break;   // dal
      case 0x0630: iso = 0xFEAB; cnt = 2; break;   // thal
      case 0x0631: iso = 0xFEAD; cnt = 2; break;   // reh
      case 0x0632: iso = 0xFEAF; cnt = 2; break;   // zain
      case 0x0633: iso = 0xFEB1; cnt = 4; break;   // seen
      case 0x0634: iso = 0xFEB5; cnt = 4; break;   // sheen
      case 0x0635: iso = 0xFEB9; cnt = 4; break;   // sad
      case 0x0636: iso = 0xFEBD; cnt = 4; break;   // dad
      case 0x0637: iso = 0xFEC1; cnt = 4; break;   // tah
      case 0x0638: iso = 0xFEC5; cnt = 4; break;   // zah
      case 0x0639: iso = 0xFEC9; cnt = 4; break;   // ain
      case 0x063A: iso = 0xFECD; cnt = 4; break;   // ghain
      case 0x0641: iso = 0xFED1; cnt = 4; break;   // feh
      case 0x0642: iso = 0xFED5; cnt = 4; break;   // qaf
      case 0x0643: iso = 0xFED9; cnt = 4; break;   // kaf
      case 0x0644: iso = 0xFEDD; cnt = 4; break;   // lam
      case 0x0645: iso = 0xFEE1; cnt = 4; break;   // meem
      case 0x0646: iso = 0xFEE5; cnt = 4; break;   // noon
      case 0x0647: iso = 0xFEE9; cnt = 4; break;   // heh
      case 0x0648: iso = 0xFEED; cnt = 2; break;   // waw
      case 0x0649: iso = 0xFEEF; cnt = 2; break;   // alef maksura
      case 0x064A: iso = 0xFEF1; cnt = 4; break;   // yeh
      case AR_TAT:                                  // tatweel keeps its shape
         f[0] = AR_TAT; f[1] = AR_TAT; f[2] = AR_TAT; f[3] = AR_TAT;
         return true;
      default: return false;
     }
   f[0] = iso;
   if(cnt >= 2) f[1] = (ushort)(iso + 1);            // final
   if(cnt == 4) { f[2] = (ushort)(iso + 2);          // initial
                  f[3] = (ushort)(iso + 3); }        // medial
   return true;
  }

// Harakat (short vowels) and other combining marks. MT4 cannot position
// combining marks, so they are dropped rather than drawn as floating boxes.
bool ArIsMark(const ushort c)
  {
   return ((c >= 0x064B && c <= 0x0655) || c == 0x0670 ||
           (c >= 0x06D6 && c <= 0x06ED));
  }

bool ArIsArabic(const ushort c)
  {
   return ((c >= 0x0600 && c <= 0x06FF) || (c >= 0xFB50 && c <= 0xFEFC));
  }

// LAM + ALEF must contract into a single mandatory ligature; rendering them
// as two separate glyphs is considered incorrect Arabic.
// Returns the isolated form, or 0 when this pair is not a ligature.
ushort ArLamAlefIso(const ushort alef)
  {
   switch(alef)
     {
      case 0x0622: return 0xFEF5;   // lam + alef madda
      case 0x0623: return 0xFEF7;   // lam + alef hamza above
      case 0x0625: return 0xFEF9;   // lam + alef hamza below
      case AR_ALEF: return 0xFEFB;  // lam + plain alef
     }
   return 0;
  }

// STEP 1 - contextual shaping. Replaces every Arabic letter with the
// presentation glyph that matches its neighbours, and contracts lam-alef.
string ArShape(const string src)
  {
   ushort src2[];
   int n = StringLen(src);
   if(n <= 0) return src;
   ArrayResize(src2, n);
   int m = 0;
   for(int i = 0; i < n; i++)
     {
      ushort c = (ushort)StringGetChar(src, i);
      if(ArIsMark(c)) continue;          // drop marks MT4 cannot place
      src2[m++] = c;
     }
   if(m <= 0) return "";

   ushort outb[];
   ArrayResize(outb, m);
   int o = 0;
   for(int i = 0; i < m; i++)
     {
      ushort c = src2[i];

      // mandatory lam-alef ligature
      if(c == AR_LAM && i + 1 < m)
        {
         ushort lig = ArLamAlefIso(src2[i + 1]);
         if(lig > 0)
           {
            // it takes the FINAL form when the preceding letter joins forward
            bool jp = (i > 0 && ArJoinType(src2[i - 1]) == 2);
            outb[o++] = (ushort)(jp ? lig + 1 : lig);
            i++;                          // consume the alef as well
            continue;
           }
        }

      ushort f[];
      if(!ArForms(c, f)) { outb[o++] = c; continue; }   // not Arabic: verbatim

      // Does the PREVIOUS letter reach forward to me? Only a dual-joining
      // letter can. Does the NEXT letter accept a connection from me? Only
      // if I am dual-joining and it is an Arabic letter at all.
      bool joinPrev = (i > 0 && ArJoinType(src2[i - 1]) == 2);
      bool joinNext = false;
      if(ArJoinType(c) == 2 && i + 1 < m)
        {
         ushort nx = src2[i + 1];
         joinNext = (ArJoinType(nx) != 0 || ArLamAlefIso(nx) > 0);
        }

      ushort g = 0;
      if(joinPrev && joinNext) g = f[3];       // medial
      else if(joinPrev)        g = f[1];       // final
      else if(joinNext)        g = f[2];       // initial
      else                     g = f[0];       // isolated
      // fall back down the chain for letters that lack that form
      if(g == 0) g = f[1];
      if(g == 0) g = f[0];
      outb[o++] = g;
     }

   string res = "";
   for(int i = 0; i < o; i++) res += ShortToString(outb[i]);
   return res;
  }

// Direction classes. Named constants rather than character literals, so the
// code does not depend on how the compiler types a single-quoted character.
#define AR_R  1   // right-to-left (Arabic)
#define AR_L  2   // left-to-right (Latin)
#define AR_D  3   // European digit
#define AR_N  4   // neutral: space, punctuation, symbols

// Direction class of one character for the bidi pass.
ushort ArClass(const ushort c)
  {
   if(ArIsArabic(c)) return AR_R;
   if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) return AR_L;
   if(c >= '0' && c <= '9') return AR_D;
   return AR_N;
  }

// Paired punctuation must be mirrored when it sits inside an RTL run:
// an opening bracket before RTL text is painted as a closing one.
ushort ArMirror(const ushort c)
  {
   switch(c)
     {
      case '(': return ')';   case ')': return '(';
      case '[': return ']';   case ']': return '[';
      case '{': return '}';   case '}': return '{';
      case '<': return '>';   case '>': return '<';
     }
   return c;
  }

// STEP 2 - the bidirectional reorder (a focused subset of UAX #9 covering
// the cases a trading panel actually produces: Arabic, Latin, numbers and
// punctuation on a single line).
//
// Rules applied: P2/P3 pick the paragraph direction from the first strong
// character; N1/N2 resolve neutrals; L2 reverses the RTL runs. The result
// is VISUAL order - exactly what a non-bidi renderer needs.
string ArBidi(const string src)
  {
   int n = StringLen(src);
   if(n <= 1) return src;

   ushort ch[], k[];
   ArrayResize(ch, n); ArrayResize(k, n);
   bool anyR = false;
   for(int i = 0; i < n; i++)
     {
      ch[i] = (ushort)StringGetChar(src, i);
      k[i]  = ArClass(ch[i]);
      if(k[i] == AR_R) anyR = true;
     }
   if(!anyR) return src;               // no Arabic at all - leave it alone

   // P2/P3 - the first strong character sets the paragraph direction.
   ushort base = AR_L;
   for(int i = 0; i < n; i++)
      if(k[i] == AR_R || k[i] == AR_L) { base = k[i]; break; }

   // A number is read left-to-right even inside Arabic text, so digits are
   // treated as an LTR run and never reversed. "0.01" must stay "0.01".
   for(int i = 0; i < n; i++)
      if(k[i] == AR_D) k[i] = AR_L;

   // N1/N2 - a neutral takes the surrounding direction when both sides
   // agree, otherwise the paragraph direction. Text boundaries count as the
   // paragraph direction (sor/eor).
   for(int i = 0; i < n; i++)
     {
      if(k[i] != AR_N) continue;
      ushort p = base, q = base;
      for(int j = i - 1; j >= 0; j--) if(k[j] != AR_N) { p = k[j]; break; }
      for(int j = i + 1; j < n;  j++) if(k[j] != AR_N) { q = k[j]; break; }
      k[i] = (p == q) ? p : base;
     }

   // L2 - emit the runs. In an RTL paragraph the run ORDER flips; an RTL run
   // is always reversed internally and its brackets mirrored.
   string res = "";
   if(base == AR_R)
     {
      int end = n;
      while(end > 0)
        {
         int st = end - 1;
         while(st > 0 && k[st - 1] == k[end - 1]) st--;
         if(k[st] == AR_R)
            for(int i = end - 1; i >= st; i--) res += ShortToString(ArMirror(ch[i]));
         else
            for(int i = st; i < end; i++)      res += ShortToString(ch[i]);
         end = st;
        }
     }
   else
     {
      int st = 0;
      while(st < n)
        {
         int end = st + 1;
         while(end < n && k[end] == k[st]) end++;
         if(k[st] == AR_R)
            for(int i = end - 1; i >= st; i--) res += ShortToString(ArMirror(ch[i]));
         else
            for(int i = st; i < end; i++)      res += ShortToString(ch[i]);
         st = end;
        }
     }
   return res;
  }

// Public entry point for CANVAS text (CCanvas::TextOut).
// The canvas is a raw pixel buffer drawn by MT4 itself: no shaping, no bidi.
// It needs the fully processed string - shaped AND reordered to visual order.
// Latin-only text is returned untouched (zero cost for the English UI).
string ArFix(const string s)
  {
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
      if(ArIsArabic((ushort)StringGetChar(s, i)))
         return ArBidi(ArShape(s));
   return s;
  }

// Public entry point for CHART OBJECTS (OBJ_BUTTON, OBJ_LABEL, ...).
//
// This is NOT the same problem as the canvas, and using ArFix() here is a bug.
// Chart objects are drawn by real Windows GDI controls, and Windows applies
// its OWN bidi reordering to the text it is given. If we hand it a string that
// is already in visual order, Windows reverses it a SECOND time and the label
// comes out backwards again:
//
//   logical "AL-RAISIYA" -> ArFix -> visual order -> Windows reverses it
//   a SECOND time -> the caption is displayed backwards again.
//
// The shaping, however, is still ours to do: MT4 passes the code points
// straight through without running the OpenType joining rules, so unshaped
// text renders as disconnected letters even though the ORDER is right.
//
// So chart objects need SHAPING ONLY, and must keep logical order.
string ArObj(const string s)
  {
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
      if(ArIsArabic((ushort)StringGetChar(s, i)))
         return ArShape(s);       // shape, but DO NOT reorder
   return s;
  }

//==================================================================//
//              U I   S T R I N G   T A B L E   ( i18n )            //
//==================================================================//
// Every visible label goes through T(). In English it returns the key
// unchanged (zero lookup cost in the common case); in Arabic it returns the
// translation, which ArFix() then shapes and reorders on the way to the
// canvas. Keys are the original English labels, so any string that has not
// been translated yet still renders - it simply stays English.
string T(const string k)
  {
   if(gLang == SF_LANG_EN) return k;
   //--- header / chrome
   if(k == "PRO")                 return "\x0628\x0631\x0648";
   if(k == "CORE")                return "\x0627\x0644\x0631\x0626\x064A\x0633\x064A\x0629";
   if(k == "FILTERS")             return "\x0627\x0644\x0641\x0644\x0627\x062A\x0631";
   if(k == "ARMED")               return "\x062C\x0627\x0647\x0632";
   if(k == "PAUSED")              return "\x0645\x062A\x0648\x0642\x0641";
   if(k == "PAUSE")               return "\x0625\x064A\x0642\x0627\x0641";
   if(k == "RESUME")              return "\x0627\x0633\x062A\x0626\x0646\x0627\x0641";
   if(k == "CLOSE ALL")           return "\x0625\x063A\x0644\x0627\x0642\x0020\x0627\x0644\x0643\x0644";
   if(k == "OVERLAY")             return "\x0627\x0644\x0631\x0633\x0645";
   if(k == "HUD")                 return "\x0627\x0644\x0644\x0648\x062D\x0629";
   //--- signal panel
   if(k == "FILTER AGREEMENT")    return "\x062A\x0648\x0627\x0641\x0642\x0020\x0627\x0644\x0641\x0644\x0627\x062A\x0631";
   if(k == "AGREEMENT")           return "\x0627\x0644\x062A\x0648\x0627\x0641\x0642";
   if(k == "EXECUTION CONSOLE")   return "\x0644\x0648\x062D\x0629\x0020\x0627\x0644\x062A\x0646\x0641\x064A\x0630";
   if(k == "BIAS")                return "\x0627\x0644\x0627\x062A\x062C\x0627\x0647";
   if(k == "VOTE")                return "\x0627\x0644\x062A\x0635\x0648\x064A\x062A";
   if(k == "DRAW")                return "\x0631\x0633\x0645";
   if(k == "FILTER")              return "\x0627\x0644\x0641\x0644\x062A\x0631";
   if(k == "BULLISH")             return "\x0635\x0627\x0639\x062F";
   if(k == "BEARISH")             return "\x0647\x0627\x0628\x0637";
   if(k == "NEUTRAL")             return "\x0645\x062D\x0627\x064A\x062F";
   if(k == "LONG")                return "\x0634\x0631\x0627\x0621";
   if(k == "SHORT")               return "\x0628\x064A\x0639";
   if(k == "FLAT")                return "\x0633\x0648\x0642\x0020\x0639\x0631\x0636\x064A";
   if(k == "N/A")                 return "\x063A\x064A\x0631\x0020\x0645\x062A\x0627\x062D";
   if(k == "ON")                  return "\x062A\x0634\x063A\x064A\x0644";
   if(k == "OFF")                 return "\x0625\x064A\x0642\x0627\x0641";
   if(k == "ALL")                 return "\x0627\x0644\x0643\x0644";
   if(k == "ANY")                 return "\x0623\x064A";
   //--- position / trade
   if(k == "NO OPEN POSITION")    return "\x0644\x0627\x0020\x062A\x0648\x062C\x062F\x0020\x0635\x0641\x0642\x0629\x0020\x0645\x0641\x062A\x0648\x062D\x0629";
   if(k == "NO CLOSED TRADES YET") return "\x0644\x0627\x0020\x062A\x0648\x062C\x062F\x0020\x0635\x0641\x0642\x0627\x062A\x0020\x0645\x063A\x0644\x0642\x0629\x0020\x0628\x0639\x062F";
   if(k == "ENTRY")               return "\x0627\x0644\x062F\x062E\x0648\x0644";
   if(k == "STOP LOSS")           return "\x0648\x0642\x0641\x0020\x0627\x0644\x062E\x0633\x0627\x0631\x0629";
   if(k == "TAKE PROFIT")         return "\x062C\x0646\x064A\x0020\x0627\x0644\x0623\x0631\x0628\x0627\x062D";
   if(k == "TRAILING")            return "\x0627\x0644\x0648\x0642\x0641\x0020\x0627\x0644\x0645\x062A\x062D\x0631\x0643";
   if(k == "BREAK-EVEN")          return "\x0646\x0642\x0637\x0629\x0020\x0627\x0644\x062A\x0639\x0627\x062F\x0644";
   if(k == "SPREAD")              return "\x0627\x0644\x0641\x0627\x0631\x0642";
   if(k == "LOTS")                return "\x0627\x0644\x0644\x0648\x062A";
   if(k == "ROUND TURN")          return "\x0630\x0647\x0627\x0628\x0020\x0648\x0639\x0648\x062F\x0629";
   if(k == "COST / ATR(")         return "\x0627\x0644\x062A\x0643\x0644\x0641\x0629\x0020\x002F\x0020\x0041\x0054\x0052\x0028";
   //--- tracker
   if(k == "PERFORMANCE TRACKER") return "\x0645\x062A\x062A\x0628\x0639\x0020\x0627\x0644\x0623\x062F\x0627\x0621";
   if(k == "DATE")                return "\x0627\x0644\x062A\x0627\x0631\x064A\x062E";
   if(k == "LOT")                 return "\x0627\x0644\x0644\x0648\x062A";
   if(k == "PROFIT")              return "\x0627\x0644\x0631\x0628\x062D";
   if(k == "GAIN%")               return "\x0627\x0644\x0646\x0633\x0628\x0629\x066A";
   if(k == "WINRATE")             return "\x0646\x0633\x0628\x0629\x0020\x0627\x0644\x0641\x0648\x0632";
   if(k == "COMMISSION")          return "\x0627\x0644\x0639\x0645\x0648\x0644\x0629";
   if(k == "FINAL P/L")           return "\x0627\x0644\x0635\x0627\x0641\x064A\x0020\x0627\x0644\x0646\x0647\x0627\x0626\x064A";
   if(k == "FINAL P/L  (NET OF COMMISSION)") return "\x0627\x0644\x0635\x0627\x0641\x064A\x0020\x0627\x0644\x0646\x0647\x0627\x0626\x064A\x0020\x0028\x0628\x0639\x062F\x0020\x0627\x0644\x0639\x0645\x0648\x0644\x0629\x0029";
   if(k == "EQUITY CURVE")        return "\x0645\x0646\x062D\x0646\x0649\x0020\x0627\x0644\x0645\x0644\x0643\x064A\x0629";
   if(k == "EQUITY")              return "\x0627\x0644\x0645\x0644\x0643\x064A\x0629";
   if(k == "BALANCE")             return "\x0627\x0644\x0631\x0635\x064A\x062F";
   if(k == "FLOATING P/L")        return "\x0627\x0644\x0631\x0628\x062D\x0020\x0627\x0644\x0639\x0627\x0626\x0645";
   if(k == "DAY P/L")             return "\x0631\x0628\x062D\x0020\x0627\x0644\x064A\x0648\x0645";
   if(k == "MAX DD")              return "\x0623\x0642\x0635\x0649\x0020\x062A\x0631\x0627\x062C\x0639";
   if(k == "TOTAL")               return "\x0627\x0644\x0625\x062C\x0645\x0627\x0644\x064A";
   if(k == "TRADES")              return "\x0627\x0644\x0635\x0641\x0642\x0627\x062A";
   if(k == "WINS")                return "\x0631\x0627\x0628\x062D\x0629";
   if(k == "LOSSES")              return "\x062E\x0627\x0633\x0631\x0629";
   if(k == "FEES")                return "\x0627\x0644\x0631\x0633\x0648\x0645";
   if(k == "GROSS")               return "\x0627\x0644\x0625\x062C\x0645\x0627\x0644\x064A";
   if(k == "NET")                 return "\x0627\x0644\x0635\x0627\x0641\x064A";
   if(k == "TRADE NOT ALLOWED")         return "\x0627\x0644\x062A\x062F\x0627\x0648\x0644\x0020\x063A\x064A\x0631\x0020\x0645\x0633\x0645\x0648\x062D";
   if(k == "POSITION OPEN")             return "\x0635\x0641\x0642\x0629\x0020\x0645\x0641\x062A\x0648\x062D\x0629";
   if(k == "pts")                       return "\x0646\x0642\x0637\x0629";
   if(k == "SHOWING ALL")               return "\x0639\x0631\x0636\x0020\x0627\x0644\x0643\x0644";
   if(k == "ACCOUNT P/L")               return "\x0631\x0628\x062D\x002F\x062E\x0633\x0627\x0631\x0629\x0020\x0627\x0644\x062D\x0633\x0627\x0628";
   if(k == "START")                     return "\x0627\x0644\x0628\x062F\x0627\x064A\x0629";
   if(k == "THIS EA")                   return "\x0647\x0630\x0627\x0020\x0627\x0644\x062E\x0628\x064A\x0631";
   if(k == "BREAKOUT")                  return "\x0627\x0644\x0627\x062E\x062A\x0631\x0627\x0642";
   if(k == "SESSION RANGE")             return "\x0646\x0637\x0627\x0642\x0020\x0627\x0644\x062C\x0644\x0633\x0629";
   if(k == "HIGH")                      return "\x0627\x0644\x0623\x0639\x0644\x0649";
   if(k == "LOW")                       return "\x0627\x0644\x0623\x062F\x0646\x0649";
   if(k == "WIDTH")                     return "\x0627\x0644\x0639\x0631\x0636";
   if(k == "NO VALID RANGE")            return "\x0644\x0627\x0020\x064A\x0648\x062C\x062F\x0020\x0646\x0637\x0627\x0642\x0020\x0635\x0627\x0644\x062D";
   if(k == "WAITING FOR BREAK")         return "\x0628\x0627\x0646\x062A\x0638\x0627\x0631\x0020\x0627\x0644\x0627\x062E\x062A\x0631\x0627\x0642";
   if(k == "COLLECTING")                return "\x062C\x0627\x0631\x064A\x0020\x0627\x0644\x062A\x062C\x0645\x064A\x0639";
   if(k == "FAILED BREAKS")             return "\x0627\x062E\x062A\x0631\x0627\x0642\x0020\x0641\x0627\x0634\x0644";
   if(k == "RANGE TOO TIGHT")           return "\x0627\x0644\x0646\x0637\x0627\x0642\x0020\x0636\x064A\x0642\x0020\x062C\x062F\x0627";
   if(k == "RANGE TOO WIDE")            return "\x0627\x0644\x0646\x0637\x0627\x0642\x0020\x0648\x0627\x0633\x0639\x0020\x062C\x062F\x0627";
   if(k == "of")                        return "\x0645\x0646";
   if(k == "bars")                      return "\x0634\x0645\x0639\x0629";
   if(k == "minimum")                  return "\x0627\x0644\x062D\x062F\x0020\x0627\x0644\x0623\x062F\x0646\x0649";
   if(k == "STOP TOO WIDE")             return "\x0627\x0644\x0648\x0642\x0641\x0020\x0628\x0639\x064A\x062F\x0020\x062C\x062F\x0627";
   if(k == "RISK TOO HIGH")             return "\x0627\x0644\x0645\x062E\x0627\x0637\x0631\x0629\x0020\x0639\x0627\x0644\x064A\x0629\x0020\x062C\x062F\x0627";
   if(k == "NO STOP")                   return "\x0644\x0627\x0020\x064A\x0648\x062C\x062F\x0020\x0648\x0642\x0641";
   if(k == "NO TICK VALUE")             return "\x0644\x0627\x0020\x062A\x0648\x062C\x062F\x0020\x0642\x064A\x0645\x0629\x0020\x0627\x0644\x0646\x0642\x0637\x0629";
   if(k == "NO RISK BUDGET")            return "\x0644\x0627\x0020\x062A\x0648\x062C\x062F\x0020\x0645\x064A\x0632\x0627\x0646\x064A\x0629\x0020\x0645\x062E\x0627\x0637\x0631\x0629";
   if(k == "LOSS CAP")                  return "\x062D\x062F\x0020\x0627\x0644\x062E\x0633\x0627\x0631\x0629";
   if(k == "RISK")                      return "\x0627\x0644\x0645\x062E\x0627\x0637\x0631\x0629";
   if(k == "lots")                      return "\x0644\x0648\x062A";
   if(k == "SKIP")                      return "\x062A\x062E\x0637\x064A";
   if(k == "T")                         return "\x0635";
   if(k == "F")                         return "\x0641";
   if(k == "BUILDING RANGE")            return "\x0628\x0646\x0627\x0621\x0020\x0627\x0644\x0646\x0637\x0627\x0642";
   if(k == "BROKEN")                    return "\x062A\x0645\x0020\x0627\x0644\x0627\x062E\x062A\x0631\x0627\x0642";
   if(k == "WAITING RETEST")            return "\x0628\x0627\x0646\x062A\x0638\x0627\x0631\x0020\x0625\x0639\x0627\x062F\x0629\x0020\x0627\x0644\x0627\x062E\x062A\x0628\x0627\x0631";
   if(k == "TRADE TAKEN")               return "\x062A\x0645\x0020\x0627\x0644\x062F\x062E\x0648\x0644";
   if(k == "PRICE INSIDE RANGE")        return "\x0627\x0644\x0633\x0639\x0631\x0020\x062F\x0627\x062E\x0644\x0020\x0627\x0644\x0646\x0637\x0627\x0642";
   if(k == "UPSIDE")                    return "\x0635\x0639\x0648\x062F\x064A";
   if(k == "DOWNSIDE")                  return "\x0647\x0628\x0648\x0637\x064A";
   if(k == "DISTANCE TO BREAK")         return "\x0627\x0644\x0645\x0633\x0627\x0641\x0629\x0020\x0625\x0644\x0649\x0020\x0627\x0644\x0627\x062E\x062A\x0631\x0627\x0642";
   if(k == "ENTRY CHECKLIST")           return "\x0642\x0627\x0626\x0645\x0629\x0020\x0627\x0644\x0634\x0631\x0648\x0637";
   if(k == "RANGE OK")                  return "\x0627\x0644\x0646\x0637\x0627\x0642";
   if(k == "VOLATILITY")                return "\x0627\x0644\x062A\x0630\x0628\x0630\x0628";
   if(k == "RANGE WIDTH")               return "\x0639\x0631\x0636\x0020\x0627\x0644\x0646\x0637\x0627\x0642";
   if(k == "BODY CLOSE")                return "\x0625\x063A\x0644\x0627\x0642\x0020\x0627\x0644\x062C\x0633\x0645";
   if(k == "NO ROLLOVER")               return "\x062E\x0627\x0631\x062C\x0020\x0627\x0644\x062A\x0628\x064A\x064A\x062A";
   if(k == "DAILY LIMIT")               return "\x0627\x0644\x062D\x062F\x0020\x0627\x0644\x064A\x0648\x0645\x064A";
   if(k == "WAIT")                      return "\x0627\x0646\x062A\x0638\x0627\x0631";
   if(k == "DONCHIAN")                  return "\x062F\x0648\x0646\x0634\x064A\x0627\x0646";
   if(k == "RANGE")                     return "\x0627\x0644\x0646\x0637\x0627\x0642";
   if(k == "NO BREAK")                  return "\x0644\x0627\x0020\x0627\x062E\x062A\x0631\x0627\x0642";
   if(k == "ROLLOVER")                  return "\x0627\x0644\x062A\x0628\x064A\x064A\x062A";
   if(k == "LIMIT")                     return "\x0627\x0644\x062D\x062F";
   if(k == "MAX TRADES")                return "\x0623\x0642\x0635\x0649\x0020\x0639\x062F\x062F\x0020\x0635\x0641\x0642\x0627\x062A";
   if(k == "DAILY LOSS")                return "\x0627\x0644\x062E\x0633\x0627\x0631\x0629\x0020\x0627\x0644\x064A\x0648\x0645\x064A\x0629";
   if(k == "NO CONFLUENCE")             return "\x0644\x0627\x0020\x062A\x0648\x0627\x0641\x0642";
   if(k == "OK")                  return "\x062A\x0645";
   if(k == "TODAY")               return "\x0627\x0644\x064A\x0648\x0645";
   if(k == "WIN")                       return "\x0631\x0628\x062D";
   if(k == "LOSS")                      return "\x062E\x0633\x0627\x0631\x0629";
   if(k == "USD")                       return "\x062F\x0648\x0644\x0627\x0631";
   if(k == "lot")                       return "\x0644\x0648\x062A";
   if(k == "p")                         return "\x0646";
   if(k == "m")                         return "\x062F";
   if(k == "FEE")                       return "\x0631\x0633\x0648\x0645";
   if(k == "BUY")                       return "\x0634\x0631\x0627\x0621";
   if(k == "SELL")                      return "\x0628\x064A\x0639";
   if(k == "WIN RATE")                  return "\x0646\x0633\x0628\x0629\x0020\x0627\x0644\x0641\x0648\x0632";
   if(k == "P/FACTOR")                  return "\x0645\x0639\x0627\x0645\x0644\x0020\x0627\x0644\x0631\x0628\x062D";
   if(k == "MODE: ALL")                 return "\x0627\x0644\x0648\x0636\x0639\x003A\x0020\x0627\x0644\x0643\x0644";
   if(k == "MODE: ANY")                 return "\x0627\x0644\x0648\x0636\x0639\x003A\x0020\x0623\x064A";
   if(k == "ALL-ALIGN")                 return "\x062A\x0648\x0627\x0641\x0642\x0020\x0643\x0644\x064A";
   if(k == "ANY-ALIGN")                 return "\x062A\x0648\x0627\x0641\x0642\x0020\x062C\x0632\x0626\x064A";
   if(k == "SCANNING")                  return "\x062C\x0627\x0631\x064A\x0020\x0627\x0644\x0645\x0633\x062D";
   if(k == "COST INTELLIGENCE")         return "\x062A\x062D\x0644\x064A\x0644\x0020\x0627\x0644\x062A\x0643\x0644\x0641\x0629";
   if(k == "RAW SPREAD")                return "\x0627\x0644\x0641\x0627\x0631\x0642\x0020\x0627\x0644\x062E\x0627\x0645";
   if(k == "LAST")                      return "\x0622\x062E\x0631";
   if(k == "DAYS")                      return "\x0623\x064A\x0627\x0645";
   if(k == "WK")                        return "\x0627\x0644\x0623\x0633\x0628\x0648\x0639";
   if(k == "MO")                        return "\x0627\x0644\x0634\x0647\x0631";
   if(k == "TRADES TODAY")              return "\x0635\x0641\x0642\x0627\x062A\x0020\x0627\x0644\x064A\x0648\x0645";
   if(k == "REGIME")                    return "\x0627\x0644\x0646\x0645\x0637";
   if(k == "BAL")                       return "\x0627\x0644\x0631\x0635\x064A\x062F";
   if(k == "WIN%")                return "\x0627\x0644\x0641\x0648\x0632\x066A";
   if(k == "COMM")                return "\x0627\x0644\x0639\x0645\x0648\x0644\x0629";
   if(k == "RESUME TRADING")      return "\x0627\x0633\x062A\x0626\x0646\x0627\x0641\x0020\x0627\x0644\x062A\x062F\x0627\x0648\x0644";
   if(k == "PAUSE TRADING")       return "\x0625\x064A\x0642\x0627\x0641\x0020\x0627\x0644\x062A\x062F\x0627\x0648\x0644";
   if(k == "ACTIVE ONLY")         return "\x0627\x0644\x0646\x0634\x0637\x0629\x0020\x0641\x0642\x0637";
   return k;                       // untranslated keys stay English
  }

// The Latin UI font has no Arabic glyphs, so the font must switch with the
// language. Everything else (sizes, weights, layout) is unchanged.
string UIFont(const string latin)
  {
   if(gLang == SF_LANG_EN) return latin;
   // preserve the weight the caller asked for where the Arabic font has one
   if(StringFind(latin, "Black") >= 0 || StringFind(latin, "Bold") >= 0)
      return HudArabicFont + " Bold";
   return HudArabicFont;
  }

//==================================================================//
//              C A N V A S   P R I M I T I V E S                   //
//==================================================================//
struct SFButton
  {
   int      x, y, w, h;
   string   id;
  };
SFButton gButtons[40];   // 11 per-filter DRAW toggles + chrome
int      gButtonCount = 0;

// MT4 has NO transparent OBJ_BUTTON: clrNONE is rendered as BLACK, and the
// object is drawn ON TOP of the canvas bitmap. v2.09 used invisible hotspots
// for hit-testing, which is exactly why the panel sprouted black boxes.
//
// v2.10 therefore stops faking controls with pixels. Every button is now a
// REAL OBJ_BUTTON, styled with the theme colours, carrying its own caption.
// MT4 draws it, MT4 reports its clicks by name - nothing depends on the
// bitmap or on coordinate routing any more.

// CCanvas colours are packed ARGB uints; MT4 object colours are BGR `color`.
color CLR(uint argb)
  {
   int r = (int)((argb >> 16) & 0xFF);
   int g = (int)((argb >>  8) & 0xFF);
   int b = (int)( argb        & 0xFF);
   return (color)((b << 16) | (g << 8) | r);
  }

// Create or update the real control. x/y are CHART pixels.
void ChartButton(string id, int x, int y, int w, int h, string caption,
                 color bg, color fg, color border, int fsize, string font)
  {
   string n = PFX + "BTN_" + id;
   // MT4 renders an OBJ_BUTTON caption with the same non-shaping, non-bidi
   // text layer as the canvas, so the caption must be shaped too - otherwise
   // the panel is Arabic but the buttons are broken letters. Shape ONCE here,
   // before the idempotency comparison below, so the stored caption and the
   // comparison string are the same thing and the button is not rewritten on
   // every repaint (which would cancel clicks - see the STATE note).
   // SHAPING ONLY - a button is a Windows control and does its own bidi.
   // Passing ArFix() here reverses the caption twice. See ArObj().
   caption = ArObj(caption);
   font    = UIFont(font);
   bool fresh = (ObjectFind(0, n) < 0);
   if(fresh) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   else
     {
      // Already on the chart: only write properties that actually CHANGED.
      // The HUD repaints ~5x a second, and blindly rewriting every property
      // (or deleting and recreating the object) tears down the control while
      // MT4 is still processing the press - the click is then lost and the
      // button just "flashes". Skipping no-op writes keeps it stable.
      if((int)ObjectGetInteger(0, n, OBJPROP_XDISTANCE) == x &&
         (int)ObjectGetInteger(0, n, OBJPROP_YDISTANCE) == y &&
         (int)ObjectGetInteger(0, n, OBJPROP_XSIZE)     == w &&
         (int)ObjectGetInteger(0, n, OBJPROP_YSIZE)     == h &&
         (color)ObjectGetInteger(0, n, OBJPROP_BGCOLOR) == bg &&
         (color)ObjectGetInteger(0, n, OBJPROP_COLOR)   == fg &&
         ObjectGetString(0, n, OBJPROP_TEXT)            == caption &&
         ObjectGetString(0, n, OBJPROP_FONT)            == font)
         return;   // nothing changed - see the STATE warning below
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetString (0, n, OBJPROP_TEXT,         caption);
   ObjectSetString (0, n, OBJPROP_FONT,         font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     fsize);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE,  BORDER_RAISED);
   ObjectSetInteger(0, n, OBJPROP_BACK,         false);
   // NEVER write OBJPROP_STATE from a repaint. MT4 sets STATE=true on mouse
   // DOWN and only queues CHARTEVENT_OBJECT_CLICK on mouse UP. The HUD
   // repaints every ~220 ms, so a timer tick landing inside a normal
   // 80-150 ms press popped the button back up and MT4 cancelled the pending
   // click: the button flashed and no event was ever delivered. STATE is now
   // reset exactly once, in the click handler itself.
   if(fresh) ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_SELECTED,     false);
   // HIDDEN only removes the object from the Object List dialog; it does not
   // affect clicks. Keep it tidy but explicit.
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,       true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       1000);
  }

void RegisterButton(string id, int x, int y, int w, int h)
  {
   if(gButtonCount >= 40) return;
   gButtons[gButtonCount].id = id;
   gButtons[gButtonCount].x  = x;
   gButtons[gButtonCount].y  = y;
   gButtons[gButtonCount].w  = w;
   gButtons[gButtonCount].h  = h;
   gButtonCount++;
  }

string HitButton(int x, int y)
  {
   for(int i = 0; i < gButtonCount; i++)
      if(x >= gButtons[i].x && x <= gButtons[i].x + gButtons[i].w &&
         y >= gButtons[i].y && y <= gButtons[i].y + gButtons[i].h)
         return gButtons[i].id;
   return "";
  }

// Midpoint-circle arc restricted to ONE quadrant. CCanvas::Circle() draws a
// full ring, so using it for rounded corners left a visible "O" bubble at
// every corner of every panel. Quadrants: 0=TL 1=TR 2=BL 3=BR.
void ArcQuarter(int cx, int cy, int r, int quad, uint clr)
  {
   if(r <= 0) return;
   int x = r, y = 0, err = 1 - r;
   while(x >= y)
     {
      if(quad == 0)      { gCv.PixelSet(cx - x, cy - y, clr); gCv.PixelSet(cx - y, cy - x, clr); }
      else if(quad == 1) { gCv.PixelSet(cx + x, cy - y, clr); gCv.PixelSet(cx + y, cy - x, clr); }
      else if(quad == 2) { gCv.PixelSet(cx - x, cy + y, clr); gCv.PixelSet(cx - y, cy + x, clr); }
      else               { gCv.PixelSet(cx + x, cy + y, clr); gCv.PixelSet(cx + y, cy + x, clr); }
      y++;
      if(err < 0) err += 2 * y + 1;
      else { x--; err += 2 * (y - x) + 1; }
     }
  }

void RoundRect(int x, int y, int w, int h, int r, uint fill, uint border, bool drawBorder = true)
  {
   if(w <= 0 || h <= 0) return;
   r = MathMax(0, MathMin(r, MathMin(w, h) / 2));
   gCv.FillRectangle(x + r, y,         x + w - r, y + h,     fill);
   gCv.FillRectangle(x,     y + r,     x + r,     y + h - r, fill);
   gCv.FillRectangle(x + w - r, y + r, x + w,     y + h - r, fill);
   if(r > 0)
     {
      gCv.FillCircle(x + r,         y + r,         r, fill);
      gCv.FillCircle(x + w - r - 1, y + r,         r, fill);
      gCv.FillCircle(x + r,         y + h - r - 1, r, fill);
      gCv.FillCircle(x + w - r - 1, y + h - r - 1, r, fill);
     }
   if(drawBorder)
     {
      gCv.Line(x + r, y,         x + w - r, y,         border);
      gCv.Line(x + r, y + h - 1, x + w - r, y + h - 1, border);
      gCv.Line(x,         y + r, x,         y + h - r, border);
      gCv.Line(x + w - 1, y + r, x + w - 1, y + h - r, border);
      if(r > 0)
        {
         ArcQuarter(x + r,         y + r,         r, 0, border);
         ArcQuarter(x + w - r - 1, y + r,         r, 1, border);
         ArcQuarter(x + r,         y + h - r - 1, r, 2, border);
         ArcQuarter(x + w - r - 1, y + h - r - 1, r, 3, border);
        }
     }
  }


// ---- RAISED 3D SURFACE -------------------------------------------------
// Draws a solid plate with a light top/left edge and a dark bottom/right
// edge, plus an outer drop shadow. This is what makes every panel read as
// physically raised off the chart instead of a flat coloured rectangle.
void RaisedPlate(int x, int y, int w, int h, int r, uint fill, uint edge,
                 bool shadow = true, int depth = 2)
  {
   if(w <= 2 || h <= 2) return;
   if(shadow)
     {
      // soft drop shadow, offset down-right
      for(int d = depth + 1; d >= 1; d--)
         RoundRect(x + d, y + d, w, h, r, A(C'0,0,0', (uchar)(70 / d)), 0, false);
     }
   RoundRect(x, y, w, h, r, fill, edge);
   // highlight: top + left
   gCv.Line(x + r,     y + 1,     x + w - r - 1, y + 1,         TLite);
   gCv.Line(x + 1,     y + r,     x + 1,         y + h - r - 1, TLite);
   // shadow: bottom + right
   gCv.Line(x + r,     y + h - 2, x + w - r - 1, y + h - 2,     TDark);
   gCv.Line(x + w - 2, y + r,     x + w - 2,     y + h - r - 1, TDark);
  }

// Inset/sunken well - used for meter tracks and table bodies.
void SunkenWell(int x, int y, int w, int h, int r, uint fill)
  {
   if(w <= 2 || h <= 2) return;
   RoundRect(x, y, w, h, r, fill, TDark);
   gCv.Line(x + r, y + 1, x + w - r - 1, y + 1, TDark);
   gCv.Line(x + 1, y + r, x + 1, y + h - r - 1, TDark);
   gCv.Line(x + r, y + h - 2, x + w - r - 1, y + h - 2, TLite);
  }

// Glowing accent bar - a vivid 3px spine used to tag panels and rows.
void AccentSpine(int x, int y, int h, uint c)
  {
   gCv.FillRectangle(x,     y, x + 2, y + h, c);
   gCv.FillRectangle(x + 3, y, x + 3, y + h, A(C'0,0,0',90));
  }

// Vertical gradient fill - gives the panels real depth instead of flat blocks.
void GradientRect(int x, int y, int w, int h, uint top, uint bottom)
  {
   if(h <= 0) return;
   uchar ta = (uchar)((top >> 24) & 0xFF), tr = (uchar)((top >> 16) & 0xFF);
   uchar tg = (uchar)((top >> 8) & 0xFF),  tb = (uchar)(top & 0xFF);
   uchar ba = (uchar)((bottom >> 24) & 0xFF), br = (uchar)((bottom >> 16) & 0xFF);
   uchar bg = (uchar)((bottom >> 8) & 0xFF),  bb = (uchar)(bottom & 0xFF);
   for(int i = 0; i < h; i++)
     {
      double t = (double)i / MathMax(1, h - 1);
      uint c = ((uint)(ta + (ba - ta) * t) << 24) |
               ((uint)(tr + (br - tr) * t) << 16) |
               ((uint)(tg + (bg - tg) * t) << 8)  |
                (uint)(tb + (bb - tb) * t);
      gCv.Line(x, y + i, x + w, y + i, c);
     }
  }

// Every label in the panel funnels through these five wrappers, so shaping
// and the Arabic font swap are applied HERE - once, at the chokepoint -
// rather than at several hundred call sites. ArFix() is a no-op for pure
// Latin text, so the English UI is completely unaffected.
void Text(int x, int y, string s, uint c, int size = 8, string font = "Segoe UI", uint flags = 0)
  {
   gCv.FontSet(UIFont(font), SC(size) * -10, flags);
   gCv.TextOut(x, y, ArFix(s), c, SF_AL_LEFT | SF_AL_TOP);
  }

// Vertically centre one line inside a box of height h.
// Every label used to be placed with a hand-tuned magic offset (y + SC(5),
// y + h/2 - SC(7), ...). Those offsets were tuned at HudScalePercent = 100
// and for one particular font, so text drifted out of its panel as soon as
// the scale or the installed font changed. Measuring the glyph box with
// TextSize() and centring on it removes the guesswork.
void TextVC(int x, int y, int h, string s, uint c, int size = 8,
            string font = "Segoe UI", uint flags = 0)
  {
   gCv.FontSet(UIFont(font), SC(size) * -10, flags);
   string d = ArFix(s);
   int tw = 0, th = 0;
   gCv.TextSize(d, tw, th);
   gCv.TextOut(x, y + (h - th) / 2, d, c, SF_AL_LEFT | SF_AL_TOP);
  }

void TextRight(int x, int y, string s, uint c, int size = 8, string font = "Segoe UI", uint flags = 0)
  {
   gCv.FontSet(UIFont(font), SC(size) * -10, flags);
   gCv.TextOut(x, y, ArFix(s), c, SF_AL_RIGHT | SF_AL_TOP);
  }

void TextCenter(int x, int y, string s, uint c, int size = 8, string font = "Segoe UI", uint flags = 0)
  {
   gCv.FontSet(UIFont(font), SC(size) * -10, flags);
   gCv.TextOut(x, y, ArFix(s), c, SF_AL_CENTER | SF_AL_TOP);
  }

// Centre a label inside a rectangle on BOTH axes, using the measured glyph
// box. Anything that centres by eye (a hardcoded y + SC(6)) is only correct
// for the font it was tuned against: the Arabic face has different ascent and
// descent, so those labels sat high in the Arabic build. Measuring fixes both
// languages at once.
void TextBoxCenter(int x, int y, int w, int h, string s, uint c, int size = 8,
                   string font = "Segoe UI", uint flags = 0)
  {
   gCv.FontSet(UIFont(font), SC(size) * -10, flags);
   string d = ArFix(s);
   int tw = 0, th = 0;
   gCv.TextSize(d, tw, th);
   gCv.TextOut(x + w / 2, y + (h - th) / 2, d, c, SF_AL_CENTER | SF_AL_TOP);
  }

// Horizontal meter with a filled portion - used for score, risk and cost.
// blend two ARGB colours (t = 0..1)
// Strength-graded fill: weak -> amber, mid -> accent, strong -> bull/bear.
// Lets you read signal conviction from the bar colour, not just its length.
void Meter(int x, int y, int w, int h, double pct01, uint fill, uint track)
  {
   pct01 = MathMax(0.0, MathMin(1.0, pct01));
   SunkenWell(x, y, w, h, h / 2, track);
   int fw = (int)MathRound((w - 2) * pct01);
   if(fw <= 0) return;
   if(fw > h) RoundRect(x + 1, y + 1, fw, h - 2, (h - 2) / 2, fill, fill, false);
   else gCv.FillRectangle(x + 1, y + 1, x + 1 + fw, y + h - 1, fill);
   // glossy top edge on the filled portion
   gCv.Line(x + 2, y + 2, x + fw - 1, y + 2, A(C'255,255,255',70));
  }


// Semi-circular conviction gauge. The needle sweeps from full bear (left)
// to full bull (right); the arc itself is coloured by the live score.
// Compact sparkline of the closed-trade equity curve.
void Sparkline(int x, int y, int w, int h, uint line, uint fill)
  {
   if(gEquityPoints < 2)
     {
      TextCenter(x + w / 2, y + h / 2 - SC(6), T("NO CLOSED TRADES YET"), TTextDim, 7);
      return;
     }
   double mn = gEquityCurve[0], mx = gEquityCurve[0];
   for(int i = 1; i < gEquityPoints; i++)
     { mn = MathMin(mn, gEquityCurve[i]); mx = MathMax(mx, gEquityCurve[i]); }
   if(mx - mn < 0.01) { mx += 0.5; mn -= 0.5; }

   int prevX = x, prevY = y + h - (int)((gEquityCurve[0] - mn) / (mx - mn) * h);
   for(int p = 1; p < gEquityPoints; p++)
     {
      int cx = x + (int)((double)p / (gEquityPoints - 1) * w);
      int cy = y + h - (int)((gEquityCurve[p] - mn) / (mx - mn) * h);
      gCv.Line(prevX, prevY, cx, cy, line);
      gCv.Line(prevX, prevY + 1, cx, cy + 1, line);
      for(int fy = (cy > y ? cy : y); fy < y + h; fy += 3) gCv.PixelSet(cx, fy, fill);
      prevX = cx; prevY = cy;
     }
  }

void StatusDot(int x, int y, int r, bool on, uint onC, uint offC)
  {
   gCv.FillCircle(x, y, r, on ? onC : offC);
   gCv.Circle(x, y, r + 1, on ? onC : TGridC);
  }

//==================================================================//
//              Q U A N T U M   H U D                               //
//==================================================================//
string StateText()
  {
   if(gPaused) return T("PAUSED");
   if(gBlockReason != "") return gBlockReason;   // already translated at source
   return T("ARMED");
  }

uint StateColor()
  {
   if(gPaused) return TBear;
   if(gBlockReason != "") return TFlat;
   return TBull;
  }

void DestroyHud()
  {
   if(gHudReady && gHud != NULL) gHud.Destroy();
   gHudReady = false; gHudW = 0; gHudH = 0;
   ObjectDelete(0, PFX + "HUD");
  }

void DestroyTracker()
  {
   if(gTrkReady && gTrk != NULL) gTrk.Destroy();
   gTrkReady = false; gTrkW = 0; gTrkH = 0;
   ObjectDelete(0, PFX + "TRK");
  }

bool EnsureHud(int w, int h)
  {
   if(gHud == NULL) gHud = new CCanvas;
   if(gHud == NULL) return false;
   if(gHudReady && w == gHudW && h == gHudH) return true;

   // Resize IN PLACE when the object already exists. Destroying and
   // re-creating the bitmap label on every size change (i.e. every collapse
   // or page switch) threw away the click target mid-dispatch, which is why
   // the minimise/maximise button felt dead.
   if(gHudReady && ObjectFind(0, PFX + "HUD") >= 0)
     {
      if(gHud.Resize(w, h))
        {
         gHudW = w; gHudH = h;
         ObjectSetInteger(0, PFX + "HUD", OBJPROP_XSIZE, w);
         ObjectSetInteger(0, PFX + "HUD", OBJPROP_YSIZE, h);
         return true;
        }
     }

   DestroyHud();
   if(!gHud.CreateBitmapLabel(0, 0, PFX + "HUD", HudMargin, HudMargin, w, h, COLOR_FORMAT_ARGB_NORMALIZE))
      return false;
   gHudReady = true; gHudW = w; gHudH = h;
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_XDISTANCE, HudMargin);
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_YDISTANCE, HudMargin);
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_BACK, false);
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, PFX + "HUD", OBJPROP_ZORDER, 500);
   return true;
  }

// The tracker is pinned to the TOP-RIGHT corner. MT4 measures
// CORNER_RIGHT_UPPER objects from the right edge, so XDISTANCE is the gap
// between the panel's RIGHT edge and the chart's right edge.
bool EnsureTracker(int w, int h)
  {
   if(gTrk == NULL) gTrk = new CCanvas;
   if(gTrk == NULL) return false;
   if(gTrkReady && w == gTrkW && h == gTrkH) return true;

   if(gTrkReady && ObjectFind(0, PFX + "TRK") >= 0)
     {
      if(gTrk.Resize(w, h))
        {
         gTrkW = w; gTrkH = h;
         ObjectSetInteger(0, PFX + "TRK", OBJPROP_XSIZE, w);
         ObjectSetInteger(0, PFX + "TRK", OBJPROP_YSIZE, h);
         return true;
        }
     }

   DestroyTracker();
   if(!gTrk.CreateBitmapLabel(0, 0, PFX + "TRK", HudMargin, HudMargin, w, h, COLOR_FORMAT_ARGB_NORMALIZE))
      return false;
   gTrkReady = true; gTrkW = w; gTrkH = h;
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_XDISTANCE, HudMargin + w);
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_YDISTANCE, HudMargin);
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_BACK, false);
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, PFX + "TRK", OBJPROP_ZORDER, 500);
   return true;
  }

void DrawChip(int x, int y, int w, int h, string label, string value, uint valueColor, uint accent)
  {
   RaisedPlate(x, y, w, h, SC(6), TPanel, TBorder);
   AccentSpine(x + SC(3), y + SC(5), h - SC(10), accent);
   // translate here rather than at each call site, so every chip is covered
   Text(x + SC(12), y + SC(6),  T(label), TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
   Text(x + SC(12), y + SC(19), value, valueColor, 10, "Segoe UI Black", SF_FW_BLACK);
  }

// A REAL MT4 button. Nothing is painted into the bitmap for it, so the canvas
// can never be covered by the control (that was the black-box bug).
void DrawButton(int x, int y, int w, int h, string id, string caption, bool active, uint accent)
  {
   uint fill = active ? accent : TPanel;
   uint txt  = active ? A(C'6,10,18',255) : TText;
   uint edge = active ? accent : TBorder;
   ChartButton(id, gCvOx + x, gCvOy + y, w, h, caption,
               CLR(fill), CLR(txt), CLR(edge), 8, "Segoe UI Semibold");
   RegisterButton(id, gCvOx + x, gCvOy + y, w, h);
  }

// Small square ON/OFF used per filter row to add or remove its chart overlay.
// Three states: lit (drawn), dark (available but off), and "--" for the
// oscillators that have no price-chart representation at all.
// Reads "ON" / "OFF" explicitly rather than a cryptic glyph, and is wide
// enough to hit comfortably with the mouse.

void PaintHud()
  {
   if(!ShowHUD)
     {
      DestroyHud(); DestroyTracker();
      gButtonCount = 0;
      ObjectsDeleteAll(0, PFX + "BTN_");   // no invisible click traps left behind
      return;
     }

   long chartW = 0, chartH = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chartW);
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chartH);

   int W = SC(430);
   if(W > (int)chartW - HudMargin * 2) W = (int)chartW - HudMargin * 2;
   if(W < SC(300)) { DestroyHud(); return; }

   int headerH = SC(54);
   // Each page owns its natural height, so no page shows dead space.
   // CORE height is the SUM of the panels actually switched on, so the
   // Show*Panel inputs genuinely remove their block instead of leaving a hole.
   int pageH = headerH + SC(6) + SC(32) + SC(34);     // header + tabs + control strip
   if(ShowSignalPanel)      pageH += SC(126) + SC(8); // agreement gauge
   if(ShowHeaderPanel)      pageH += SC(92)  + SC(8); // cost intelligence
   if(ShowPerformancePanel) pageH += SC(40)*2 + SC(6) + SC(8); // balance/equity chips
   if(ShowRiskPanel)        pageH += SC(112) + SC(8); // execution console
   if(ShowTradePanel)       pageH += SC(74)  + SC(8); // live trade ticket
   if(gHudPage == 1)
     {
      // BREAKOUT page: range card + state strip + distance meter +
      // the 8-gate checklist + the footer buttons. Summed, never guessed.
      pageH = headerH + SC(6) + SC(32)      // header + tab row
              + SC(96) + SC(8)              // range card
              + SC(54) + SC(8)              // state strip
              + SC(64) + SC(8)              // distance meter
              + SC(30) + BK_GATES * SC(20) + SC(10) + SC(8)  // checklist
              + SC(46) + SC(8);             // footer buttons
     }
   int H = gHudCollapsed ? headerH + SC(8) : pageH;
   if(H > (int)chartH - HudMargin * 2) H = (int)chartH - HudMargin * 2;
   if(H < headerH + SC(8)) return;

   if(!EnsureHud(W, H)) return;
   gButtonCount = 0;                 // PaintHud always repaints first
   gCv   = gHud;                     // route primitives to the HUD bitmap
   gCvOx = HudMargin;
   gCvOy = HudMargin;
   gCv.Erase(A(C'0,0,0', 0));

   //================= shell =================
   RaisedPlate(0, 0, W, H, SC(12), TBg, TBorder, false, 0);
   GradientRect(3, 3, W - 6, headerH - 5, TPanelHi, TBg2);
   gCv.Line(SC(10), headerH - 1, W - SC(10), headerH - 1, TAccent);
   gCv.Line(SC(10), headerH,     W - SC(10), headerH,     TDark);

   //================= header =================
   // Header is laid out RIGHT-TO-LEFT from the window edge, and the PRO badge
   // is positioned from the MEASURED width of the wordmark (CCanvas::TextWidth)
   // rather than a hardcoded offset - hardcoding it made the badge land on top
   // of the wordmark whenever the installed font metrics differed from mine.
   int hx = SC(14), hy = SC(10);
   gCv.FillCircle(hx + SC(10), hy + SC(14), SC(11), TAccent2);
   gCv.FillCircle(hx + SC(10), hy + SC(14), SC(7),  TBg);
   gCv.FillCircle(hx + SC(10), hy + SC(14), SC(3),  TAccent);

   int txtX = hx + SC(28);
   string mark = "BREAKOUT FORGE";
   gCv.FontSet("Segoe UI Black", SC(11) * -10, SF_FW_BLACK);
   int markW = gCv.TextWidth(mark);
   Text(txtX, hy, mark, TText, 11, "Segoe UI Black", SF_FW_BLACK);

   // right cluster: [collapse] [state pill], both anchored to the right edge
   string st = StateText();
   int pillW = SC(92), pillH = SC(22);
   int pillX = W - pillW - SC(12);
   int colW  = SC(28);
   int colX  = pillX - colW - SC(7);

   int badgeW = SC(32), badgeH = SC(14);
   int badgeX = txtX + markW + SC(7);
   if(badgeX + badgeW < colX - SC(6))
     {
      RoundRect(badgeX, hy + SC(2), badgeW, badgeH, SC(3), TAccent, TAccent);
      TextBoxCenter(badgeX, hy + SC(2), badgeW, badgeH, "BK", A(C'6,10,18',255), 7,
                    "Segoe UI Black", SF_FW_BLACK);
     }

   Text(txtX, hy + SC(18), Symbol() + "  ·  M" + IntegerToString(Period()) +
        "  ·  RAW  ·  v1.04", TTextDim, 7);

   RaisedPlate(pillX, hy + SC(3), pillW, pillH, SC(10), TPanelHi, StateColor(), true, 1);
   StatusDot(pillX + SC(12), hy + SC(14), SC(4), !gPaused, StateColor(), TGridC);
   TextBoxCenter(pillX + SC(18), hy + SC(3), pillW - SC(24), pillH, st, StateColor(), 7,
                 "Segoe UI Semibold", SF_FW_SEMI);

   DrawButton(colX, hy + SC(3), colW, pillH, "BTN_COLLAPSE",
              gHudCollapsed ? "+" : "–", false, TAccent);

   if(gHudCollapsed) { gCv.Update(); ChartRedraw(0); return; }

   int y = headerH + SC(6);
   int pad = SC(12);
   int innerW = W - pad * 2;

   //================= navigation tabs =================
   // Row layout: [ CORE ][ FILTERS ][ lang ][ theme ]
   // The two square buttons on the right switch the interface language and
   // the colour theme live, with no need to reopen the EA properties dialog.
   // Two pages: CORE | BREAKOUT, then the language and theme squares.
   // The tab width is derived from the counts, never hardcoded.
   int sqW   = SC(30);
   int tabW2 = (innerW - SC(8) * 3 - sqW * 2) / 2;
   int lx    = pad + (tabW2 + SC(8)) * 2;
   int tx    = lx + sqW + SC(8);
   // TRACKER is no longer a tab - it lives in its own top-right panel.
   DrawButton(pad,                   y, tabW2, SC(24), "TAB_CORE",     T("CORE"),     gHudPage == 0, TAccent);
   DrawButton(pad + tabW2 + SC(8),   y, tabW2, SC(24), "TAB_BREAKOUT", T("BREAKOUT"), gHudPage == 1, TAccent);
   // Language: shows the language you will switch TO, so the button always
   // reads in the script the user is about to get.
   DrawButton(lx, y, sqW, SC(24), "BTN_LANG",
              (gLang == SF_LANG_AR ? "EN" : "\x0639\x0631"), gLang == SF_LANG_AR, TAccent2);
   DrawButton(tx, y, sqW, SC(24), "BTN_SKIN",
              IntegerToString(gTheme + 1), false, TAccent2);
   y += SC(32);

   //================================================================
   //                        PAGE 0 : CORE
   //================================================================
   if(gHudPage == 0)
     {
      //---------- filter agreement gauge ----------
      if(ShowSignalPanel)
        {
        // Breakout status at a glance: where the range is, and how close
        // price is to the level that would actually fire a trade.
        int gaugeH = SC(126);
        RaisedPlate(pad, y, innerW, gaugeH, SC(10), TPanel, TBorder);
        AccentSpine(pad + SC(4), y + SC(7), SC(13), TAccent);
        Text(pad + SC(13), y + SC(6), T("BREAKOUT STATUS"), TText, 8, "Segoe UI Black", SF_FW_BLACK);

        uint stc = (gBkDir > 0) ? TBull : (gBkDir < 0) ? TBear : TFlat;
        string stt = BkStateText();
        TextBoxCenter(pad, y + SC(30), innerW, SC(30), stt, stc, 15,
                      "Segoe UI Black", SF_FW_BLACK);

        string sdir = (gBkDir > 0) ? T("UPSIDE") : (gBkDir < 0) ? T("DOWNSIDE")
                                                                : T("PRICE INSIDE RANGE");
        TextBoxCenter(pad, y + SC(60), innerW, SC(16), sdir, TTextDim, 7);

        // distance-to-trigger meter
        Text(pad + SC(12), y + SC(80), T("DISTANCE TO BREAK"), TAccent, 7);
        TextRight(pad + innerW - SC(12), y + SC(80),
                  DoubleToString(gBkDistPct, 0) + "%", TText, 7,
                  "Segoe UI Semibold", SF_FW_SEMI);
        Meter(pad + SC(12), y + SC(96), innerW - SC(24), SC(14),
              gBkDistPct / 100.0, (gBkDistPct > 85) ? TBull : TAccent, TBg2);
        y += gaugeH + SC(8);
        }

      //---------- cost intelligence ----------
      if(ShowHeaderPanel)
        {
        int costH = SC(92);
        RaisedPlate(pad, y, innerW, costH, SC(10), TPanel, TBorder);
        AccentSpine(pad + SC(4), y + SC(7), SC(13), TAccent2);
        Text(pad + SC(13), y + SC(6), T("COST INTELLIGENCE") + "  ·  " + T("RAW SPREAD"),
             TText, 8, "Segoe UI Black", SF_FW_BLACK);

        double spPts  = SpreadPoints();
        double cost   = TotalCostPoints();
        double atrP   = ATRPoints(1);
        double costPct= (atrP > 0) ? cost / atrP : 1.0;
        uint costCol  = (costPct < 0.12) ? TBull : (costPct < 0.25 ? TFlat : TBear);

        int col = innerW / 3;
        Text(pad + SC(12), y + SC(26), T("SPREAD"), TTextDim, 7);
        Text(pad + SC(12), y + SC(37), Fmt(spPts, 0) + " pts",
             (MaximumSpreadPoints <= 0 || spPts <= MaximumSpreadPoints) ? TText : TBear, 10, "Segoe UI Semibold", SF_FW_SEMI);

        Text(pad + SC(12) + col, y + SC(26), T("COMMISSION"), TTextDim, 7);
        Text(pad + SC(12) + col, y + SC(37), Fmt(gCostPointsRT, 0) + " pts", TText, 10, "Segoe UI Semibold", SF_FW_SEMI);

        Text(pad + SC(12) + col * 2, y + SC(26), "ROUND TURN", TTextDim, 7);
        Text(pad + SC(12) + col * 2, y + SC(37), Fmt(cost, 0) + " pts", costCol, 10, "Segoe UI Semibold", SF_FW_SEMI);

        Text(pad + SC(12), y + SC(57), "COST / ATR(" + IntegerToString(ATRLength) + ")", TTextDim, 7);
        TextRight(pad + innerW - SC(12), y + SC(57), Fmt(costPct * 100.0, 1) + "% of ATR", costCol, 7,
                  "Segoe UI Semibold", SF_FW_SEMI);
        Meter(pad + SC(12), y + SC(72), innerW - SC(24), SC(8), costPct * 4.0, costCol, TGridC);
        y += costH + SC(8);
        }

      //---------- account / equity chips ----------
      if(ShowPerformancePanel)
        {
        int chipH = SC(40), chipW = (innerW - SC(8)) / 2;
        double eq = AccountEquity(), bal = AccountBalance();
        double flt = eq - bal;
        DrawChip(pad, y, chipW, chipH, "BALANCE", "$" + Fmt(bal, 2), TText, TAccent);
        DrawChip(pad + chipW + SC(8), y, chipW, chipH, "EQUITY", "$" + Fmt(eq, 2),
                 flt >= 0 ? TBull : TBear, TAccent2);
        y += chipH + SC(6);
        DrawChip(pad, y, chipW, chipH, "FLOATING P/L", Signed(flt, 2),
                 flt > 0 ? TBull : (flt < 0 ? TBear : TText), flt >= 0 ? TBull : TBear);
        DrawChip(pad + chipW + SC(8), y, chipW, chipH, "DAY P/L",
                 Signed(DayPnLPercent(), 2) + "%",
                 DayPnLPercent() >= 0 ? TBull : TBear, TAccent);
        y += chipH + SC(8);
        }

      //---------- execution console ----------
      if(ShowRiskPanel)
        {
        // The original strategy carries no daily budget, so this panel reports
        // what the EA is actually configured to do on the next fill.
        int riskH = SC(112);
        RaisedPlate(pad, y, innerW, riskH, SC(10), TPanel, TBorder);
        AccentSpine(pad + SC(4), y + SC(7), SC(13), TFlat);
        Text(pad + SC(13), y + SC(6), T("EXECUTION CONSOLE"), TText, 8, "Segoe UI Black", SF_FW_BLACK);

        string slTxt = "ATR x " + Fmt(StopLossATR, 2);
        if(StopByRangeOpposite) slTxt = T("RANGE") + " / " + slTxt;
        string tpTxt = (TakeProfitMode == TP_By_ATR)
                       ? ("ATR x " + Fmt(TakeProfitATR, 2))
                       : (Fmt(TakeProfitPoints, 0) + " pts");

        Text(pad + SC(12), y + SC(26), T("STOP LOSS"), TTextDim, 7);
        TextRight(pad + innerW - SC(12), y + SC(26), slTxt, TText, 7, "Segoe UI Semibold", SF_FW_SEMI);

        Text(pad + SC(12), y + SC(42), T("TAKE PROFIT"), TTextDim, 7);
        TextRight(pad + innerW - SC(12), y + SC(42), tpTxt, TText, 7, "Segoe UI Semibold", SF_FW_SEMI);

        Text(pad + SC(12), y + SC(58), T("TRAILING"), TTextDim, 7);
        TextRight(pad + innerW - SC(12), y + SC(58),
                  EnableTrailingStop ? (Fmt(TrailingStartPoints, 0) + " / " +
                                        Fmt(TrailingDistancePoints, 0) + " pts")
                                     : "OFF",
                  EnableTrailingStop ? TBull : TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);

        // The lot is derived from the stop now, so show the RISK BUDGET and
        // the lot the next fill would actually use - a static FixedLots
        // readout would be a lie under risk sizing.
        string lotTxt;
        if(UseRiskSizing)
          {
           double pvAtr = iATR(NULL, 0, MathMax(1, ATRLength), 1) * MathMax(0.1, StopLossATR);
           double rUSD = 0; string rWhy = "";
           double nextLot = (pvAtr > 0) ? LotForRisk(pvAtr, rUSD, rWhy) : 0;
           lotTxt = T("RISK") + " $" + Fmt(RiskBudgetUSD(), 2) + "  ->  " +
                    ((nextLot > 0) ? Fmt(nextLot, 2) + " " + T("lots")
                                   : T("SKIP"));
          }
        else lotTxt = T("LOTS") + "  " + Fmt(FixedLots, 2);
        Text(pad + SC(12), y + SC(76), lotTxt, TTextDim, 7);
        TextRight(pad + innerW - SC(12), y + SC(76),
                  T("TRADES TODAY") + " " + IntegerToString(gDayTrades), TTextDim, 7,
                  "Segoe UI Semibold", SF_FW_SEMI);

        // spread headroom against the only hard gate v1 enforces
        double sprUse = (MaximumSpreadPoints > 0)
                        ? SpreadPoints() / (double)MaximumSpreadPoints : 0.0;
        Meter(pad + SC(12), y + SC(93), innerW - SC(24), SC(7), sprUse,
              sprUse > 0.9 ? TBear : (sprUse > 0.6 ? TFlat : TBull), TGridC);
        y += riskH + SC(8);
        }

      //---------- live trade ticket ----------
      if(ShowTradePanel)
        {
        int type = -1, ticket = -1;
        int open = CountOwnPositions(type, ticket);
        int tkH = SC(74);
        RaisedPlate(pad, y, innerW, tkH, SC(10), TPanel, TBorder);
        if(open > 0 && OrderSelect(ticket, SELECT_BY_TICKET))
          {
           uint sideC = (OrderType() == OP_BUY) ? TBull : TBear;
           string side = (OrderType() == OP_BUY) ? "LONG" : "SHORT";
           RoundRect(pad + SC(10), y + SC(10), SC(56), SC(20), SC(5), sideC, sideC);
           TextCenter(pad + SC(38), y + SC(13), side, A(C'6,10,18',255), 8, "Segoe UI Black", SF_FW_BLACK);
           Text(pad + SC(74), y + SC(12), Fmt(OrderLots(), 2) + " lots @ " + Fmt(OrderOpenPrice(), gDigits),
                TText, 8, "Segoe UI Semibold", SF_FW_SEMI);
           double pnl = OrderProfit() + OrderSwap() + OrderCommission();
           TextRight(pad + innerW - SC(12), y + SC(11), Signed(pnl, 2),
                     pnl >= 0 ? TBull : TBear, 11, "Segoe UI Black", SF_FW_BLACK);
           int c3 = (innerW - SC(20)) / 3;
           Text(pad + SC(12),          y + SC(38), "SL", TTextDim, 7);
           Text(pad + SC(12),          y + SC(48), OrderStopLoss() > 0 ? Fmt(OrderStopLoss(), gDigits) : "--", TBear, 8);
           Text(pad + SC(12) + c3,     y + SC(38), "TP", TTextDim, 7);
           Text(pad + SC(12) + c3,     y + SC(48), OrderTakeProfit() > 0 ? Fmt(OrderTakeProfit(), gDigits) : "--", TBull, 8);
           Text(pad + SC(12) + c3 * 2, y + SC(38), T("BREAK-EVEN"), TTextDim, 7);
           Text(pad + SC(12) + c3 * 2, y + SC(48),
                Fmt(BreakEvenPrice(OrderType(), OrderOpenPrice(), OrderLots()), gDigits), TAccent, 8);
        }
      else
        {
         TextCenter(pad + innerW / 2, y + SC(16), T("NO OPEN POSITION"), TTextDim, 9, "Segoe UI Semibold", SF_FW_SEMI);
         TextCenter(pad + innerW / 2, y + SC(34),
                    BkStateText() + "   ·   " +
                    (gBlockReason == "" ? T("SCANNING") : gBlockReason), TTextDim, 7);
         double atrNow = ATRPoints(1);
         TextCenter(pad + innerW / 2, y + SC(50),
                    "ATR " + Fmt(atrNow, 0) + " " + T("pts") + "   ·   " + T("REGIME") + " " +
                    Fmt(ATRRatio(1), 2) + "x", TTextDim, 7);
        }
      y += tkH + SC(8);
        }

      //---------- control strip ----------
      int bw = (innerW - SC(16)) / 3;
      DrawButton(pad,                    y, bw, SC(26), "BTN_PAUSE",
                 gPaused ? T("RESUME") : T("PAUSE"), gPaused, TFlat);
      DrawButton(pad + bw + SC(8),       y, bw, SC(26), "BTN_CLOSE", T("CLOSE ALL"), false, TBear);
      DrawButton(pad + (bw + SC(8)) * 2, y, bw, SC(26), "BTN_THEME", T("RANGE BOX"),
                 gShowRangeBox, TAccent2);
     }

   //================================================================
   //                      PAGE 1 : FILTERS
   //================================================================
   else if(gHudPage == 1)
     {
      //---- the range itself -------------------------------------
      RaisedPlate(pad, y, innerW, SC(96), SC(8), TPanel, TBorder, true, 1);
      TextVC(pad + SC(12), y, SC(24), T("SESSION RANGE"), TAccent, 7,
             "Segoe UI Black", SF_FW_BLACK);
      // Mode badge so it is never ambiguous which range is on screen.
      string mode = (RangeMode == BK_RANGE_DONCHIAN)
                    ? T("DONCHIAN") + " " + IntegerToString(MathMax(2, DonchianBars))
                    : T("SESSION") + " " + IntegerToString(RangeStartHour) + "-" +
                      IntegerToString(RangeEndHour);
      TextRight(pad + innerW - SC(12), y + SC(7), mode, TTextDim, 7);

      int rY = y + SC(30);
      if(gBkValid)
        {
         Text(pad + SC(12), rY, T("HIGH"), TTextDim, 7);
         TextRight(pad + innerW - SC(12), rY, DoubleToString(gBkHigh, Digits),
                   TBull, 9, "Segoe UI Semibold", SF_FW_SEMI);
         Text(pad + SC(12), rY + SC(21), T("LOW"), TTextDim, 7);
         TextRight(pad + innerW - SC(12), rY + SC(21), DoubleToString(gBkLow, Digits),
                   TBear, 9, "Segoe UI Semibold", SF_FW_SEMI);
         Text(pad + SC(12), rY + SC(42), T("WIDTH"), TTextDim, 7);
         // ...and the number the width gate actually judges, with the window
         // it has to fall inside, so a rejection is never a mystery.
         Text(pad + SC(12) + SC(52), rY + SC(43),
              "x" + DoubleToString(gBkRatio, 2) + "  (" +
              DoubleToString(MinRangeATRMult, 2) + "-" +
              DoubleToString(MaxRangeATRMult, 2) + ")", TTextDim, 7);
         TextRight(pad + innerW - SC(12), rY + SC(42),
                   DoubleToString((gBkHigh - gBkLow) / gPoint, 0) + T("p"),
                   TText, 9, "Segoe UI Semibold", SF_FW_SEMI);
        }
      else if(gBkForming && gBkFormHigh > gBkFormLow)
        {
         // The window is still open: show what has been collected so far so
         // the panel and the dotted box on the chart tell the same story.
         Text(pad + SC(12), rY, T("HIGH"), TTextDim, 7);
         TextRight(pad + innerW - SC(12), rY, DoubleToString(gBkFormHigh, Digits),
                   TTextDim, 9, "Segoe UI Semibold", SF_FW_SEMI);
         Text(pad + SC(12), rY + SC(21), T("LOW"), TTextDim, 7);
         TextRight(pad + innerW - SC(12), rY + SC(21), DoubleToString(gBkFormLow, Digits),
                   TTextDim, 9, "Segoe UI Semibold", SF_FW_SEMI);
         Text(pad + SC(12), rY + SC(42), T("COLLECTING"), TTextDim, 7);
         TextRight(pad + innerW - SC(12), rY + SC(42),
                   DoubleToString((gBkFormHigh - gBkFormLow) / gPoint, 0) + T("p"),
                   TAccent, 9, "Segoe UI Semibold", SF_FW_SEMI);
        }
      else
        {
         // A range exists but failed the width gate: show the measurement
         // that rejected it rather than a dead end.
         if(gBkHigh > gBkLow && gBkRatio > 0)
           {
            TextVC(pad + SC(12), rY, SC(21),
                   (gBkRatio > MaxRangeATRMult) ? T("RANGE TOO WIDE")
                                                : T("RANGE TOO TIGHT"),
                   TWarn, 8, "Segoe UI Semibold", SF_FW_SEMI);
            Text(pad + SC(12), rY + SC(24), T("WIDTH"), TTextDim, 7);
            TextRight(pad + innerW - SC(12), rY + SC(24),
                      DoubleToString((gBkHigh - gBkLow) / gPoint, 0) + T("p"),
                      TTextDim, 8, "Segoe UI Semibold", SF_FW_SEMI);
            // Name the test that actually failed: the relative ratio or the
            // absolute points floor.
            bool absFail = (MinRangePoints > 0 &&
                            (gBkHigh - gBkLow) / gPoint < MinRangePoints);
            Text(pad + SC(12), rY + SC(44),
                 absFail ? ("< " + DoubleToString(MinRangePoints, 0) + T("p") +
                            " " + T("minimum"))
                         : ("x" + DoubleToString(gBkRatio, 2) + " " + T("of") + " " +
                            DoubleToString(MinRangeATRMult, 2) + "-" +
                            DoubleToString(MaxRangeATRMult, 2)), TWarn, 7);
            TextRight(pad + innerW - SC(12), rY + SC(44),
                      IntegerToString(gBkBars) + " " + T("bars"), TTextDim, 7);
           }
         else
            TextVC(pad + SC(12), rY, SC(42), T("NO VALID RANGE"), TTextDim, 8,
                   "Segoe UI Semibold", SF_FW_SEMI);
        }
      y += SC(96) + SC(8);

      //---- state strip -------------------------------------------
      // Named bkSt, not st: PaintHud() already has a function-scope `st`
      // for the header pill, and MQL4 warns on the shadowing.
      string bkSt = BkStateText();
      uint stc;
      if(gBkState == BK_TRADED || gBkState == BK_RETEST) stc = TAccent2;
      else if(gBkState == BK_BROKEN)                     stc = (gBkDir > 0) ? TBull : TBear;
      else if(gBkValid)                                  stc = TAccent;
      else                                               stc = TTextDim;
      RaisedPlate(pad, y, innerW, SC(54), SC(8), TPanelHi, stc, true, 1);
      TextBoxCenter(pad, y + SC(4), innerW, SC(26), bkSt, stc, 11,
                    "Segoe UI Black", SF_FW_BLACK);
      string sub;
      if(gBkGateFail != "")                   sub = gBkGateFail;
      else if(gBkDir > 0)                     sub = T("UPSIDE");
      else if(gBkDir < 0)                     sub = T("DOWNSIDE");
      else if(gBkForming)                     sub = T("COLLECTING");
      else                                    sub = T("PRICE INSIDE RANGE");
      if(gBkFailedBreaks > 0)
         sub = sub + "   ·   " + IntegerToString(gBkFailedBreaks) + " " + T("FAILED BREAKS");
      TextBoxCenter(pad, y + SC(30), innerW, SC(18), sub, TTextDim, 7);
      y += SC(54) + SC(8);

      //---- distance to the trigger --------------------------------
      RaisedPlate(pad, y, innerW, SC(64), SC(8), TPanel, TBorder, true, 1);
      TextVC(pad + SC(12), y, SC(24), T("DISTANCE TO BREAK"), TAccent, 7,
             "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(12), y + SC(7),
                DoubleToString(gBkDistPct, 0) + "%", TText, 7);
      Meter(pad + SC(12), y + SC(34), innerW - SC(24), SC(14), gBkDistPct / 100.0,
            (gBkDistPct > 85) ? TBull : TAccent, TBg2);
      y += SC(64) + SC(8);

      //---- the eight gates ----------------------------------------
      SunkenWell(pad, y, innerW, SC(26), SC(6), TBg2);
      TextVC(pad + SC(10), y, SC(26), T("ENTRY CHECKLIST"), TAccent, 7,
             "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(10), y + SC(8),
                IntegerToString(BkGatesPassed()) + " / " + IntegerToString(BK_GATES),
                TTextDim, 7);
      y += SC(30);
      for(int g = 0; g < BK_GATES; g++)
        {
         uint gc = gBkGate[g] ? TBull : TTextDim;
         StatusDot(pad + SC(14), y + SC(9), SC(4), gBkGate[g], TBull, TGridC);
         Text(pad + SC(26), y + SC(3), T(BkGateName(g)), TText, 7);
         TextRight(pad + innerW - SC(12), y + SC(3),
                   gBkGate[g] ? T("OK") : T("WAIT"), gc, 7,
                   "Segoe UI Semibold", SF_FW_SEMI);
         y += SC(20);
        }
      y += SC(10);

      //---- footer -------------------------------------------------
      int bw3 = (innerW - SC(8)) / 2;
      DrawButton(pad, y, bw3, SC(26), "BTN_PAUSE",
                 gPaused ? T("RESUME") : T("PAUSE"), gPaused, TFlat);
      DrawButton(pad + bw3 + SC(8), y, bw3, SC(26), "BTN_CLOSE",
                 T("CLOSE ALL"), false, TBear);
     }

   gCv.Update();
  }

//==================================================================//
//        S T A N D A L O N E   T R A C K E R   P A N E L           //
//==================================================================//
// The performance tracker is no longer a tab inside the HUD: it is its own
// bitmap pinned to the TOP-RIGHT corner, so the trader sees the running
// P/L at the same time as the signal engine on the left.
void PaintTracker()
  {
   if(!ShowHUD || !ShowTrackerPanel) { DestroyTracker(); return; }

   long chartW = 0, chartH = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS,  0, chartW);
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chartH);

   int W = SC(TrackerWidthPx);
   // never let the two panels collide: the HUD owns the left side
   int leftTaken = (gHudReady ? HudMargin + gHudW : 0) + SC(10);
   int avail     = (int)chartW - leftTaken - HudMargin;
   if(W > avail) W = avail;
   if(W < SC(240)) { DestroyTracker(); return; }

   int headerH = SC(34);
   // Fixed content = KPI strip + 6-day table + FINAL P/L + pause button.
   // Below this the blocks would collide, so the panel hides instead of
   // drawing a broken layout. The sparkline takes whatever is left over.
   int minH = headerH + SC(8) + SC(52) + SC(8)
              + SC(26) + SC(20) + SF_TRACK_DAYS * SC(21) + SC(24) + SC(8)
              + SC(46) + SC(8) + SC(40);
   int H = gTrkCollapsed ? headerH + SC(8) : SC(TrackerHeightPx);
   if(H > (int)chartH - HudMargin * 2) H = (int)chartH - HudMargin * 2;
   if(!gTrkCollapsed && H < minH)      { DestroyTracker(); return; }
   if(H < headerH + SC(8))             { DestroyTracker(); return; }

   if(!EnsureTracker(W, H)) return;

   // route every primitive to the tracker canvas, and tell RegisterButton
   // where this panel sits on screen so its buttons hit-test correctly
   gCv  = gTrk;
   gCvOx = (int)chartW - HudMargin - W;
   gCvOy = HudMargin;

   // Erase fully TRANSPARENT (same as the HUD): the rounded shell is then
   // drawn on top, so the corners stay round instead of being squared off by
   // an opaque background. TBg is already a packed ARGB uint, not a `color`.
   gCv.Erase(A(C'0,0,0', 0));
   RaisedPlate(0, 0, W, H, SC(12), TBg, TBorder, false, 0);

   int pad = SC(10);
   int innerW = W - pad * 2;

   //---------- header ----------
   // inset like the HUD header, otherwise the square gradient paints over
   // the rounded top corners of the shell
   GradientRect(3, 3, W - 6, headerH - 5, TPanelHi, TBg2);
   AccentSpine(pad, SC(9), headerH - SC(18), TAccent2);
   Text(pad + SC(10), SC(7), T("PERFORMANCE TRACKER"), TText, 9, "Segoe UI Black", SF_FW_BLACK);
   TextRight(W - pad - SC(30), SC(9), Symbol(), TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
   DrawButton(W - pad - SC(22), SC(7), SC(22), SC(19), "TRK_COLLAPSE",
              gTrkCollapsed ? "+" : "-", false, TAccent);
   gCv.Line(SC(10), headerH - 1, W - SC(10), headerH - 1, TAccent);
   gCv.Line(SC(10), headerH,     W - SC(10), headerH,     TDark);

   if(gTrkCollapsed) { gCv.Update(); return; }

   int y = headerH + SC(8);

   RebuildStats();

   //---------- headline KPI strip ----------
   double wr = (gStatTrades > 0) ? 100.0 * gStatWins / gStatTrades : 0;
   double pf = (gStatGL > 0) ? gStatGP / gStatGL : (gStatGP > 0 ? 99.9 : 0);
   int kpiH = SC(52);
   int kw = (innerW - SC(12)) / 4;
   string klbl[4];
   klbl[0]=T("TRADES"); klbl[1]=T("WIN RATE"); klbl[2]=T("P/FACTOR"); klbl[3]=T("MAX DD");
   string kval[4];
   kval[0] = IntegerToString(gStatTrades);
   kval[1] = Fmt(wr, 1) + "%";
   kval[2] = (pf >= 99.9 ? "MAX" : Fmt(pf, 2));
   kval[3] = Fmt(gStatMaxDD, 1) + "%";
   uint kcol[4];
   kcol[0] = TAccent;
   kcol[1] = (wr >= 50 ? TBull : TBear);
   kcol[2] = (pf >= 1.0 ? TBull : TBear);
   kcol[3] = (gStatMaxDD <= 15 ? TBull : TBear);
   for(int k = 0; k < 4; k++)
     {
      int kx = pad + k * (kw + SC(4));
      RaisedPlate(kx, y, kw, kpiH, SC(6), TPanel, TBorder);
      AccentSpine(kx + SC(3), y + SC(6), kpiH - SC(12), kcol[k]);
      Text(kx + SC(11), y + SC(8),  klbl[k], TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
      Text(kx + SC(11), y + SC(23), kval[k], kcol[k], 13, "Segoe UI Black", SF_FW_BLACK);
     }
   y += kpiH + SC(8);

   //---------- DAILY PERFORMANCE TRACKER TABLE ----------
   int hdrH = SC(20), rowH = SC(21);
   int tblH = SC(26) + hdrH + SF_TRACK_DAYS * rowH + SC(24);
   RaisedPlate(pad, y, innerW, tblH, SC(8), TPanel, TBorder);
   AccentSpine(pad + SC(4), y + SC(7), SC(13), TAccent);
   Text(pad + SC(13), y + SC(6), T("PERFORMANCE TRACKER"), TText, 8, "Segoe UI Black", SF_FW_BLACK);
   TextRight(pad + innerW - SC(10), y + SC(7),
             T("LAST") + " " + IntegerToString(SF_TRACK_DAYS) + " " + T("DAYS"),
             TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);

   // column layout: DATE | LOTS | PROFIT | GAIN% | WIN% | COMM
   int tx = pad + SC(6), tw = innerW - SC(12);
   int cW[6];
   cW[0] = (int)(tw * 0.21); // DATE
   cW[1] = (int)(tw * 0.13); // LOTS
   cW[2] = (int)(tw * 0.20); // PROFIT
   cW[3] = (int)(tw * 0.17); // GAIN%
   cW[4] = (int)(tw * 0.15); // WIN%
   cW[5] = tw - cW[0] - cW[1] - cW[2] - cW[3] - cW[4]; // COMM
   string cH[6];
   cH[0]=T("DATE"); cH[1]=T("LOTS"); cH[2]=T("PROFIT");
   cH[3]=T("GAIN%"); cH[4]=T("WIN%"); cH[5]=T("COMM");

   int hy2 = y + SC(26);
   SunkenWell(tx, hy2, tw, hdrH, SC(3), TBg2);
   int cx2 = tx;
   for(int c = 0; c < 6; c++)
     {
      if(c == 0) TextVC(cx2 + SC(6), hy2, hdrH, cH[c], TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
      else TextRight(cx2 + cW[c] - SC(6), hy2 + SC(6), cH[c], TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
      cx2 += cW[c];
     }

   int ry = hy2 + hdrH;
   for(int r2 = 0; r2 < SF_TRACK_DAYS; r2++)
     {
      bool isToday = (r2 == 0);
      uint rowBg = isToday ? TPanelHi : ((r2 % 2 == 0) ? TBg2 : TPanel);
      RoundRect(tx, ry, tw, rowH - 1, SC(2), rowBg, rowBg, false);
      if(isToday) AccentSpine(tx + 1, ry + SC(3), rowH - SC(7), TAccent);

      double prof = gTrkProfit[r2];
      uint pcol = (prof > 0) ? TBull : (prof < 0 ? TBear : TTextDim);
      double dwr = (gTrkTrades[r2] > 0) ? 100.0 * gTrkWins[r2] / gTrkTrades[r2] : 0;
      bool had = (gTrkTrades[r2] > 0);

      string v0 = TimeToString(gTrkDate[r2], TIME_DATE);
      // trim year for width: yyyy.mm.dd -> mm.dd
      if(StringLen(v0) > 5) v0 = StringSubstr(v0, 5);
      if(isToday) v0 = v0 + "  *";
      string v1 = had ? Fmt(gTrkLots[r2], 2) : "-";
      string v2 = had ? Signed(prof, 2) : "-";
      string v3 = had ? Signed(gTrkGainPct[r2], 2) + "%" : "-";
      string v4 = had ? Fmt(dwr, 0) + "%" : "-";
      string v5 = had ? "-" + Fmt(gTrkComm[r2], 2) : "-";

      uint c4 = !had ? TTextDim : (dwr >= 50 ? TBull : TBear);
      cx2 = tx;
      Text(cx2 + SC(6), ry + SC(5), v0, isToday ? TText : TTextDim, 7,
           "Segoe UI Semibold", SF_FW_SEMI);
      cx2 += cW[0];
      TextRight(cx2 + cW[1] - SC(6), ry + SC(5), v1, TText, 7, "Segoe UI Semibold", SF_FW_SEMI);
      cx2 += cW[1];
      TextRight(cx2 + cW[2] - SC(6), ry + SC(4), v2, pcol, 8, "Segoe UI Black", SF_FW_BLACK);
      cx2 += cW[2];
      TextRight(cx2 + cW[3] - SC(6), ry + SC(5), v3, pcol, 7, "Segoe UI Semibold", SF_FW_SEMI);
      cx2 += cW[3];
      TextRight(cx2 + cW[4] - SC(6), ry + SC(5), v4, c4, 7, "Segoe UI Semibold", SF_FW_SEMI);
      cx2 += cW[4];
      TextRight(cx2 + cW[5] - SC(6), ry + SC(5), v5, TWarn, 7, "Segoe UI Semibold", SF_FW_SEMI);
      ry += rowH;
     }

   // ---- TOTAL row ----
   SunkenWell(tx, ry + SC(2), tw, SC(19), SC(3), TBg);
   cx2 = tx;
   Text(cx2 + SC(6), ry + SC(6), T("TOTAL"), TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
   cx2 += cW[0];
   double sumLots = 0, sumComm = 0;
   for(int a2 = 0; a2 < SF_TRACK_DAYS; a2++) { sumLots += gTrkLots[a2]; sumComm += gTrkComm[a2]; }
   TextRight(cx2 + cW[1] - SC(6), ry + SC(6), Fmt(sumLots, 2), TText, 7, "Segoe UI Black", SF_FW_BLACK);
   cx2 += cW[1];
   TextRight(cx2 + cW[2] - SC(6), ry + SC(5), Signed(gStatNet, 2),
             gStatNet >= 0 ? TBull : TBear, 8, "Segoe UI Black", SF_FW_BLACK);
   cx2 += cW[2];
   double gainBase = (gAcctStart > 0) ? gAcctStart : gTrkStartBal;
   double totGain  = (gainBase > 0) ? gStatNet / gainBase * 100.0 : 0;
   TextRight(cx2 + cW[3] - SC(6), ry + SC(6), Signed(totGain, 2) + "%",
             gStatNet >= 0 ? TBull : TBear, 7, "Segoe UI Black", SF_FW_BLACK);
   cx2 += cW[3];
   TextRight(cx2 + cW[4] - SC(6), ry + SC(6), Fmt(wr, 0) + "%",
             wr >= 50 ? TBull : TBear, 7, "Segoe UI Black", SF_FW_BLACK);
   cx2 += cW[4];
   TextRight(cx2 + cW[5] - SC(6), ry + SC(6), "-" + Fmt(gStatCommission, 2), TWarn, 7,
             "Segoe UI Black", SF_FW_BLACK);
   y += tblH + SC(8);

   //---------- FINAL P/L ----------
   // This is the headline number, so it reports the ACCOUNT, not this EA's
   // filtered slice of it. Showing the magic-filtered figure here is what
   // made a demo that went 200.00 -> 157.79 display "+11.03": the trades
   // that lost the money carried a different magic and were skipped.
   int flH = SC(46);
   double acctPL   = AccountBalance() - gAcctStart;   // the truth
   double gross    = gStatNet + gStatCommission;
   bool   acctUp   = (acctPL >= 0);
   RaisedPlate(pad, y, innerW, flH, SC(8),
               acctUp ? TBullDeep : TBearDeep, acctUp ? TBull : TBear);
   AccentSpine(pad + SC(4), y + SC(8), flH - SC(16), acctUp ? TBull : TBear);
   Text(pad + SC(13), y + SC(6), T("ACCOUNT P/L"), TText, 7,
        "Segoe UI Semibold", SF_FW_SEMI);
   Text(pad + SC(13), y + SC(20), Signed(acctPL, 2) + "  USD",
        acctUp ? TBull : TBear, 15, "Segoe UI Black", SF_FW_BLACK);
   // right column: where that number comes from, so the two can never
   // silently disagree again
   TextRight(pad + innerW - SC(12), y + SC(6), T("START") + " " + Fmt(gAcctStart, 2),
             TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
   TextRight(pad + innerW - SC(12), y + SC(18), T("BAL") + " " + Fmt(AccountBalance(), 2),
             TText, 8, "Segoe UI Black", SF_FW_BLACK);
   TextRight(pad + innerW - SC(12), y + SC(31),
             T("THIS EA") + " " + Signed(gStatNet, 2) + "  " +
             T("FEES") + " -" + Fmt(gStatCommission, 2),
             gStatNet >= 0 ? TBull : TWarn, 7, "Segoe UI Semibold", SF_FW_SEMI);
   y += flH + SC(8);

   //---------- equity sparkline ----------
   int sparkH = H - y - SC(40);
   if(sparkH >= SC(54))
     {
      RaisedPlate(pad, y, innerW, sparkH, SC(8), TPanel, TBorder);
      AccentSpine(pad + SC(4), y + SC(7), SC(12), TAccent2);
      Text(pad + SC(13), y + SC(6), T("EQUITY CURVE"), TText, 7, "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(10), y + SC(6),
                T("TODAY") + " " + Signed(gStatToday, 2) + "   " + T("WK") + " " + Signed(gStatWeek, 2) +
                "   " + T("MO") + " " + Signed(gStatMonth, 2), TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
      SunkenWell(pad + SC(8), y + SC(21), innerW - SC(16), sparkH - SC(29), SC(4), TBg);
      Sparkline(pad + SC(12), y + SC(25), innerW - SC(24), sparkH - SC(37),
                gStatNet >= 0 ? TBull : TBear, TGridC);
      y += sparkH + SC(6);
     }

   // distinct id from the HUD's pause button, otherwise both would light up
   // together on hover (HitButton returns the first match)
   DrawButton(pad, H - SC(34), innerW, SC(26), "TRK_PAUSE",
              gPaused ? T("RESUME TRADING") : T("PAUSE TRADING"), gPaused, TFlat);
   gCv.Update();
  }

// Repaint both panels in the right order: PaintHud() clears the shared button
// registry, so the tracker must register its own buttons afterwards.
void PaintAll()
  {
   PaintHud();
   PaintTracker();
   // Both panels have re-registered their buttons, so any control object left
   // over belongs to something no longer on screen (a collapsed panel, the
   // other tab's rows). Deleting them is what makes collapse actually hide
   // the buttons instead of leaving them floating over the chart.
  }

//==================================================================//
//              C H A R T   V I S U A L S                           //
//==================================================================//

// True once this symbol/period actually has usable data. iMA() on a partially
// downloaded series returns 0.0, which silently produces invisible plots.
void SetLevelLine(string id, double price, color c, int style, int width, string txt)
  {
   string n = PFX + "LVL_" + id;
   if(price <= 0) { ObjectDelete(0, n); return; }
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, n, OBJPROP_PRICE1, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

// Draw the live range: the box itself, and the two buffered trigger lines
// that are the levels the EA actually reacts to. Seeing the buffer is the
// point - it explains at a glance why a wick that pierced the box was not
// a trade.
// One buffered trigger line. Created once, then only moved, so the chart
// does not flicker on every tick.
void SetRangeLine(string id, double price, color c)
  {
   if(price <= 0) { ObjectDelete(0, id); return; }
   if(ObjectFind(0, id) < 0)
     {
      ObjectCreate(0, id, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, id, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, id, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, id, OBJPROP_BACK, true);
      ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
     }
   ObjectSetDouble(0, id, OBJPROP_PRICE, price);
   ObjectSetInteger(0, id, OBJPROP_COLOR, c);
  }

// ---- HISTORICAL RANGES --------------------------------------------
// Each archived range gets its own permanent rectangle (plus an optional
// label), keyed by index so it is created once and never moved. A range
// that produced a trade is tinted with the accent colour; one that failed
// the width gate is drawn dim and hollow, so a glance at the chart shows
// which setups the engine accepted and which it threw away.
// ---- PERMANENT TRADE MARKERS ---------------------------------------
// The result CARDS are pixel-anchored and capped at MaxResultPills, so on a
// long run most trades have no lasting record on the chart. These are
// price-anchored trend segments from entry to exit - one per closed trade,
// green for a winner, red for a loser - which survive scrolling and are not
// capped. This is what makes a whole backtest reviewable afterwards.
void DrawTradeHistoryMarkers()
  {
   if(!KeepAllTradeMarkers)
     {
      ObjectsDeleteAll(0, PFX + "TH_");
      return;
     }

   // Only rebuild when the history actually changed. These are price-anchored
   // objects, so unlike the pixel-anchored cards they do NOT need redrawing
   // on scroll or zoom - MT4 keeps them attached to their bars.
   int total = OrdersHistoryTotal();
   if(total == gKnownMarkerHistory) return;
   gKnownMarkerHistory = total;

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      datetime ot = OrderOpenTime(), ct = OrderCloseTime();
      if(ct <= 0 || ot <= 0) continue;

      string tag = IntegerToString(OrderTicket());
      string idS = PFX + "TH_S" + tag;      // entry -> exit segment
      string idE = PFX + "TH_E" + tag;      // entry arrow
      string idX = PFX + "TH_X" + tag;      // exit arrow

      double net = OrderProfit() + OrderSwap() + OrderCommission();
      uint   col = (net >= 0) ? TBull : TBear;

      if(ObjectFind(0, idS) < 0)
        {
         ObjectCreate(0, idS, OBJ_TREND, 0, ot, OrderOpenPrice(), ct, OrderClosePrice());
         ObjectSetInteger(0, idS, OBJPROP_RAY, false);
         ObjectSetInteger(0, idS, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, idS, OBJPROP_BACK, false);
         ObjectSetInteger(0, idS, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, idS, OBJPROP_HIDDEN, true);
         ObjectMove(0, idS, 0, ot, OrderOpenPrice());
         ObjectMove(0, idS, 1, ct, OrderClosePrice());
        }
      ObjectSetInteger(0, idS, OBJPROP_COLOR, CLR(col));
      ObjectSetInteger(0, idS, OBJPROP_STYLE, (net >= 0) ? STYLE_SOLID : STYLE_DOT);

      if(ObjectFind(0, idE) < 0)
        {
         ObjectCreate(0, idE, OBJ_ARROW, 0, ot, OrderOpenPrice());
         ObjectSetInteger(0, idE, OBJPROP_ARROWCODE,
                          (OrderType() == OP_BUY) ? 233 : 234);
         ObjectSetInteger(0, idE, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, idE, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, idE, OBJPROP_HIDDEN, true);
         ObjectMove(0, idE, 0, ot, OrderOpenPrice());
        }
      ObjectSetInteger(0, idE, OBJPROP_COLOR,
                       CLR((OrderType() == OP_BUY) ? TBull : TBear));

      if(ObjectFind(0, idX) < 0)
        {
         ObjectCreate(0, idX, OBJ_ARROW, 0, ct, OrderClosePrice());
         ObjectSetInteger(0, idX, OBJPROP_ARROWCODE, 251);   // cross
         ObjectSetInteger(0, idX, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, idX, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, idX, OBJPROP_HIDDEN, true);
         ObjectMove(0, idX, 0, ct, OrderClosePrice());
        }
      ObjectSetInteger(0, idX, OBJPROP_COLOR, CLR(col));
      // The tooltip carries the numbers, so hovering a marker in the tester
      // reports the trade without needing the card.
      ObjectSetString(0, idX, OBJPROP_TOOLTIP,
                      "#" + tag + "  " + DoubleToString(OrderLots(), 2) + " lots  " +
                      DoubleToString(net, 2) + " USD");
     }
  }

void DrawRangeHistory()
  {
   if(!gShowRangeBox || !KeepRangeHistory)
     {
      ObjectsDeleteAll(0, PFX + "HRNG_");
      ObjectsDeleteAll(0, PFX + "HLBL_");
      return;
     }

   int have = ArchivedRanges();
   int show = (MaxRangeHistory > 0) ? MathMin(have, MaxRangeHistory) : have;

   for(int nth = 0; nth < show; nth++)
     {
      int k = ArchivedSlot(nth);
      if(k < 0) continue;
      if(gRngHigh[k] <= gRngLow[k]) continue;

      // Key on the range's own start time: stable even as the ring wraps,
      // so a box is never redrawn in the wrong place.
      string tag = IntegerToString((int)gRngStart[k]);
      string idB = PFX + "HRNG_" + tag;

      datetime t1 = gRngStart[k];
      datetime t2 = (gRngEnd[k] > t1) ? gRngEnd[k] : (t1 + PeriodSeconds() * 10);

      if(ObjectFind(0, idB) < 0)
        {
         ObjectCreate(0, idB, OBJ_RECTANGLE, 0, t1, gRngHigh[k], t2, gRngLow[k]);
         ObjectSetInteger(0, idB, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, idB, OBJPROP_BACK, true);
         ObjectSetInteger(0, idB, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, idB, OBJPROP_HIDDEN, true);
         ObjectMove(0, idB, 0, t1, gRngHigh[k]);
         ObjectMove(0, idB, 1, t2, gRngLow[k]);
        }
      // Colour encodes the OUTCOME, which is the whole point of keeping them.
      uint col;
      if(!gRngValid[k])         col = TTextDim;                       // rejected
      else if(gRngTaken[k] > 0) col = (gRngDir[k] >= 0) ? TBull : TBear;
      else                      col = TAccent;                        // valid, untraded
      ObjectSetInteger(0, idB, OBJPROP_COLOR, CLR(col));
      ObjectSetInteger(0, idB, OBJPROP_STYLE, gRngValid[k] ? STYLE_SOLID : STYLE_DOT);
      ObjectSetInteger(0, idB, OBJPROP_FILL,  gRngTaken[k] > 0);

      if(!ShowRangeLabels) { ObjectDelete(0, PFX + "HLBL_" + tag); continue; }

      string idL = PFX + "HLBL_" + tag;
      string txt = DoubleToString((gRngHigh[k] - gRngLow[k]) / gPoint, 0) + "p  x" +
                   DoubleToString(gRngRatio[k], 2) +
                   (gRngValid[k] ? "" : "  " + T("SKIP")) +
                   (gRngTaken[k] > 0 ? "  " + IntegerToString(gRngTaken[k]) + T("T") : "") +
                   (gRngFails[k] > 0 ? "  " + IntegerToString(gRngFails[k]) + T("F") : "");
      if(ObjectFind(0, idL) < 0)
        {
         ObjectCreate(0, idL, OBJ_TEXT, 0, t1, gRngHigh[k]);
         ObjectSetInteger(0, idL, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, idL, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, idL, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, idL, OBJPROP_FONTSIZE, 7);
         ObjectMove(0, idL, 0, t1, gRngHigh[k]);
        }
      ObjectSetString (0, idL, OBJPROP_TEXT, ArObj(txt));
      ObjectSetString (0, idL, OBJPROP_FONT, UIFont("Segoe UI"));
      ObjectSetInteger(0, idL, OBJPROP_COLOR, CLR(col));
     }
  }

void DrawRangeObjects()
  {
   // Past ranges are independent objects with their own lifetime; drawing
   // them here means every existing call site keeps them up to date without
   // having to be edited.
   DrawRangeHistory();

   string idBox = PFX + "RNG_BOX";
   string idUp  = PFX + "RNG_UP";
   string idDn  = PFX + "RNG_DN";

   if(!gShowRangeBox)
     {
      ObjectDelete(0, idBox); ObjectDelete(0, idUp); ObjectDelete(0, idDn);
      return;
     }

   // While the session window is still open there is no tradable range yet,
   // but the user asked to SEE it being built: draw the partial high/low in
   // a dimmed style, with no trigger lines (there is nothing to trigger on).
   if(gBkForming && gBkFormHigh > gBkFormLow)
     {
      datetime f1 = (gBkFormStart > 0) ? gBkFormStart : Time[MathMin(Bars - 1, 50)];
      datetime f2 = Time[0] + PeriodSeconds() * 2;
      if(ObjectFind(0, idBox) < 0)
        {
         ObjectCreate(0, idBox, OBJ_RECTANGLE, 0, f1, gBkFormHigh, f2, gBkFormLow);
         ObjectSetInteger(0, idBox, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, idBox, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, idBox, OBJPROP_BACK, true);
         ObjectSetInteger(0, idBox, OBJPROP_FILL, true);
         ObjectSetInteger(0, idBox, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, idBox, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(0, idBox, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, idBox, OBJPROP_COLOR, CLR(TTextDim));
      ObjectMove(0, idBox, 0, f1, gBkFormHigh);
      ObjectMove(0, idBox, 1, f2, gBkFormLow);
      // no buffer yet -> no trigger lines
      ObjectDelete(0, idUp); ObjectDelete(0, idDn);
      return;
     }

   if(!gBkValid || gBkHigh <= gBkLow)
     {
      ObjectDelete(0, idBox); ObjectDelete(0, idUp); ObjectDelete(0, idDn);
      return;
     }

   // The box spans from where the range was measured to the right edge.
   datetime t1 = (gBkRangeStamp > 0) ? gBkRangeStamp : Time[MathMin(Bars - 1, 50)];
   datetime t2 = Time[0] + PeriodSeconds() * 10;

   if(ObjectFind(0, idBox) < 0)
     {
      ObjectCreate(0, idBox, OBJ_RECTANGLE, 0, t1, gBkHigh, t2, gBkLow);
      ObjectSetInteger(0, idBox, OBJPROP_COLOR, CLR(TAccent2));
      ObjectSetInteger(0, idBox, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, idBox, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, idBox, OBJPROP_BACK, true);
      ObjectSetInteger(0, idBox, OBJPROP_FILL, true);
      ObjectSetInteger(0, idBox, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, idBox, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, idBox, 0, t1, gBkHigh);
   ObjectMove(0, idBox, 1, t2, gBkLow);
   ObjectSetInteger(0, idBox, OBJPROP_COLOR, CLR(TAccent2));
   ObjectSetInteger(0, idBox, OBJPROP_STYLE, STYLE_SOLID);  // undo forming dots

   // Trigger lines - dashed, because they are not the range, they are the
   // range plus the buffer the body has to close beyond.
   SetRangeLine(idUp, gBkUpper, (gBkDir > 0) ? CLR(TBull) : CLR(TAccent));
   SetRangeLine(idDn, gBkLower, (gBkDir < 0) ? CLR(TBear) : CLR(TAccent));
  }

void DrawTradeLevelLines()
  {
   if(!DrawTradeLevels)
     {
      ObjectDelete(0, PFX + "LVL_ENTRY"); ObjectDelete(0, PFX + "LVL_SL");
      ObjectDelete(0, PFX + "LVL_TP");    ObjectDelete(0, PFX + "LVL_BE");
      return;
     }
   int type = -1, ticket = -1;
   if(CountOwnPositions(type, ticket) == 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
     {
      SetLevelLine("ENTRY", 0, clrNONE, 0, 1, ""); SetLevelLine("SL", 0, clrNONE, 0, 1, "");
      SetLevelLine("TP", 0, clrNONE, 0, 1, "");    SetLevelLine("BE", 0, clrNONE, 0, 1, "");
      return;
     }
   SetLevelLine("ENTRY", OrderOpenPrice(), C'90,170,255', STYLE_DASH, 1, "ENTRY");
   SetLevelLine("SL", OrderStopLoss(),   C'255,70,102', STYLE_SOLID, 2, "STOP");
   SetLevelLine("TP", OrderTakeProfit(), C'0,230,160',  STYLE_SOLID, 2, "TARGET");
   SetLevelLine("BE", BreakEvenPrice(OrderType(), OrderOpenPrice(), OrderLots()),
                C'255,206,84', STYLE_DOT, 1, "TRUE BREAK-EVEN (incl. cost)");
  }

// ---- SOLID RAISED RESULT CARDS ----------------------------------------
// Each closed trade gets a multi-line card anchored at its close, built from
// stacked OBJ_RECTANGLE_LABEL rows (BORDER_RAISED) so it is legible on any
// chart background - far more informative than the old one-line price tag.
// ======================================================================
//  ON-CHART TRADE CARDS
//  A card is born the moment a trade OPENS (entry / TP / SL / live P&L),
//  recolours green or red as the position moves, and on close rewrites
//  itself into the final result. Cards are pushed into a free lane so they
//  never sit on top of candles, and are tied back to the entry with a
//  dotted horizontal leader line.
// ======================================================================

// --- one stacked row of a card, positioned in raw SCREEN pixels ---------
void CardRow(string name, int x, int y, int w, int h, string txt,
             color bg, color fg, int fontSize, bool bold)
  {
   if(ObjectFind(0, name) >= 0 && (int)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_RECTANGLE_LABEL)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_RAISED);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 30);

   string lbl = name + "_T";
   if(ObjectFind(0, lbl) < 0) ObjectCreate(0, lbl, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, lbl, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, lbl, OBJPROP_XDISTANCE, x + ResultCardPadding);
   ObjectSetInteger(0, lbl, OBJPROP_YDISTANCE, y + h / 2);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, fontSize);
   // An OBJ_LABEL is a Windows-drawn control, so it applies its own bidi:
   // shape the glyphs but keep LOGICAL order (see ArObj), and switch to an
   // Arabic-capable font, because Consolas/Arial Black have no Arabic glyphs.
   ObjectSetString(0, lbl, OBJPROP_FONT,
                   gLang == SF_LANG_AR ? (HudArabicFont + " Bold")
                                       : (bold ? "Arial Black" : "Consolas Bold"));
   ObjectSetString(0, lbl, OBJPROP_TEXT, ArObj(txt));
   ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, lbl, OBJPROP_ZORDER, 31);
  }

// --- dotted leader: horizontal run at the anchor price, then a short
//     vertical riser to the card if the card had to dodge candles --------
void CardLeader(string base, datetime t1, double price, int cardX, int cardY,
                int cardH, color c)
  {
   // convert the card's left-middle edge back into time/price so the dotted
   // leader can be drawn with chart objects (which live in time/price space)
   int sub = 0; datetime t2 = 0; double pRow = 0.0;
   if(!ChartXYToTimePrice(0, cardX - 2, cardY + cardH / 2, sub, t2, pRow)) return;
   if(t2 <= t1) return;   // card sits left of its own anchor: skip the leader

   string hn = base + "LH";
   if(ObjectFind(0, hn) < 0) ObjectCreate(0, hn, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, hn, OBJPROP_TIME1,  t1);  ObjectSetDouble(0, hn, OBJPROP_PRICE1, price);
   ObjectSetInteger(0, hn, OBJPROP_TIME2,  t2);  ObjectSetDouble(0, hn, OBJPROP_PRICE2, price);
   ObjectSetInteger(0, hn, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, hn, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, hn, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, hn, OBJPROP_COLOR, c);
   ObjectSetInteger(0, hn, OBJPROP_BACK, true);
   ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hn, OBJPROP_HIDDEN, true);

   // vertical riser only when the card is not level with the entry
   string vn = base + "LV";
   if(MathAbs(pRow - price) > gPoint)
     {
      if(ObjectFind(0, vn) < 0) ObjectCreate(0, vn, OBJ_TREND, 0, t2, price, t2, pRow);
      ObjectSetInteger(0, vn, OBJPROP_TIME1,  t2); ObjectSetDouble(0, vn, OBJPROP_PRICE1, price);
      ObjectSetInteger(0, vn, OBJPROP_TIME2,  t2); ObjectSetDouble(0, vn, OBJPROP_PRICE2, pRow);
      ObjectSetInteger(0, vn, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, vn, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, vn, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, vn, OBJPROP_COLOR, c);
      ObjectSetInteger(0, vn, OBJPROP_BACK, true);
      ObjectSetInteger(0, vn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, vn, OBJPROP_HIDDEN, true);
     }
   else ObjectDelete(0, vn);
  }

// --- has the visible chart window moved since the last card layout? -----
// Cards live in screen pixels, so ANY of these changing invalidates them:
// the first visible bar (scroll), the bar count (zoom), the pixel size
// (resize) and the price scale (vertical drag / autoscale).
// This is polled rather than event-driven because CHARTEVENT_CHART_CHANGE is
// never delivered inside the Strategy Tester - which is exactly the case the
// user reported as "in tester he still in his place".
bool ViewportMoved()
  {
   long fvb = 0, vb = 0, w = 0, h = 0;
   ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0, fvb);
   ChartGetInteger(0, CHART_VISIBLE_BARS,      0, vb);
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS,   0, w);
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS,  0, h);
   double pmin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double pmax = ChartGetDouble(0, CHART_PRICE_MAX, 0);

   string sig = IntegerToString((int)fvb) + "|" + IntegerToString((int)vb) + "|" +
                IntegerToString((int)w)   + "|" + IntegerToString((int)h)  + "|" +
                DoubleToString(pmin, 5)   + "|" + DoubleToString(pmax, 5);
   if(sig == gViewSig) return false;
   gViewSig = sig;
   return true;
  }

// --- screen rect occupied by the HUD panel, so cards can dodge it -------
// MT4's OBJPROP_ZORDER only decides which object receives a CLICK; it does
// NOT control draw order for OBJ_RECTANGLE_LABEL vs a bitmap label. Giving
// the HUD zorder 500 therefore never stopped cards painting on top of it.
// The only reliable fix is geometric: treat the panel as occupied space.
void HudScreenRect(int &x1, int &y1, int &x2, int &y2)
  {
   x1 = 0; y1 = 0; x2 = 0; y2 = 0;
   if(!ShowHUD || !gHudReady) return;
   x1 = HudMargin;
   y1 = HudMargin;
   x2 = HudMargin + gHudW;
   y2 = HudMargin + gHudH;
  }

// The standalone tracker is a second no-go zone for result cards. It hugs the
// TOP-RIGHT corner, so its left edge is measured back from the chart width.
void TrackerScreenRect(int &x1, int &y1, int &x2, int &y2)
  {
   x1 = 0; y1 = 0; x2 = 0; y2 = 0;
   if(!ShowHUD || !ShowTrackerPanel || !gTrkReady) return;
   long chartW = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chartW);
   x2 = (int)chartW - HudMargin;
   x1 = x2 - gTrkW;
   y1 = HudMargin;
   y2 = HudMargin + gTrkH;
  }

// --- find a vertical slot for a card whose x-span is [cx, cx+cw] so that
//     it clears every candle in that span, plus any card already placed ---
int FreeLaneY(int cx, int cw, int ch, int anchorY, bool preferAbove,
              int &oX1[], int &oY1[], int &oX2[], int &oY2[], int occN)
  {
   long chH = 0, chW = 0;
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chH);
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chW);
   int gap = MathMax(6, ResultCardGapPx);
   int sep = MathMax(0, ResultCardSeparationPx);   // required gap BETWEEN cards

   // price extremes of the candles the card would cover horizontally
   int sub = 0; datetime tA = 0, tB = 0; double pA = 0, pB = 0;
   double hi = 0, lo = 0; bool haveBars = false;
   if(ChartXYToTimePrice(0, cx, 10, sub, tA, pA) &&
      ChartXYToTimePrice(0, cx + cw, 10, sub, tB, pB))
     {
      int iA = iBarShift(NULL, 0, tA, false);
      int iB = iBarShift(NULL, 0, tB, false);
      int lo_i = MathMin(iA, iB), hi_i = MathMax(iA, iB);
      if(lo_i < 0) lo_i = 0;
      if(hi_i >= Bars) hi_i = Bars - 1;
      int cnt = hi_i - lo_i + 1;
      if(cnt > 0 && cnt < 5000)
        {
         int hh = iHighest(NULL, 0, MODE_HIGH, cnt, lo_i);
         int ll = iLowest(NULL, 0, MODE_LOW,  cnt, lo_i);
         if(hh >= 0 && ll >= 0) { hi = High[hh]; lo = Low[ll]; haveBars = true; }
        }
     }

   int yUp = anchorY - ch - gap, yDn = anchorY + gap;
   if(haveBars)
     {
      int xh = 0, yh = 0, xl = 0, yl = 0;
      if(ChartTimePriceToXY(0, 0, Time[0], hi, xh, yh)) yUp = yh - ch - gap;
      if(ChartTimePriceToXY(0, 0, Time[0], lo, xl, yl)) yDn = yl + gap;
     }

   // the HUD is an obstacle like any other card - see HudScreenRect()
   int hx1 = 0, hy1 = 0, hx2 = 0, hy2 = 0;
   HudScreenRect(hx1, hy1, hx2, hy2);
   bool hudOverlapsX = (hx2 > hx1) && (cx < hx2 + sep) && (cx + cw > hx1 - sep);
   int tx1 = 0, ty1 = 0, tx2 = 0, ty2 = 0;
   TrackerScreenRect(tx1, ty1, tx2, ty2);
   bool trkOverlapsX = (tx2 > tx1) && (cx < tx2 + sep) && (cx + cw > tx1 - sep);

   // Side preference (BUY above / SELL below) is a SOFT constraint: if the
   // preferred side is blocked by the panel, a card or the window edge we
   // fall back to the other side rather than hide the result. Separation and
   // panel-avoidance are HARD - they are never traded away.
   int cand[2];
   if(preferAbove) { cand[0] = yUp; cand[1] = yDn; }
   else            { cand[0] = yDn; cand[1] = yUp; }

   for(int pass = 0; pass < 2; pass++)
     {
      int y = cand[pass];
      bool up = (cand[pass] == yUp);
      if(y < 4 || y + ch > (int)chH - 4) continue;

      // Walk the card clear of every obstacle. Each displacement is at least
      // `sep` px so two cards can never end up merely touching - the user
      // asked for a hard 40 px of daylight between them.
      bool placed = false;
      for(int tries = 0; tries < 40; tries++)
        {
         bool clash = false;

         if(hudOverlapsX && y < hy2 + sep && y + ch > hy1 - sep)
           {
            // push the card out of the panel band, away from the panel
            y = up ? (hy1 - sep - ch) : (hy2 + sep);
            clash = true;
           }
         else if(trkOverlapsX && y < ty2 + sep && y + ch > ty1 - sep)
           {
            y = up ? (ty1 - sep - ch) : (ty2 + sep);
            clash = true;
           }

         if(!clash)
            for(int k = 0; k < occN; k++)
              {
               // inflate the occupied rect by `sep` on every side
               if(cx < oX2[k] + sep && cx + cw > oX1[k] - sep &&
                  y  < oY2[k] + sep && y + ch  > oY1[k] - sep)
                 {
                  y = up ? (oY1[k] - sep - ch) : (oY2[k] + sep);
                  clash = true;
                  break;
                 }
              }

         if(!clash) { placed = true; break; }
         if(y < 4 || y + ch > (int)chH - 4) break;
        }
      if(placed && y >= 4 && y + ch <= (int)chH - 4) return y;
     }

   // Last resort A: scan the whole column for the first free slot, still
   // honouring the separation. Better a displaced card than a stacked one.
   for(int y2 = 4; y2 + ch <= (int)chH - 4; y2 += 6)
     {
      bool clash = false;
      if(hudOverlapsX && y2 < hy2 + sep && y2 + ch > hy1 - sep) clash = true;
      if(trkOverlapsX && y2 < ty2 + sep && y2 + ch > ty1 - sep) clash = true;
      if(!clash)
         for(int k = 0; k < occN; k++)
            if(cx < oX2[k] + sep && cx + cw > oX1[k] - sep &&
               y2 < oY2[k] + sep && y2 + ch > oY1[k] - sep)
              { clash = true; break; }
      if(!clash) return y2;
     }

   // Nowhere honours the separation. Rather than stack this card on top of
   // another - the exact complaint being fixed - REFUSE to place it and let
   // the caller skip it. Cards are drawn newest-first, so what gets dropped
   // is always the oldest, least interesting result.
   return SF_NO_LANE;
  }

// Same allocator, but guaranteed to return a position. Used by the LIVE card,
// which must always be visible even on a crowded chart.
int ForcedLaneY(int cx, int cw, int ch, int anchorY, bool preferAbove,
                int &oX1[], int &oY1[], int &oX2[], int &oY2[], int occN)
  {
   int y = FreeLaneY(cx, cw, ch, anchorY, preferAbove, oX1, oY1, oX2, oY2, occN);
   if(y != SF_NO_LANE) return y;

   long chH = 0;
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chH);
   int hx1 = 0, hy1 = 0, hx2 = 0, hy2 = 0;
   HudScreenRect(hx1, hy1, hx2, hy2);
   bool hudX = (hx2 > hx1) && (cx < hx2) && (cx + cw > hx1);
   int tx1 = 0, ty1 = 0, tx2 = 0, ty2 = 0;
   TrackerScreenRect(tx1, ty1, tx2, ty2);
   bool trkX = (tx2 > tx1) && (cx < tx2) && (cx + cw > tx1);

   // first slot that at least clears the panel and hard-overlaps nothing
   for(int y3 = 4; y3 + ch <= (int)chH - 4; y3 += 6)
     {
      if(hudX && y3 < hy2 + 2 && y3 + ch > hy1 - 2) continue;
      if(trkX && y3 < ty2 + 2 && y3 + ch > ty1 - 2) continue;
      bool hard = false;
      for(int k = 0; k < occN; k++)
         if(cx < oX2[k] && cx + cw > oX1[k] && y3 < oY2[k] && y3 + ch > oY1[k])
           { hard = true; break; }
      if(!hard) return y3;
     }

   int fy = anchorY - ch / 2;
   if(hudX)
     {
      if(hy2 + 2 + ch <= (int)chH - 4) fy = hy2 + 2;
      else if(hy1 - 2 - ch >= 4)       fy = hy1 - 2 - ch;
     }
   if(fy < 4) fy = 4;
   if(fy + ch > (int)chH - 4) fy = (int)chH - ch - 4;
   return fy;
  }

// --- the LIVE card for the currently open position ---------------------
void DrawLiveTradeCard(int &oX1[], int &oY1[], int &oX2[], int &oY2[], int &occN)
  {
   int type = -1, ticket = -1;
   if(CountOwnPositions(type, ticket) == 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
     { ObjectsDeleteAll(0, PFX + "LIVE_"); return; }

   bool   isBuy = (OrderType() == OP_BUY);
   double entry = OrderOpenPrice();
   double cur   = isBuy ? Bid : Ask;
   bool   commEst = false;
   double gross   = OrderProfit() + OrderSwap();
   double comm    = TradeCommissionUSD(OrderLots(), OrderCommission(), commEst);
   double net     = commEst ? (gross - comm) : (gross + OrderCommission());
   double pts   = isBuy ? (cur - entry) / gPoint : (entry - cur) / gPoint;
   double bal   = AccountBalance();
   double gainP = (bal > 0) ? net / bal * 100.0 : 0.0;
   int    mins  = (int)((TimeCurrent() - OrderOpenTime()) / 60);

   // colour follows the LIVE result, flipping green/red as price moves
   color bgHead, bgBody, edge, txtBd;
   if(net > 0)      { bgHead = C'0,138,96';   bgBody = C'8,58,46';   edge = C'0,255,170'; txtBd = C'150,255,215'; }
   else if(net < 0) { bgHead = C'158,28,56';  bgBody = C'74,18,32';  edge = C'255,80,120'; txtBd = C'255,180,195'; }
   else             { bgHead = C'30,64,132';  bgBody = C'18,32,62';  edge = C'120,180,255'; txtBd = C'185,210,255'; }

   int fs = MathMax(7, ResultCardFontSize), fsHd = fs + 1;
   int rowH = fs + SC(11), headH = rowH + SC(3);
   int w = MathMax(SC(150), ResultCardWidth + SC(14));
   int h = headH + rowH * 4;

   long chW = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chW);
   int ex = 0, ey = 0;
   if(!ChartTimePriceToXY(0, 0, OrderOpenTime(), entry, ex, ey))
     { ObjectsDeleteAll(0, PFX + "LIVE_"); return; }

   // park the live card in the right margin, clear of the candles
   int x = (int)chW - w - SC(16);
   if(x < ex + SC(24)) x = ex + SC(24);
   if(x + w > (int)chW - SC(6)) x = (int)chW - w - SC(6);
   if(x < 2) x = 2;
   // BUY above price, SELL below (user-configurable)
   bool above = BuyCardsAbove ? isBuy : !isBuy;
   int y = ForcedLaneY(x, w, h, ey, above, oX1, oY1, oX2, oY2, occN);

   string b = PFX + "LIVE_";
   double tp = OrderTakeProfit(), sl = OrderStopLoss();
   double tpP = (tp > 0) ? (isBuy ? (tp - entry) : (entry - tp)) / gPoint : 0;
   double slP = (sl > 0) ? (isBuy ? (entry - sl) : (sl - entry)) / gPoint : 0;

   CardRow(b + "R0", x, y, w, headH,
           "LIVE " + (net >= 0 ? "+" : "") + DoubleToString(net, 2) + " USD",
           bgHead, C'255,255,255', fsHd, true);
   CardRow(b + "R1", x, y + headH, w, rowH,
           (isBuy ? "BUY  " : "SELL ") + DoubleToString(OrderLots(), 2) + " @ " +
           DoubleToString(entry, gDigits), bgBody, txtBd, fs, false);
   CardRow(b + "R2", x, y + headH + rowH, w, rowH,
           "TP " + (tp > 0 ? DoubleToString(tp, gDigits) + "  " +
                             DoubleToString(MathRound(tpP), 0) + "p" : "none"),
           bgBody, C'150,255,215', fs, false);
   CardRow(b + "R3", x, y + headH + rowH * 2, w, rowH,
           "SL " + (sl > 0 ? DoubleToString(sl, gDigits) + "  " +
                             DoubleToString(MathRound(slP), 0) + "p" : "none"),
           bgBody, C'255,180,195', fs, false);
   CardRow(b + "R4", x, y + headH + rowH * 3, w, rowH,
           (pts >= 0 ? "+" : "") + DoubleToString(MathRound(pts), 0) + "p  " +
           (gainP >= 0 ? "+" : "") + DoubleToString(gainP, 2) + "%  " +
           IntegerToString(mins) + "m", bgBody, txtBd, fs, false);

   CardLeader(b, OrderOpenTime(), entry, x, y, h, edge);

   if(occN < ArraySize(oX1))
     { oX1[occN] = x; oY1[occN] = y; oX2[occN] = x + w; oY2[occN] = y + h; occN++; }
  }

// --- cards for CLOSED trades: the final result ------------------------
void DrawClosedTradeCards(int &oX1[], int &oY1[], int &oX2[], int &oY2[], int &occN)
  {
   int total = OrdersHistoryTotal();
   int fs = MathMax(7, ResultCardFontSize), fsHd = fs + 1;
   int rowH = fs + SC(11), headH = rowH + SC(3);
   int w = MathMax(SC(150), ResultCardWidth + SC(14));
   int h = headH + rowH * 3;
   int drawn = 0;
   int sep  = MathMax(0, ResultCardSeparationPx);
   int sepX = MathMax(4, sep / 2);      // horizontal breathing room
   long chW = 0, chH = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chW);
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chH);

   for(int i = total - 1; i >= 0 && drawn < MaxResultPills; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      datetime ct = OrderCloseTime();
      if(ct <= 0) continue;

      bool   commEst = false;
      double gross   = OrderProfit() + OrderSwap();
      double comm    = TradeCommissionUSD(OrderLots(), OrderCommission(), commEst);
      // when the fee had to be estimated it is not in OrderProfit() either,
      // so subtract it to keep net honest
      double net     = commEst ? (gross - comm) : (gross + OrderCommission());
      bool   won     = (net > 0);
      bool   isBuy = (OrderType() == OP_BUY);
      double pts   = isBuy ? (OrderClosePrice() - OrderOpenPrice()) / gPoint
                           : (OrderOpenPrice() - OrderClosePrice()) / gPoint;
      // gTrkStartBal is only populated by RebuildStats(); fall back to the
      // live balance so GAIN% is never a silent 0.00%
      double baseBal = (gTrkStartBal > 0) ? gTrkStartBal : AccountBalance();
      double gainPct = (baseBal > 0) ? net / baseBal * 100.0 : 0.0;
      int holdMin = (int)((ct - OrderOpenTime()) / 60);

      int ax = 0, ay = 0;
      if(!ChartTimePriceToXY(0, 0, ct, OrderClosePrice(), ax, ay)) continue;
      if(ax < -w || ax > (int)chW + w) continue;   // off screen horizontally

      int x = ax + SC(12);
      if(x + w > (int)chW - SC(4)) x = ax - w - SC(12);
      if(x < 2) x = 2;

      // If the card would land in the panel's x-band, move it clear
      // HORIZONTALLY. Sliding it vertically instead would force it into the
      // thin strip above/below a tall panel, where only one card fits - which
      // is what used to make cards pile up on each other next to the HUD.
      // Clear the panel's x-band by the FULL separation, not sepX. FreeLaneY()
      // tests that band inflated by `sep`, so dodging by only sepX left the
      // card still "inside" the band and it got shoved below the panel.
      int hx1 = 0, hy1 = 0, hx2 = 0, hy2 = 0;
      HudScreenRect(hx1, hy1, hx2, hy2);
      if(hx2 > hx1 && x < hx2 + sep && x + w > hx1 - sep)
        {
         int altR = hx2 + sep;                  // just right of the panel
         int altL = hx1 - sep - w;              // just left of the panel
         if(altR + w <= (int)chW - SC(4))      x = altR;
         else if(altL >= 2)                    x = altL;
        }

      // same dodge for the top-right tracker; prefer sliding LEFT of it
      // because there is no room between it and the right window edge.
      int tx1 = 0, ty1 = 0, tx2 = 0, ty2 = 0;
      TrackerScreenRect(tx1, ty1, tx2, ty2);
      if(tx2 > tx1 && x < tx2 + sep && x + w > tx1 - sep)
        {
         int tAltL = tx1 - sep - w;
         if(tAltL >= 2 && !(hx2 > hx1 && tAltL < hx2 + sep && tAltL + w > hx1 - sep))
            x = tAltL;
        }

      // Cards that still share a column get staggered sideways so the
      // vertical allocator has somewhere to put them.
      for(int nudge = 0; nudge < 8; nudge++)
        {
         bool tight = false;
         for(int k = 0; k < occN; k++)
            if(x < oX2[k] + sepX && x + w > oX1[k] - sepX)
              {
               // only step aside if this column is already near capacity
               int stack = 0;
               for(int q = 0; q < occN; q++)
                  if(x < oX2[q] + sepX && x + w > oX1[q] - sepX) stack++;
               if(stack * (h + sep) > (int)chH - 8) { tight = true; }
               break;
              }
         if(!tight) break;
         int step = w + sepX;
         if(x + step + w <= (int)chW - SC(4)) x += step;
         else if(x - step >= 2)               x -= step;
         else break;
        }

      // BUY above price, SELL below (user-configurable)
      bool above = BuyCardsAbove ? isBuy : !isBuy;
      int y = FreeLaneY(x, w, h, ay, above, oX1, oY1, oX2, oY2, occN);
      if(y == SF_NO_LANE) continue;   // too crowded: drop the oldest result

      color bgHead = won ? C'0,138,96'  : C'158,28,56';
      color bgBody = won ? C'8,58,46'   : C'74,18,32';
      color edge   = won ? C'0,255,170' : C'255,80,120';
      color txtBd  = won ? C'150,255,215' : C'255,180,195';

      string b = PFX + "RES_" + IntegerToString(OrderTicket()) + "_";
      CardRow(b + "R0", x, y, w, headH,
              (won ? T("WIN") : T("LOSS")) + " " + (net >= 0 ? "+" : "") +
              DoubleToString(net, 2) + " " + T("USD"), bgHead, C'255,255,255', fsHd, true);
      CardRow(b + "R1", x, y + headH, w, rowH,
              (isBuy ? T("BUY") : T("SELL")) + " " + DoubleToString(OrderLots(), 2) +
              " " + T("lot") + "  " +
              (pts >= 0 ? "+" : "") + DoubleToString(MathRound(pts), 0) + T("p"),
              bgBody, txtBd, fs, false);
      CardRow(b + "R2", x, y + headH + rowH, w, rowH,
              T("GROSS") + " " + (gross >= 0 ? "+" : "") + DoubleToString(gross, 2) +
              "  " + T("FEE") + " " + (commEst ? "~-" : "-") + DoubleToString(comm, 2),
              bgBody, txtBd, fs, false);
      CardRow(b + "R3", x, y + headH + rowH * 2, w, rowH,
              T("GAIN") + " " + (gainPct >= 0 ? "+" : "") + DoubleToString(gainPct, 2) + "%  " +
              IntegerToString(holdMin) + T("m"), bgBody, txtBd, fs, false);

      CardLeader(b, OrderOpenTime(), OrderOpenPrice(), x, y, h, edge);

      string m = b + "MK";
      if(ObjectFind(0, m) < 0) ObjectCreate(0, m, OBJ_ARROW, 0, ct, OrderClosePrice());
      ObjectMove(0, m, 0, ct, OrderClosePrice());
      ObjectSetInteger(0, m, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, m, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, m, OBJPROP_COLOR, edge);
      ObjectSetInteger(0, m, OBJPROP_BACK, false);
      ObjectSetInteger(0, m, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, m, OBJPROP_HIDDEN, true);

      if(occN < ArraySize(oX1))
        { oX1[occN] = x; oY1[occN] = y; oX2[occN] = x + w; oY2[occN] = y + h; occN++; }
      drawn++;
     }
  }

// Closed cards are static once drawn, so they are only rebuilt when the
// history actually changes or the chart moves (gCardsDirty). The LIVE card
// is cheap and is refreshed on every call so its P&L tracks price.
// Rebuilding all ~125 objects at the HUD refresh rate would flicker.
void DrawResultPills()
  {
   // Card text depends on tracker-derived stats (gTrkStartBal for GAIN%).
   // RebuildStats() used to be called only by the TRACKER page, so cards drawn
   // before that tab was ever opened baked in a 0.00% gain and were then
   // latched by gKnownResultHistory and never redrawn. It is cheap (it early-
   // outs unless the history count changed), so drive it from here too.
   RebuildStats();

   // Poll the viewport. Closed cards are pixel-anchored, so a scroll, zoom,
   // resize or price-scale change invalidates every one of them. Polling here
   // (rather than relying on CHARTEVENT_CHART_CHANGE) is what makes the cards
   // track the chart INSIDE THE STRATEGY TESTER, where OnChartEvent is never
   // delivered and the cards previously stayed frozen where they were born.
   if(ViewportMoved()) gCardsDirty = true;

   int total = OrdersHistoryTotal();
   bool rebuildClosed = (total != gKnownResultHistory) || gCardsDirty;

   int oX1[64], oY1[64], oX2[64], oY2[64];
   ArrayInitialize(oX1, 0); ArrayInitialize(oY1, 0);
   ArrayInitialize(oX2, 0); ArrayInitialize(oY2, 0);
   int occN = 0;

   // the live card is placed first so closed cards dodge it
   if(ShowLiveTradeCard) DrawLiveTradeCard(oX1, oY1, oX2, oY2, occN);
   else                  ObjectsDeleteAll(0, PFX + "LIVE_");

   if(rebuildClosed)
     {
      ObjectsDeleteAll(0, PFX + "RES_");
      if(DrawTradeResults) DrawClosedTradeCards(oX1, oY1, oX2, oY2, occN);
      gKnownResultHistory = total;
      gCardsDirty = false;
     }

   // Permanent, price-anchored markers for EVERY closed trade. Unlike the
   // cards above these are not capped by MaxResultPills and not deleted on
   // a viewport change, so a finished run stays fully reviewable.
   DrawTradeHistoryMarkers();
  }

void ApplySkin()
  {
   if(!ApplyChartSkin) return;
   color bg, fg, grid, up, dn;
   switch(gTheme)
     {
      case SF_THEME_CARBON:
         bg = C'14,16,18'; fg = C'190,200,212'; grid = C'34,38,44';
         up = C'150,255,90'; dn = C'255,92,92'; break;
      case SF_THEME_SOLAR:
         bg = C'20,16,12'; fg = C'220,205,185'; grid = C'44,36,26';
         up = C'255,190,60'; dn = C'255,96,86'; break;
      default:
         bg = C'8,11,20'; fg = C'170,190,220'; grid = C'22,30,48';
         up = C'0,230,160'; dn = C'255,70,102'; break;
     }
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, bg);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, fg);
   ChartSetInteger(0, CHART_COLOR_GRID, grid);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, up);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, dn);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, up);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, dn);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, fg);
   ChartSetInteger(0, CHART_COLOR_BID, C'90,180,255');
   ChartSetInteger(0, CHART_COLOR_ASK, C'255,120,150');
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, C'255,206,84');
   ChartSetInteger(0, CHART_SHOW_OHLC, true);
   ChartRedraw(0);
  }

//==================================================================//
//              E N T R Y   G A T E                                 //
//==================================================================//
// The original strategy had no risk layer: the only pre-trade checks were
// the spread cap (inside OpenPosition) and the manual pause. Everything
// else - sessions, daily loss caps, equity kill-switch, cooldowns - was a
// v2 addition and has been removed at the user's request.
bool MayOpenNewTrade(string &why)
  {
   why = "";
   if(gPaused)                { why = T("PAUSED");         return false; }
   if(!IsTradeAllowed())      { why = T("TRADE NOT ALLOWED"); return false; }
   if(IsTradeContextBusy())   { why = T("CONTEXT BUSY");      return false; }
   return true;
  }

//==================================================================//
//              O N   I N I T   /   D E I N I T                     //
//==================================================================//
int OnInit()
  {
   gLang  = (int)HudLanguage;   // seed the live copies from the inputs
   gShowRangeBox = ShowRangeBox;
   gTheme = (int)HudTheme;
   LoadTheme();
   CacheSymbolSpec();
   RecalcCostPoints();



   gDayStamp       = DayStart(TimeCurrent());
   gDayStartEquity = AccountEquity();
   gLastHistoryCount = -1;

   if(HudInteractive) ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   if(!IsTesting() || IsVisualMode()) ApplySkin();
   if(!IsTesting()) EventSetMillisecondTimer(MathMax(100, HudRefreshMs));

   if(Digits != 3 && StringFind(Symbol(), "XAU") >= 0)
      Print("[BK-FORGE] NOTE: symbol has ", Digits, " digits. Tuned for 3-digit gold; ",
            "point-based inputs may need scaling.");

   Journal("BK-FORGE v1.04 online | comm " + Fmt(gCostPointsRT, 0) + " pts RT | " +
           "min " + Fmt(gMinLot, 2) + " lot");

   // Print exactly which overlays are armed, so a "nothing is drawn" report
   // can be diagnosed from the Experts log without guesswork.
   string ov = "";
   Print("[BK-FORGE] v1.04 build | range=",
         (RangeMode == BK_RANGE_DONCHIAN ? "DONCHIAN" : "SESSION"),
         " | entry=", (EntryMode == BK_ENTRY_RETEST ? "RETEST" : "BREAK"),
         " | width gate=", DoubleToString(MinRangeATRMult, 2), "-",
         DoubleToString(MaxRangeATRMult, 2), " x expected travel",
         " | magic=", MagicNumber);

   gLastBar = 0;

   // Build and draw the range NOW rather than waiting for the first new bar,
   // which on a live M5 chart would leave the panel empty for five minutes.
   if(!IsTesting() || IsVisualMode())
     {
      if(Bars > 100)
        {
         UpdateRange();
         // Explain the range verdict in the journal. "NO VALID RANGE" on the
         // panel is otherwise impossible to diagnose from a screenshot.
         if(gBkForming)
            Print("[BK-FORGE] range window still open, collecting (",
                  gBkFormBars, " bars so far)");
         else if(gBkHigh > gBkLow)
            Print("[BK-FORGE] range ", DoubleToString(gBkLow, Digits), "-",
                  DoubleToString(gBkHigh, Digits),
                  " | ", gBkBars, " bars | width ",
                  DoubleToString((gBkHigh - gBkLow) / gPoint, 0), "p",
                  " | ratio ", DoubleToString(gBkRatio, 2),
                  " vs ", DoubleToString(MinRangeATRMult, 2), "-",
                  DoubleToString(MaxRangeATRMult, 2),
                  " -> ", (gBkValid ? "VALID" : "REJECTED"));
         else
            Print("[BK-FORGE] no range yet (need history, or the window has ",
                  "not completed since the EA started)");
         DrawRangeObjects();
         DrawTradeLevelLines();
         DrawResultPills();
        }
      PaintAll();
      ChartRedraw(0);
     }

   // Self-test: prove the controls really exist as OBJ_BUTTON objects and
   // report where they are, so a dead-button report can be diagnosed from
   // the log alone rather than by guesswork.
   int nbtn = 0;
   string firstName = "", firstPos = "";
   for(int b = ObjectsTotal(0, -1, OBJ_BUTTON) - 1; b >= 0; b--)
     {
      string bn = ObjectName(0, b, -1, OBJ_BUTTON);
      if(StringFind(bn, PFX + "BTN_") != 0) continue;
      nbtn++;
      if(firstName == "")
        {
         firstName = bn;
         firstPos  = "x=" + IntegerToString((int)ObjectGetInteger(0, bn, OBJPROP_XDISTANCE)) +
                     " y=" + IntegerToString((int)ObjectGetInteger(0, bn, OBJPROP_YDISTANCE)) +
                     " w=" + IntegerToString((int)ObjectGetInteger(0, bn, OBJPROP_XSIZE)) +
                     " h=" + IntegerToString((int)ObjectGetInteger(0, bn, OBJPROP_YSIZE));
        }
     }
   Print("[BK-FORGE] controls created: ", nbtn, " real OBJ_BUTTON objects",
         (nbtn > 0 ? " | e.g. " + firstName + " " + firstPos : " <-- NONE! HUD is not interactive"));
   Print("[BK-FORGE] interactive=", HudInteractive,
         " | if clicking prints no 'event id=' line, the click is not reaching the EA");
   return INIT_SUCCEEDED;
  }

// new-allocated canvases must be deleted explicitly or MT4 logs a leak
void FreeCanvases()
  {
   gCv = NULL;
   if(gHud != NULL) { delete gHud; gHud = NULL; }
   if(gTrk != NULL) { delete gTrk; gTrk = NULL; }
  }

// ---- CSV EXPORT ----------------------------------------------------
// Chart objects are for eyeballing; a CSV is for actually analysing. Two
// files are written to MQL4/Files (or tester/files during a backtest):
// one row per archived range, one row per closed trade. Written on deinit
// so a finished backtest leaves the whole run on disk.
void ExportHistoryFiles()
  {
   if(!ExportHistoryCSV) return;

   string stamp = Symbol() + "_" + IntegerToString(Period()) + "_" +
                  IntegerToString(MagicNumber);

   // ---- ranges ----
   string fr = "BKF_ranges_" + stamp + ".csv";
   int h = FileOpen(fr, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
      Print("[BK-FORGE] range CSV open failed: ", GetLastError());
   else
     {
      FileWrite(h, "start", "end", "high", "low", "width_points",
                   "bars", "ratio", "valid", "trades", "failed_breaks", "last_dir");
      int have = ArchivedRanges();
      for(int nth = have - 1; nth >= 0; nth--)     // oldest first
        {
         int k = ArchivedSlot(nth);
         if(k < 0 || gRngHigh[k] <= gRngLow[k]) continue;
         FileWrite(h,
                   TimeToString(gRngStart[k], TIME_DATE | TIME_MINUTES),
                   TimeToString(gRngEnd[k],   TIME_DATE | TIME_MINUTES),
                   DoubleToString(gRngHigh[k], Digits),
                   DoubleToString(gRngLow[k],  Digits),
                   DoubleToString((gRngHigh[k] - gRngLow[k]) / gPoint, 0),
                   IntegerToString(gRngBars[k]),
                   DoubleToString(gRngRatio[k], 3),
                   gRngValid[k] ? "1" : "0",
                   IntegerToString(gRngTaken[k]),
                   IntegerToString(gRngFails[k]),
                   IntegerToString(gRngDir[k]));
        }
      FileClose(h);
      Print("[BK-FORGE] wrote ", fr, " (", have, " ranges)");
     }

   // ---- trades ----
   string ft = "BKF_trades_" + stamp + ".csv";
   int h2 = FileOpen(ft, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h2 == INVALID_HANDLE)
     {
      Print("[BK-FORGE] trade CSV open failed: ", GetLastError());
      return;
     }
   FileWrite(h2, "ticket", "type", "lots", "open_time", "open_price",
                 "close_time", "close_price", "sl", "tp",
                 "stop_points", "target_points",
                 "profit", "swap", "commission", "net", "comment");
   int total = OrdersHistoryTotal(), n = 0;
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      double slp = (OrderStopLoss()   > 0)
                   ? MathAbs(OrderOpenPrice() - OrderStopLoss())   / gPoint : 0;
      double tpp = (OrderTakeProfit() > 0)
                   ? MathAbs(OrderTakeProfit() - OrderOpenPrice()) / gPoint : 0;
      FileWrite(h2,
                IntegerToString(OrderTicket()),
                (OrderType() == OP_BUY) ? "BUY" : "SELL",
                DoubleToString(OrderLots(), 2),
                TimeToString(OrderOpenTime(),  TIME_DATE | TIME_MINUTES),
                DoubleToString(OrderOpenPrice(),  Digits),
                TimeToString(OrderCloseTime(), TIME_DATE | TIME_MINUTES),
                DoubleToString(OrderClosePrice(), Digits),
                DoubleToString(OrderStopLoss(),   Digits),
                DoubleToString(OrderTakeProfit(), Digits),
                DoubleToString(slp, 0),
                DoubleToString(tpp, 0),
                DoubleToString(OrderProfit(), 2),
                DoubleToString(OrderSwap(), 2),
                DoubleToString(OrderCommission(), 2),
                DoubleToString(net, 2),
                OrderComment());
      n++;
     }
   FileClose(h2);
   Print("[BK-FORGE] wrote ", ft, " (", n, " trades)");
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   // The range that is live when the EA stops has never been archived, so
   // fold it in before exporting or the last session would be missing.
   if(KeepRangeHistory) ArchiveCurrentRange();
   ExportHistoryFiles();

   if(IsTesting() && IsVisualMode() && KeepVisualsAfterTest)
     {
      // Canvas dies with the EA; leave the chart objects for review.
      // The invisible hotspots must go, though - they would otherwise sit on
      // the chart swallowing clicks with no EA behind them.
      DestroyHud();
      DestroyTracker();
      ObjectsDeleteAll(0, PFX + "BTN_");
      FreeCanvases();
      ChartRedraw(0);
      return;
     }
   DestroyHud();
   DestroyTracker();
   FreeCanvases();
   ObjectsDeleteAll(0, PFX);
   ChartRedraw(0);
  }

//==================================================================//
//              T I M E R  /  E V E N T S                           //
//==================================================================//
void OnTimer()
  {
   RollDailyCounters();
   TrackClosedTrades();
   // Do not rebuild the controls while the user is interacting with them.
   if(RepaintLocked()) { ChartRedraw(0); return; }
   DrawTradeLevelLines();
   DrawResultPills();
   PaintAll();
   ChartRedraw(0);
  }

void HandleHudAction(string hit)
  {
   if(hit == "") return;
   if(VerboseJournal) Print("[BK-FORGE] click -> ", hit);

   if(hit == "BTN_COLLAPSE") gHudCollapsed = !gHudCollapsed;
   else if(hit == "TAB_CORE")     gHudPage = 0;
   else if(hit == "TAB_BREAKOUT") gHudPage = 1;
   else if(hit == "TRK_COLLAPSE") gTrkCollapsed = !gTrkCollapsed;
   else if(hit == "BTN_LANG")
     {
      // Live language switch. Every button caption changes script, so the
      // existing objects must be destroyed: MT4 caches the caption, and a
      // stale Latin caption in an Arabic font renders as boxes.
      gLang = (gLang == SF_LANG_AR) ? SF_LANG_EN : SF_LANG_AR;
      ObjectsDeleteAll(0, PFX + "BTN_");
      gButtonCount = 0;
      gCardsDirty  = true;         // chart result cards are translated too
      Journal(gLang == SF_LANG_AR ? "LANGUAGE: ARABIC" : "LANGUAGE: ENGLISH");
     }
   else if(hit == "BTN_SKIN")
     {
      // Cycle the colour theme and re-skin both the panels and the chart.
      gTheme = (gTheme + 1) % 3;
      LoadTheme();
      ApplySkin();
      gCardsDirty = true;
      Journal("THEME " + IntegerToString(gTheme + 1));
     }
   else if(hit == "BTN_PAUSE" || hit == "TRK_PAUSE")
     {
      gPaused = !gPaused;
      Journal(gPaused ? "MANUAL PAUSE" : "MANUAL RESUME");
     }
   else if(hit == "BTN_CLOSE")
     {
      int t = -1, tk = -1;
      if(CountOwnPositions(t, tk) > 0) CloseAllOwn("MANUAL BUTTON");
      else Journal("NOTHING TO CLOSE");
     }
   else if(hit == "BTN_THEME")
     {
      // Toggle the range box and its buffer lines on the price chart.
      gShowRangeBox = !gShowRangeBox;
      if(!gShowRangeBox)
        {
         ObjectDelete(0, PFX + "RNG_BOX");
         ObjectDelete(0, PFX + "RNG_UP");
         ObjectDelete(0, PFX + "RNG_DN");
        }
      else DrawRangeObjects();
      Journal(gShowRangeBox ? "RANGE BOX ON" : "RANGE BOX OFF");
     }
   PaintAll();
   ChartRedraw(0);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // Diagnostic: prove whether clicks reach the EA at all. Any click on the
   // panel must print a line here; if nothing prints, the event never
   // arrived (AutoTrading off, chart not focused, or the object is not a
   // real button) rather than the handler misbehaving.
   if(VerboseJournal && id != CHARTEVENT_MOUSE_MOVE)
      Print("[BK-FORGE] event id=", id,
            (sparam != "" ? " obj=" + sparam : ""),
            " lp=", lparam, " dp=", dparam);

   if(!HudInteractive) return;

   //--- track the cursor only; MT4 renders hover on a real button itself, so
   //    repainting the whole HUD on every mouse move is pure overhead (and it
   //    used to fight the click, because the repaint deleted and recreated
   //    objects while the button was being pressed).
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      gMouseX = (int)lparam; gMouseY = (int)dparam;
      gLastMouseMs = GetTickCount();   // arm the repaint freeze
      return;
     }

   // PRIMARY path: a real OBJ_BUTTON hotspot was clicked. MT4 always reports
   // this for a genuine button and hands us the object NAME, so no coordinate
   // guessing is involved - this is what makes the HUD reliably clickable.
   // Some builds report a button press as OBJECT_CLICK, others fold it into
   // OBJECT_CHANGE / a plain CLICK. Accept every route that names one of our
   // controls, so the HUD cannot be dead just because of build differences.
   if(id == CHARTEVENT_OBJECT_CLICK || id == CHARTEVENT_OBJECT_CHANGE)
     {
      if(StringFind(sparam, PFX + "BTN_") == 0)
        {
         gLastMouseMs = GetTickCount();
         // a button latches itself down; release it so it can be clicked again
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         string btnId = StringSubstr(sparam, StringLen(PFX + "BTN_"));
         if(DuplicateClick(btnId))
           {
            if(VerboseJournal) Print("[BK-FORGE] ignored duplicate click -> ", btnId);
            return;
           }
         HandleHudAction(btnId);
         return;
        }
      if(sparam == PFX + "HUD" || sparam == PFX + "TRK")
        {
         string panelId = HitButton(gMouseX, gMouseY);
         if(!DuplicateClick(panelId)) HandleHudAction(panelId);
         return;
        }
     }

   // FALLBACK: bare chart click, hit-tested against the registry.
   if(id == CHARTEVENT_CLICK)
     {
      gLastMouseMs = GetTickCount();
      string hitId = HitButton((int)lparam, (int)dparam);
      if(hitId == "" && VerboseJournal)
         Print("[BK-FORGE] click at ", lparam, ",", dparam,
               " matched no control (", gButtonCount, " registered)");
      if(DuplicateClick(hitId))
        {
         if(VerboseJournal) Print("[BK-FORGE] ignored duplicate click -> ", hitId);
         return;
        }
      HandleHudAction(hitId);
     }

   if(id == CHARTEVENT_KEYDOWN)
     {
      // MT4 delivers virtual key codes, which match the uppercase ASCII values.
      if(lparam == 'P') { gPaused = !gPaused; Journal(gPaused ? "HOTKEY PAUSE" : "HOTKEY RESUME"); }
      if(lparam == 'H') gHudCollapsed = !gHudCollapsed;
      if(lparam == 'C') CloseAllOwn("HOTKEY CLOSE ALL");
      PaintAll(); ChartRedraw(0);
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      // Result cards are pixel-anchored, so they must re-resolve their
      // time/price anchor the moment the chart scrolls or zooms.
      gCardsDirty = true;
      DrawResultPills();
      DrawTradeLevelLines();
      PaintAll();
     }
  }

// ---- EMERGENCY FLOATING LOSS GUARD --------------------------------
// MaxDailyLossUSD is checked BEFORE a trade opens, so it can only ever
// bound losses that have already been realised. It cannot bound a position
// that is still open - which is precisely how one trade turned a +229 USD
// day into a -0.09 USD account. This runs on every tick and closes the book
// when the open drawdown breaches the cap.
void EnforceFloatingLossCap()
  {
   if(MaxOpenLossUSD <= 0) return;

   double floating = 0; int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      floating += OrderProfit() + OrderSwap() + OrderCommission();
      n++;
     }
   if(n == 0) return;

   // Cap the open loss on its own, and the open loss plus everything already
   // realised today, so a bad position cannot undo a good day either.
   bool hitOpen = (floating <= -MathAbs(MaxOpenLossUSD));
   bool hitDay  = (MaxDailyLossUSD > 0 &&
                   (gDayNet + floating) <= -MathAbs(MaxDailyLossUSD));
   if(!hitOpen && !hitDay) return;

   string why = hitOpen ? "OPEN LOSS CAP" : "DAY LOSS CAP (incl. open)";
   Print("[BK-FORGE] EMERGENCY CLOSE: ", why, " floating $",
         DoubleToString(floating, 2), " day $", DoubleToString(gDayNet, 2));
   CloseAllOwn(why);
   gBlockReason = T("LOSS CAP");
  }

//==================================================================//
//              O N   T I C K                                       //
//==================================================================//
void OnTick()
  {
   // Trailing first - identical order to Signal Forge PRO, and identical
   // code inside ManageTrailing().
   ManageTrailing();
   // Bound the OPEN loss on every tick, not just before the next entry.
   EnforceFloatingLossCap();
   if(Bars < 100) return;

   PushSpreadSample();
   TrackClosedTrades();

   bool graphics = (!IsTesting() || IsVisualMode());

   //--- intrabar --------------------------------------------------
   // The range levels and the distance meter are live, so they update
   // between bars; the ENTRY decision is not taken here.
   if(Time[0] == gLastBar)
     {
      UpdateRange();
      if(graphics)
        {
         uint tnow = GetTickCount();
               if(tnow - gLastHudPaint >= (uint)MathMax(100, HudRefreshMs))
           {
            DrawRangeObjects();
            DrawTradeLevelLines(); DrawResultPills(); PaintAll();
            gLastHudPaint = tnow;
           }
        }
      return;
     }
   gLastBar = Time[0];
   RollDailyCounters();

   int shift = TradeOnClosedBar ? 1 : 0;

   //--- rebuild the range on the new bar ---------------------------
   UpdateRange();

   //--- BREAKOUT STATE MACHINE -------------------------------------
   int dir = 0;
   bool wantEntry = false;

   if(gBkState == BK_RETEST)
     {
      // A pending retest either completes, dies, or times out.
      int r = RetestResult(shift);
      if(r == 1)
        {
         dir = gBkDir;
         wantEntry = true;
        }
      else if(r < 0 || (Bars - gBkBreakBar) > MathMax(1, RetestMaxBars))
        {
         gBkState = BK_READY;   // setup abandoned, wait for the next break
         gBkDir = 0; gBkLevel = 0;
        }
     }
   else if(gBkState == BK_TRADED || gBkState == BK_BROKEN)
     {
      // The range already produced a break. Watch the level for a failure
      // (re-arm) or a wick rejection (immediate re-entry).
      int rr = ReEntryResult(shift);
      if(rr == BK_REARM)
        {
         gBkFailedBreaks++;
         gBkState = BK_READY;        // level held as a range again
         gBkDir   = 0; gBkLevel = 0;
        }
      else if(rr != 0)
        {
         dir       = rr;             // CASE B - same-direction re-entry
         wantEntry = true;
        }
      else if(gBkState == BK_BROKEN)
        {
         // an untraded break can still flip to the other side
         int d2 = BreakDirection(shift);
         if(d2 != 0 && d2 != gBkDir)
           {
            gBkDir = d2; gBkLevel = (d2 > 0) ? gBkUpper : gBkLower;
            gBkBreakBar = Bars; dir = d2; wantEntry = true;
           }
        }
     }
   else if(gBkState == BK_READY)
     {
      dir = BreakDirection(shift);
      if(dir != 0)
        {
         gBkDir      = dir;
         gBkLevel    = (dir > 0) ? gBkUpper : gBkLower;
         gBkBreakBar = Bars;
         if(EntryMode == BK_ENTRY_RETEST)
           {
            gBkState = BK_RETEST;     // wait for the pullback
            dir = 0;                  // ...so do not enter yet
           }
         else
           {
            gBkState  = BK_BROKEN;
            wantEntry = true;
           }
        }
     }

   // The shared HUD reads gLongSignal/gShortSignal for its bias plate;
   // in this EA the bias IS the live breakout direction.
   gLongSignal  = (gBkDir > 0);
   gShortSignal = (gBkDir < 0);

   //--- gates ------------------------------------------------------
   // Run them even with no break so the HUD checklist stays live.
   string why = "";
   bool gatesPass = BreakoutGates((dir != 0) ? dir : gBkDir, why);
   gBkGateFail = gatesPass ? "" : why;
   gBlockReason = gatesPass ? "" : why;

   //--- visuals ----------------------------------------------------
   if(graphics)
     {
      DrawRangeObjects();
     }

   //--- flip out on an opposite break ------------------------------
   int curType = -1, curTicket = -1;
   int openCount = CountOwnPositions(curType, curTicket);
   if(CloseOnOppositeSignal && openCount > 0 && dir != 0)
     {
      if((curType == OP_BUY && dir < 0) || (curType == OP_SELL && dir > 0))
         if(CloseAllOwn("OPPOSITE BREAK")) openCount = 0;
     }

   //--- entry ------------------------------------------------------
   if(wantEntry && dir != 0 && gatesPass)
     {
      if(!OnePositionOnly || openCount == 0)
        {
         if(OpenPosition((dir > 0) ? OP_BUY : OP_SELL))
           {
            gBkTakenThis++;
            gBkState = BK_TRADED;
           }
        }
      else gBlockReason = T("POSITION OPEN");
     }

   //--- repaint ----------------------------------------------------
   if(graphics)
     {
      DrawRangeObjects();
      DrawTradeLevelLines();
      DrawResultPills();
      PaintAll();
      ChartRedraw(0);
     }
  }
//+------------------------------------------------------------------+