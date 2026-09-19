//+------------------------------------------------------------------+
//|                                  Signal Forge PRO XAUUSD M5 EA   |
//|                    QUANTUM HUD  ·  v2.03  ·  MQL4 / MetaTrader 4 |
//|------------------------------------------------------------------|
//| Evolution of "Signal Forge XAUUSD M5 EA".                        |
//| Original indicator concept: Signal Forge [LuxAlgo]               |
//| (c) LuxAlgo, CC BY-NC-SA 4.0 - non commercial ShareAlike port.    |
//| https://creativecommons.org/licenses/by-nc-sa/4.0/               |
//|------------------------------------------------------------------|
//| TUNED FOR : XAUUSD  M5  ·  Exness Raw Spread  ·  3-digit gold     |
//| ACCOUNT   : from 200 USD  (micro-account guardian built in)       |
//| COST MODEL: 3.50 USD / lot / side  ==  0.07 USD round turn / 0.01 |
//|             lot  ==  a constant 70 price points on a 3-digit feed |
//|------------------------------------------------------------------|
//| THIS IS NOT FINANCIAL ADVICE. FORWARD TEST ON DEMO FIRST.         |
//+------------------------------------------------------------------+
#property copyright "Signal Forge PRO - CC BY-NC-SA 4.0"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "2.03"
#property strict

#include <Canvas\Canvas.mqh>

//==================================================================//
//                          E N U M S                               //
//==================================================================//
enum ENUM_SF_CONFLUENCE
  {
   SF_CONF_SCORE   = 0, // Weighted score (recommended)
   SF_CONF_ALL     = 1, // All enabled filters must align
   SF_CONF_ANY     = 2  // Any enabled filter may fire
  };

enum ENUM_SF_SL
  {
   SF_SL_ATR       = 0, // ATR multiple
   SF_SL_STRUCTURE = 1, // Swing structure + ATR buffer
   SF_SL_FIXED     = 2, // Fixed points
   SF_SL_RISK      = 3  // Distance derived from risk money
  };

enum ENUM_SF_TP
  {
   SF_TP_ATR       = 0, // ATR multiple
   SF_TP_FIXED     = 1, // Fixed points
   SF_TP_COST      = 2  // Multiple of full round-turn cost
  };

enum ENUM_SF_TRAIL
  {
   SF_TRAIL_OFF        = 0, // Off
   SF_TRAIL_POINTS     = 1, // Classic step trailing (points)
   SF_TRAIL_ATR        = 2, // ATR distance trailing
   SF_TRAIL_CHANDELIER = 3  // Chandelier (highest high - k*ATR)
  };

enum ENUM_SF_SIZING
  {
   SF_SIZE_FIXED   = 0, // Fixed lots
   SF_SIZE_RISK    = 1, // Risk % of equity per trade (recommended)
   SF_SIZE_LADDER  = 2  // Balance ladder (one step per X USD)
  };

enum ENUM_SF_THEME
  {
   SF_THEME_QUANTUM = 0, // Quantum (cyan / violet on navy)
   SF_THEME_CARBON  = 1, // Carbon (lime / amber on graphite)
   SF_THEME_SOLAR   = 2  // Solar (gold / orange on charcoal)
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
input int    MagicNumber            = 260914;   // Magic number
input string TradeComment           = "SignalForgePRO";
input int    SlippagePoints         = 60;       // Max slippage (points)
input int    OrderRetries           = 3;        // Send/modify retries
input bool   TradeOnClosedBar       = true;     // Evaluate on closed bar only
input bool   OnePositionOnly        = true;     // Only one position at a time
input bool   CloseOnOppositeSignal  = true;     // Flip out on opposite signal
input int    MinBarsBetweenTrades   = 3;        // Cooldown bars between entries

input string __02 = "======== BROKER COST MODEL (EXNESS RAW) ========"; // .
input double CommissionPer001LotRT  = 0.07;     // USD round-turn commission per 0.01 lot
input int    MaxSpreadPoints        = 130;      // Hard spread cap (points, 3-digit gold)
input bool   UseAdaptiveSpreadCap   = true;     // Also cap at k x median spread
input double AdaptiveSpreadFactor   = 2.2;      // k for adaptive spread cap
input double MinTPtoCostRatio       = 3.0;      // TP must be >= this x round-turn cost
input bool   BreakEvenIncludesCost  = true;     // True break-even = entry + spread + commission

input string __03 = "======== MICRO ACCOUNT / POSITION SIZING ========"; // .
input ENUM_SF_SIZING SizingMode     = SF_SIZE_RISK; // Lot sizing mode
input double FixedLots              = 0.01;     // Fixed lots (SF_SIZE_FIXED)
input double RiskPercent            = 1.0;      // Risk % per trade
input double MaxRiskPercentHardCap  = 2.0;      // Never risk more than this %
input bool   AllowMinLotOverride    = false;    // Take min-lot trade even if it breaks the cap
input double LadderStepUSD          = 200.0;    // +0.01 lot per this much balance (LADDER)
input double MaxLots                = 1.00;     // Absolute lot ceiling
input double MinAccountBalanceUSD   = 150.0;    // Hard stop below this balance
input bool   UseEquityForRisk       = true;     // Size from equity instead of balance
input double RiskReferenceBalance   = 0.0;      // 0 = live balance/equity

input string __04 = "======== RISK GUARDIANS ========"; // .
input double DailyLossLimitPercent  = 6.0;      // Stop trading after -x% day (0=off)
input double DailyProfitTargetPct   = 6.0;      // Stop trading after +x% day (0=off)
input int    MaxTradesPerDay        = 6;        // Max new trades per day (0=off)
input int    MaxConsecutiveLosses   = 3;        // Losses before cooldown (0=off)
input int    CooldownMinutes        = 60;       // Cooldown length after loss streak
input double MaxDailyDrawdownPct    = 10.0;     // Equity drawdown kill-switch (0=off)
input bool   ReduceRiskAfterLoss    = true;     // Step risk down after a losing trade
input double LossRiskFactor         = 0.6;      // Risk multiplier while recovering

input string __05 = "======== SESSION / TIME FILTER (SERVER = GMT) ========"; // .
input bool   UseSessionFilter       = true;     // Trade only inside the windows below
input int    ServerGMTOffsetHours   = 0;        // Exness MT4 server is GMT+0
input bool   TradeLondon            = true;     // London window
input int    LondonStartHour        = 7;        // London start (server hour)
input int    LondonEndHour          = 12;       // London end
input bool   TradeOverlap           = true;     // London/NY overlap - best gold liquidity
input int    OverlapStartHour       = 12;       // Overlap start
input int    OverlapEndHour         = 17;       // Overlap end
input bool   TradeNewYork           = true;     // New York afternoon
input int    NewYorkStartHour       = 17;       // NY start
input int    NewYorkEndHour         = 20;       // NY end
input bool   TradeAsia              = false;    // Asia (low liquidity, wide spread)
input int    AsiaStartHour          = 0;        // Asia start
input int    AsiaEndHour            = 6;        // Asia end
input bool   AvoidRollover          = true;     // Skip the swap/rollover window
input int    RolloverStartHour      = 20;       // Rollover blackout start
input int    RolloverEndHour        = 22;       // Rollover blackout end
input bool   CloseBeforeWeekend     = true;     // Flatten before the weekend
input int    FridayCloseHour        = 19;       // Friday flatten hour
input bool   FlattenAtSessionEnd    = false;    // Flatten when the last window closes
input string ManualBlackout         = "";       // e.g. "12:25-12:45,18:00-18:15"

input string __06 = "======== VOLATILITY REGIME ========"; // .
input bool   UseVolatilityFilter    = true;     // Require a healthy ATR regime
input int    ATRLength              = 14;       // Fast ATR
input int    ATRRegimeLength        = 50;       // Slow ATR baseline
input double MinATRRatio            = 0.70;     // Skip dead markets below this ratio
input double MaxATRRatio            = 2.60;     // Skip news explosions above this ratio
input double MinATRPoints           = 350.0;    // Absolute ATR floor (points)

input string __07 = "======== CONFLUENCE ENGINE ========"; // .
input ENUM_SF_CONFLUENCE ConfluenceMode = SF_CONF_SCORE; // Aggregation mode
input double EntryScoreThreshold    = 62.0;     // |score| needed to arm (0..100)
input bool   RequireFreshCross      = true;     // Only trade the bar the score crosses
input bool   RequireHTFAlignment    = true;     // HTF bias must agree with the trade
input int    HTFTimeframeMinutes    = 60;       // Higher timeframe (60 = H1)
input int    HTFFastEMA             = 21;       // HTF fast EMA
input int    HTFSlowEMA             = 55;       // HTF slow EMA

input string __08 = "======== FILTERS : ENABLE + WEIGHT ========"; // .
input bool   EnableSMA              = false;
input double WeightSMA        = 1.0;
input int    SMAFastLength          = 9;
input int    SMASlowLength    = 30;
input bool   EnableRSI              = true;
input double WeightRSI        = 1.5;
input int    RSILength              = 14;
input double RSILongAbove     = 52.0;
input double RSIShortBelow          = 48.0;
input bool   EnableMACD             = true;
input double WeightMACD       = 1.5;
input int    MACDFastLength         = 8;
input int    MACDSlowLength   = 21;
input int    MACDSignalLength       = 5;
input bool   EnableSupertrend       = true;
input double WeightSupertrend = 3.0;
input double SupertrendFactor       = 2.5;
input int    SupertrendLength = 10;
input bool   EnableStochastic       = false;
input double WeightStochastic = 1.0;
input int    StochasticKLength      = 14;
input int    StochasticDLength= 3;
input int    StochasticSmooth       = 3;
input bool   EnableBollinger        = false;
input double WeightBollinger  = 1.0;
input int    BollingerLength        = 20;
input bool   EnableEMA              = true;
input double WeightEMA        = 2.0;
input int    EMAFastLength          = 9;
input int    EMASlowLength    = 21;
input bool   EnableAO               = false;
input double WeightAO         = 1.0;
input bool   EnableSAR              = false;
input double WeightSAR        = 1.0;
input double SARStep                = 0.02;
input double SARMaximum       = 0.2;
input bool   EnableCCI              = false;
input double WeightCCI        = 1.0;
input int    CCILength              = 20;
input double CCILongAbove     = 50.0;
input double CCIShortBelow          = -50.0;
input bool   EnableADX              = true;
input double WeightADX        = 2.0;
input int    ADXPeriod              = 14;
input double ADXThreshold     = 22.0;
input bool   EnableHTFBias          = true;
input double WeightHTFBias    = 2.5;
input bool   EnableStructure        = true;
input double WeightStructure  = 2.0;
input int    StructureLookback      = 20;     // Donchian break lookback
input bool   EnableVWAP             = true;
input double WeightVWAP       = 1.5;

input string __09 = "======== STOP LOSS / TAKE PROFIT ========"; // .
input ENUM_SF_SL StopLossMode       = SF_SL_ATR;   // Stop loss engine
input double StopLossATR            = 1.6;      // ATR multiple for SL
input double StructureBufferATR     = 0.35;     // Extra ATR buffer beyond the swing
input int    StructureSwingBars     = 12;       // Swing lookback for structure SL
input double StopLossPoints         = 1500.0;   // Fixed SL (points)
input ENUM_SF_TP TakeProfitMode     = SF_TP_ATR;   // Take profit engine
input double TakeProfitATR          = 2.6;      // ATR multiple for TP
input double TakeProfitPoints       = 4000.0;   // Fixed TP (points)
input double TakeProfitCostMultiple = 12.0;     // TP = x * round-turn cost (SF_TP_COST)

input string __10 = "======== TRADE MANAGEMENT ========"; // .
input bool   UseBreakEven           = true;     // Move stop to true break-even
input double BreakEvenTriggerATR    = 1.0;      // Trigger at x ATR in profit
input double BreakEvenLockPoints    = 30.0;     // Extra points locked beyond cost
input bool   UsePartialClose        = true;     // Bank part of the trade at TP1
input double PartialTriggerATR      = 1.4;      // TP1 distance in ATR
input double PartialClosePercent    = 50.0;     // % of volume closed at TP1
input ENUM_SF_TRAIL TrailingMode    = SF_TRAIL_CHANDELIER; // Trailing engine
input double TrailingStartPoints    = 700.0;    // Start trailing after x points
input double TrailingDistancePoints = 450.0;    // Distance (SF_TRAIL_POINTS)
input double TrailingStepPoints     = 80.0;     // Min improvement per update
input double TrailingATRMultiple    = 2.0;      // ATR distance / chandelier k
input int    ChandelierLookback     = 14;       // Bars for chandelier extreme
input bool   UseTimeStop            = true;     // Close stagnant trades
input int    TimeStopBars           = 36;       // Bars before the time stop
input double TimeStopMinProgressR   = 0.30;     // Needs this R to survive

input string __11 = "======== QUANTUM HUD (INTERFACE) ========"; // .
input bool   ShowHUD                = true;     // Master HUD switch
input ENUM_SF_THEME HudTheme        = SF_THEME_QUANTUM; // Colour theme
input bool   ApplyChartSkin         = true;     // Re-skin the chart
input bool   ShowHeaderPanel        = true;     // Top command bar
input bool   ShowSignalPanel        = true;     // Confluence core
input bool   ShowRiskPanel          = true;     // Risk console
input bool   ShowPerformancePanel   = true;     // Performance + equity curve
input bool   ShowTradePanel         = true;     // Live trade ticket
input ENUM_SF_FILTERVIEW FilterView = SF_VIEW_ACTIVE; // Filter list mode
input int    HudMargin              = 12;       // Outer margin (px)
input int    HudRefreshMs           = 220;      // Repaint interval (ms)
input bool   HudInteractive         = true;     // Buttons + hover + hotkeys
input int    HudScalePercent        = 100;      // 80..130 UI scale

input string __12 = "======== CHART VISUALS ========"; // .
input bool   DrawSignalOrbs         = true;     // Buy/Sell orbs
input int    SignalHistoryBars      = 250;      // Historic orbs
input int    SignalOrbSize          = 16;       // Orb radius (px)
input bool   DrawTradeLevels        = true;     // Entry/SL/TP lines
input bool   DrawTradeResults       = true;     // Closed trade result cards
input int    MaxResultPills         = 25;       // Max result cards on chart
input int    ResultCardFontSize     = 9;        // Result card font size
input int    ResultCardWidth        = 172;      // Result card width (px)
input int    ResultCardPadding      = 7;        // Result card text padding (px)
input bool   ShowLiveTradeCard      = true;     // Live card while a trade is open
input int    ResultCardGapPx        = 18;       // Min gap from candles (px)
input bool   DrawIndicatorOverlay   = true;     // Plot active filters
input int    OverlayBars            = 180;      // Bars plotted
input bool   KeepVisualsAfterTest   = true;     // Keep graphics after a visual test

input string __13 = "======== ALERTS ========"; // .
input bool   AlertOnEntry           = false;    // Popup/sound on entry
input bool   PushOnEntry            = false;    // Push notification on entry
input bool   VerboseJournal         = true;     // Detailed journal logging

//==================================================================//
//                    G L O B A L   S T A T E                       //
//==================================================================//
#define SF_FILTERS 14

// Win32 GDI text-alignment and font-weight values, spelled out so the EA
// compiles on every MT4 build regardless of which TA_/FW_ enums it exposes.
#define SF_AL_LEFT     0
#define SF_AL_RIGHT    2
#define SF_AL_CENTER   6
#define SF_AL_TOP      0
#define SF_FW_NORMAL   400
#define SF_FW_SEMI     600
#define SF_FW_BLACK    900

string   PFX = "SFP_";
string   gFilterName[SF_FILTERS];

//--- signal state
int      gBull[SF_FILTERS], gBear[SF_FILTERS];
double   gWeight[SF_FILTERS];
bool     gEnabled[SF_FILTERS];
double   gScore = 0.0, gPrevScore = 0.0;  // gPrevScore = last bar conviction
bool     gLongSignal = false, gShortSignal = false;
int      gHTFBias = 0;

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

//--- runtime / guardians
datetime gLastBar = 0;
datetime gLastTradeBar = 0;
datetime gCooldownUntil = 0;
datetime gDayStamp = 0;
double   gDayStartEquity = 0.0;
double   gDayPeakEquity = 0.0;
int      gDayTrades = 0;
double   gDayNet = 0.0;
int      gConsecLosses = 0;
bool     gHalted = false;
string   gHaltReason = "";
string   gLastAction = "EA INITIALISED";
string   gBlockReason = "";
int      gLastHistoryCount = -1;

//--- partial / management bookkeeping.
//    Keyed on OrderOpenTime(), NOT the ticket: MT4 issues a brand new ticket
//    for the remainder after a partial close, while the open time survives.
datetime gPartialDone[64];
int      gPartialCount = 0;
datetime gBEDone[64];
int      gBECount = 0;

//--- blackout windows
int      gBlackStart[16], gBlackEnd[16], gBlackCount = 0;

//--- supertrend incremental cache
bool     gSTReady = false;
double   gSTUpper = 0, gSTLower = 0, gSTLine = 0, gSTClose = 0;
int      gSTDir = 0, gSTPrevDir = 0;
datetime gSTTime = 0, gSTPrevTime = 0;

//--- HUD
CCanvas  gHud;
bool     gHudReady = false;
int      gHudW = 0, gHudH = 0;
uint     gLastHudPaint = 0;
bool     gHudCollapsed = false;
int      gHudPage = 0;          // 0 = core, 1 = filters, 2 = journal
bool     gShowAllFilters = false;
bool     gPaused = false;
int      gMouseX = -1, gMouseY = -1;   // chart-space cursor, for hover + click fallback
string   gHoverId = "";
datetime gSignalHistoryBuilt = 0;
int      gKnownResultHistory = -1;
bool     gCardsDirty = true;      // force a closed-card rebuild (chart moved)

//--- stats cache
int      gStatHistory = -1;
int      gStatTrades = 0, gStatWins = 0, gStatLosses = 0;
double   gStatNet = 0, gStatGP = 0, gStatGL = 0, gStatMaxDD = 0;
double   gStatBestTrade = 0, gStatWorstTrade = 0;
double   gStatCommission = 0;
double   gStatToday = 0, gStatWeek = 0, gStatMonth = 0;
double   gEquityCurve[512];
int      gEquityPoints = 0;

//--- PERFORMANCE TRACKER: last N trading days, newest first
#define SF_TRACK_DAYS 6
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
   switch(HudTheme)
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
double CommissionRT(double lots)
  {
   return (lots / 0.01) * CommissionPer001LotRT;
  }

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
   if(VerboseJournal) Print("[SF-PRO] ", msg);
  }

string Fmt(double v, int d) { return DoubleToString(v, d); }
string Signed(double v, int d) { return (v >= 0 ? "+" : "") + DoubleToString(v, d); }

double NormalizeLots(double lots)
  {
   lots = MathMax(gMinLot, MathMin(MathMin(gMaxLot, MaxLots), lots));
   lots = MathFloor(lots / gLotStep + 1e-8) * gLotStep;
   return NormalizeDouble(lots, 2);
  }

double MinStopDistance()
  {
   return (gStopLevel + 2) * gPoint;
  }

double RiskCapital()
  {
   if(RiskReferenceBalance > 0) return RiskReferenceBalance;
   return UseEquityForRisk ? AccountEquity() : AccountBalance();
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
//                 S E S S I O N   /   T I M E                      //
//==================================================================//
void ParseBlackout()
  {
   gBlackCount = 0;
   string s = ManualBlackout;
   StringTrimLeft(s); StringTrimRight(s);
   if(StringLen(s) < 5) return;
   string parts[];
   int n = StringSplit(s, ',', parts);
   for(int i = 0; i < n && gBlackCount < 16; i++)
     {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      int dash = StringFind(p, "-");
      if(dash < 0) continue;
      string a = StringSubstr(p, 0, dash);
      string b = StringSubstr(p, dash + 1);
      int ca = StringFind(a, ":"), cb = StringFind(b, ":");
      if(ca < 0 || cb < 0) continue;
      int m1 = (int)StringToInteger(StringSubstr(a, 0, ca)) * 60 + (int)StringToInteger(StringSubstr(a, ca + 1));
      int m2 = (int)StringToInteger(StringSubstr(b, 0, cb)) * 60 + (int)StringToInteger(StringSubstr(b, cb + 1));
      gBlackStart[gBlackCount] = m1;
      gBlackEnd[gBlackCount]   = m2;
      gBlackCount++;
     }
  }

bool InHourWindow(int hour, int start, int end)
  {
   if(start == end) return false;
   if(start < end)  return (hour >= start && hour < end);
   return (hour >= start || hour < end);   // window wraps midnight
  }

// Session windows are expressed in GMT. Exness MT4 servers run at GMT+0, so
// the default offset is zero; other brokers just set their own offset once.
int GmtHourNow()
  {
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   int h = d.hour - ServerGMTOffsetHours;
   while(h < 0)   h += 24;
   while(h >= 24) h -= 24;
   return h;
  }

string ActiveSessionName()
  {
   int h = GmtHourNow();
   if(TradeOverlap && InHourWindow(h, OverlapStartHour, OverlapEndHour)) return "OVERLAP";
   if(TradeLondon  && InHourWindow(h, LondonStartHour,  LondonEndHour))  return "LONDON";
   if(TradeNewYork && InHourWindow(h, NewYorkStartHour, NewYorkEndHour)) return "NEW YORK";
   if(TradeAsia    && InHourWindow(h, AsiaStartHour,    AsiaEndHour))    return "ASIA";
   return "CLOSED";
  }

bool SessionAllows(string &why)
  {
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   int h = GmtHourNow(), minutes = h * 60 + d.min;

   for(int i = 0; i < gBlackCount; i++)
      if(minutes >= gBlackStart[i] && minutes < gBlackEnd[i])
        { why = "MANUAL BLACKOUT"; return false; }

   if(AvoidRollover && InHourWindow(h, RolloverStartHour, RolloverEndHour))
     { why = "ROLLOVER WINDOW"; return false; }

   if(CloseBeforeWeekend && d.day_of_week == 5 && h >= FridayCloseHour)
     { why = "WEEKEND GUARD"; return false; }

   if(d.day_of_week == 0 || d.day_of_week == 6)
     { why = "MARKET CLOSED"; return false; }

   if(!UseSessionFilter) return true;

   bool ok = false;
   if(TradeLondon  && InHourWindow(h, LondonStartHour,  LondonEndHour))  ok = true;
   if(TradeOverlap && InHourWindow(h, OverlapStartHour, OverlapEndHour)) ok = true;
   if(TradeNewYork && InHourWindow(h, NewYorkStartHour, NewYorkEndHour)) ok = true;
   if(TradeAsia    && InHourWindow(h, AsiaStartHour,    AsiaEndHour))    ok = true;
   if(!ok) { why = "OUT OF SESSION"; return false; }
   return true;
  }

//==================================================================//
//              V O L A T I L I T Y   R E G I M E                   //
//==================================================================//
double ATRPoints(int shift)
  {
   return iATR(NULL, 0, MathMax(1, ATRLength), shift) / gPoint;
  }

double ATRRatio(int shift)
  {
   double fast = iATR(NULL, 0, MathMax(1, ATRLength), shift);
   double slow = iATR(NULL, 0, MathMax(2, ATRRegimeLength), shift);
   if(slow <= 0) return 1.0;
   return fast / slow;
  }

bool VolatilityAllows(int shift, string &why)
  {
   if(!UseVolatilityFilter) return true;
   double pts = ATRPoints(shift);
   if(pts < MinATRPoints) { why = "ATR TOO LOW"; return false; }
   double r = ATRRatio(shift);
   if(r < MinATRRatio)    { why = "DEAD REGIME";  return false; }
   if(r > MaxATRRatio)    { why = "NEWS SPIKE";   return false; }
   return true;
  }

//==================================================================//
//                    S U P E R T R E N D                           //
//==================================================================//
void AdvanceST(int shift)
  {
   double atr   = iATR(NULL, 0, MathMax(1, SupertrendLength), shift);
   double mid   = (High[shift] + Low[shift]) * 0.5;
   double up    = mid + SupertrendFactor * atr;
   double dn    = mid - SupertrendFactor * atr;
   double fu = up, fl = dn, line = up;
   int dir = 1;
   if(!gSTReady || atr <= 0) { if(atr > 0) gSTReady = true; }
   else
     {
      fu = (up < gSTUpper || gSTClose > gSTUpper) ? up : gSTUpper;
      fl = (dn > gSTLower || gSTClose < gSTLower) ? dn : gSTLower;
      if(gSTLine == gSTUpper) line = (Close[shift] > fu) ? fl : fu;
      else                    line = (Close[shift] < fl) ? fu : fl;
      dir = (line == fl) ? -1 : 1;
     }
   gSTPrevTime = gSTTime; gSTPrevDir = gSTDir;
   gSTUpper = fu; gSTLower = fl; gSTLine = line; gSTClose = Close[shift];
   gSTDir = gSTReady ? dir : 0;
   gSTTime = Time[shift];
  }

int SupertrendDir(int shift)
  {
   if(Time[shift] == gSTTime)     return gSTDir;
   if(Time[shift] == gSTPrevTime) return gSTPrevDir;
   if(gSTTime != 0 && shift + 1 < Bars && Time[shift + 1] == gSTTime)
     { AdvanceST(shift); return gSTDir; }
   gSTReady = false; gSTUpper = 0; gSTLower = 0; gSTLine = 0; gSTClose = 0;
   gSTDir = 0; gSTPrevDir = 0; gSTTime = 0; gSTPrevTime = 0;
   int oldest = MathMin(Bars - 2, shift + 600);
   for(int i = oldest; i >= shift; i--) AdvanceST(i);
   return gSTDir;
  }

//==================================================================//
//                 S U P P O R T   S T U D I E S                    //
//==================================================================//
// Session-anchored VWAP: resets each trading day, the reference
// institutional traders actually defend on gold intraday.
double SessionVWAP(int shift)
  {
   datetime day = DayStart(Time[shift]);
   double pv = 0, vol = 0;
   for(int i = shift; i < Bars && i < shift + 400; i++)
     {
      if(Time[i] < day) break;
      double typical = (High[i] + Low[i] + Close[i]) / 3.0;
      double v = (double)MathMax(1, Volume[i]);
      pv  += typical * v;
      vol += v;
     }
   if(vol <= 0) return Close[shift];
   return pv / vol;
  }

int HTFBias(int shift)
  {
   int tf = MathMax(Period(), HTFTimeframeMinutes);
   int hs = iBarShift(Symbol(), tf, Time[shift], false);
   if(hs < 0) hs = 0;
   double f = iMA(NULL, tf, MathMax(1, HTFFastEMA), 0, MODE_EMA, PRICE_CLOSE, hs);
   double s = iMA(NULL, tf, MathMax(2, HTFSlowEMA), 0, MODE_EMA, PRICE_CLOSE, hs);
   if(f > s) return  1;
   if(f < s) return -1;
   return 0;
  }

double DonchianHigh(int shift, int look)
  {
   int idx = iHighest(NULL, 0, MODE_HIGH, look, shift + 1);
   if(idx < 0) return High[shift];
   return High[idx];
  }

double DonchianLow(int shift, int look)
  {
   int idx = iLowest(NULL, 0, MODE_LOW, look, shift + 1);
   if(idx < 0) return Low[shift];
   return Low[idx];
  }

//==================================================================//
//              C O N F L U E N C E   E N G I N E                   //
//==================================================================//
void LoadFilterConfig()
  {
   gFilterName[0]="SMA CROSS";   gEnabled[0]=EnableSMA;        gWeight[0]=WeightSMA;
   gFilterName[1]="RSI";         gEnabled[1]=EnableRSI;        gWeight[1]=WeightRSI;
   gFilterName[2]="MACD";        gEnabled[2]=EnableMACD;       gWeight[2]=WeightMACD;
   gFilterName[3]="SUPERTREND";  gEnabled[3]=EnableSupertrend; gWeight[3]=WeightSupertrend;
   gFilterName[4]="STOCHASTIC";  gEnabled[4]=EnableStochastic; gWeight[4]=WeightStochastic;
   gFilterName[5]="BOLLINGER";   gEnabled[5]=EnableBollinger;  gWeight[5]=WeightBollinger;
   gFilterName[6]="EMA CROSS";   gEnabled[6]=EnableEMA;        gWeight[6]=WeightEMA;
   gFilterName[7]="AWESOME OSC"; gEnabled[7]=EnableAO;         gWeight[7]=WeightAO;
   gFilterName[8]="PARABOLIC SAR";gEnabled[8]=EnableSAR;       gWeight[8]=WeightSAR;
   gFilterName[9]="CCI";         gEnabled[9]=EnableCCI;        gWeight[9]=WeightCCI;
   gFilterName[10]="ADX / DI";   gEnabled[10]=EnableADX;       gWeight[10]=WeightADX;
   gFilterName[11]="HTF BIAS";   gEnabled[11]=EnableHTFBias;   gWeight[11]=WeightHTFBias;
   gFilterName[12]="STRUCTURE";  gEnabled[12]=EnableStructure; gWeight[12]=WeightStructure;
   gFilterName[13]="VWAP";       gEnabled[13]=EnableVWAP;      gWeight[13]=WeightVWAP;
   for(int i = 0; i < SF_FILTERS; i++)
      if(gWeight[i] < 0) gWeight[i] = 0;
  }

void EvaluateFilters(int shift, int &bull[], int &bear[])
  {
   for(int i = 0; i < SF_FILTERS; i++) { bull[i] = 0; bear[i] = 0; }

   // 0 SMA
   double a = iMA(NULL,0,MathMax(1,SMAFastLength),0,MODE_SMA,PRICE_CLOSE,shift);
   double b = iMA(NULL,0,MathMax(2,SMASlowLength),0,MODE_SMA,PRICE_CLOSE,shift);
   bull[0] = (a > b) ? 1 : 0; bear[0] = (a < b) ? 1 : 0;

   // 1 RSI
   double r = iRSI(NULL,0,MathMax(1,RSILength),PRICE_CLOSE,shift);
   bull[1] = (r > RSILongAbove) ? 1 : 0; bear[1] = (r < RSIShortBelow) ? 1 : 0;

   // 2 MACD
   double m  = iMACD(NULL,0,MACDFastLength,MACDSlowLength,MACDSignalLength,PRICE_CLOSE,MODE_MAIN,shift);
   double ms = iMACD(NULL,0,MACDFastLength,MACDSlowLength,MACDSignalLength,PRICE_CLOSE,MODE_SIGNAL,shift);
   bull[2] = (m > ms && m > 0) ? 1 : 0; bear[2] = (m < ms && m < 0) ? 1 : 0;

   // 3 Supertrend
   int sd = SupertrendDir(shift);
   bull[3] = (sd == -1) ? 1 : 0; bear[3] = (sd == 1) ? 1 : 0;

   // 4 Stochastic
   double k = iStochastic(NULL,0,StochasticKLength,StochasticDLength,StochasticSmooth,MODE_SMA,0,MODE_MAIN,shift);
   double dd= iStochastic(NULL,0,StochasticKLength,StochasticDLength,StochasticSmooth,MODE_SMA,0,MODE_SIGNAL,shift);
   bull[4] = (k > dd && k > 45) ? 1 : 0; bear[4] = (k < dd && k < 55) ? 1 : 0;

   // 5 Bollinger (mid-band bias)
   double mid = iBands(NULL,0,MathMax(2,BollingerLength),2.0,0,PRICE_CLOSE,MODE_MAIN,shift);
   bull[5] = (Close[shift] > mid) ? 1 : 0; bear[5] = (Close[shift] < mid) ? 1 : 0;

   // 6 EMA
   double ef = iMA(NULL,0,MathMax(1,EMAFastLength),0,MODE_EMA,PRICE_CLOSE,shift);
   double es = iMA(NULL,0,MathMax(2,EMASlowLength),0,MODE_EMA,PRICE_CLOSE,shift);
   bull[6] = (ef > es) ? 1 : 0; bear[6] = (ef < es) ? 1 : 0;

   // 7 Awesome Oscillator
   double ao = iAO(NULL,0,shift), ao1 = iAO(NULL,0,shift+1);
   bull[7] = (ao > 0 && ao >= ao1) ? 1 : 0; bear[7] = (ao < 0 && ao <= ao1) ? 1 : 0;

   // 8 Parabolic SAR
   double sar = iSAR(NULL,0,SARStep,SARMaximum,shift);
   bull[8] = (Close[shift] > sar) ? 1 : 0; bear[8] = (Close[shift] < sar) ? 1 : 0;

   // 9 CCI
   double cci = iCCI(NULL,0,MathMax(2,CCILength),PRICE_CLOSE,shift);
   bull[9] = (cci > CCILongAbove) ? 1 : 0; bear[9] = (cci < CCIShortBelow) ? 1 : 0;

   // 10 ADX / DI - trend strength gate
   double adx = iADX(NULL,0,MathMax(2,ADXPeriod),PRICE_CLOSE,MODE_MAIN,shift);
   double dp  = iADX(NULL,0,MathMax(2,ADXPeriod),PRICE_CLOSE,MODE_PLUSDI,shift);
   double dm  = iADX(NULL,0,MathMax(2,ADXPeriod),PRICE_CLOSE,MODE_MINUSDI,shift);
   bull[10] = (adx > ADXThreshold && dp > dm) ? 1 : 0;
   bear[10] = (adx > ADXThreshold && dm > dp) ? 1 : 0;

   // 11 Higher timeframe bias
   int hb = HTFBias(shift);
   gHTFBias = hb;
   bull[11] = (hb ==  1) ? 1 : 0; bear[11] = (hb == -1) ? 1 : 0;

   // 12 Market structure (Donchian break / position)
   double dh = DonchianHigh(shift, MathMax(3, StructureLookback));
   double dl = DonchianLow(shift,  MathMax(3, StructureLookback));
   double mid2 = (dh + dl) * 0.5;
   bull[12] = (Close[shift] > mid2 && Close[shift] >= dh - (dh - dl) * 0.25) ? 1 : 0;
   bear[12] = (Close[shift] < mid2 && Close[shift] <= dl + (dh - dl) * 0.25) ? 1 : 0;

   // 13 Session VWAP
   double vw = SessionVWAP(shift);
   bull[13] = (Close[shift] > vw) ? 1 : 0; bear[13] = (Close[shift] < vw) ? 1 : 0;
  }

// Returns a normalised -100..+100 conviction score.
double ConfluenceScore(int &bull[], int &bear[])
  {
   double total = 0, net = 0;
   for(int i = 0; i < SF_FILTERS; i++)
     {
      if(!gEnabled[i] || gWeight[i] <= 0) continue;
      total += gWeight[i];
      if(bull[i]) net += gWeight[i];
      if(bear[i]) net -= gWeight[i];
     }
   if(total <= 0) return 0.0;
   return (net / total) * 100.0;
  }

void ResolveSignal(int &bull[], int &bear[], double score, bool &lng, bool &sht)
  {
   lng = false; sht = false;
   if(ConfluenceMode == SF_CONF_SCORE)
     {
      lng = (score >=  EntryScoreThreshold);
      sht = (score <= -EntryScoreThreshold);
     }
   else if(ConfluenceMode == SF_CONF_ALL)
     {
      bool any = false; lng = true; sht = true;
      for(int i = 0; i < SF_FILTERS; i++)
        {
         if(!gEnabled[i]) continue;
         any = true;
         lng = (lng && bull[i] == 1);
         sht = (sht && bear[i] == 1);
        }
      if(!any) { lng = false; sht = false; }
     }
   else
     {
      for(int i = 0; i < SF_FILTERS; i++)
        {
         if(!gEnabled[i]) continue;
         if(bull[i]) lng = true;
         if(bear[i]) sht = true;
        }
     }
   if(lng && sht) { lng = false; sht = false; }

   if(RequireHTFAlignment && EnableHTFBias)
     {
      if(lng && gHTFBias < 0) lng = false;
      if(sht && gHTFBias > 0) sht = false;
     }
  }

//==================================================================//
//              R I S K   G U A R D I A N S                         //
//==================================================================//
void RollDailyCounters()
  {
   datetime today = DayStart(TimeCurrent());
   if(today == gDayStamp) return;
   gDayStamp        = today;
   gDayStartEquity  = AccountEquity();
   gDayPeakEquity   = AccountEquity();
   gDayTrades       = 0;
   gDayNet          = 0.0;
   if(gHalted && (gHaltReason == "DAILY LOSS LIMIT" ||
                  gHaltReason == "DAILY TARGET HIT" ||
                  gHaltReason == "MAX TRADES/DAY"   ||
                  gHaltReason == "EQUITY DRAWDOWN"))
     { gHalted = false; gHaltReason = ""; Journal("NEW DAY - GUARDIANS RESET"); }
  }

double DayPnLPercent()
  {
   if(gDayStartEquity <= 0) return 0;
   return (AccountEquity() - gDayStartEquity) / gDayStartEquity * 100.0;
  }

double DayDrawdownPercent()
  {
   if(gDayPeakEquity <= 0) return 0;
   return (gDayPeakEquity - AccountEquity()) / gDayPeakEquity * 100.0;
  }

void UpdateGuardians()
  {
   RollDailyCounters();
   gDayPeakEquity = MathMax(gDayPeakEquity, AccountEquity());

   if(AccountBalance() < MinAccountBalanceUSD)
     { gHalted = true; gHaltReason = "BALANCE FLOOR"; return; }

   if(MaxDailyDrawdownPct > 0 && DayDrawdownPercent() >= MaxDailyDrawdownPct)
     { if(!gHalted) Journal("KILL SWITCH: DAILY EQUITY DD");
       gHalted = true; gHaltReason = "EQUITY DRAWDOWN"; return; }

   if(DailyLossLimitPercent > 0 && DayPnLPercent() <= -DailyLossLimitPercent)
     { if(!gHalted) Journal("GUARDIAN: DAILY LOSS LIMIT");
       gHalted = true; gHaltReason = "DAILY LOSS LIMIT"; return; }

   if(DailyProfitTargetPct > 0 && DayPnLPercent() >= DailyProfitTargetPct)
     { if(!gHalted) Journal("GUARDIAN: DAILY TARGET REACHED");
       gHalted = true; gHaltReason = "DAILY TARGET HIT"; return; }

   if(MaxTradesPerDay > 0 && gDayTrades >= MaxTradesPerDay)
     { gHalted = true; gHaltReason = "MAX TRADES/DAY"; return; }
  }

bool InCooldown()
  {
   return (gCooldownUntil > 0 && TimeCurrent() < gCooldownUntil);
  }

//==================================================================//
//              P O S I T I O N   S I Z I N G                       //
//==================================================================//
// Risk-based sizing that *includes* the Exness commission in the loss
// budget. A 0.01-lot gold trade already costs 0.07 USD before it moves,
// which is 0.035% of a 200 USD account - small, but on a 30-trade month
// it is a full 1% of the account. Ignoring it overstates position size.
double CalculateLots(double slDistancePrice, double &riskUsed, string &note)
  {
   note = "";
   double capital = RiskCapital();
   if(capital <= 0) { riskUsed = 0; note = "NO CAPITAL"; return 0; }

   if(SizingMode == SF_SIZE_FIXED)
     {
      double lf = NormalizeLots(FixedLots);
      riskUsed = (PointValue(lf) * (slDistancePrice / gPoint) + CommissionRT(lf)) / capital * 100.0;
      note = "FIXED";
      return lf;
     }

   if(SizingMode == SF_SIZE_LADDER)
     {
      double steps = MathFloor(capital / MathMax(1.0, LadderStepUSD));
      double ll = NormalizeLots(MathMax(gMinLot, steps * gLotStep));
      riskUsed = (PointValue(ll) * (slDistancePrice / gPoint) + CommissionRT(ll)) / capital * 100.0;
      note = "LADDER";
      return ll;
     }

   // ---- risk percent ----
   double pct = MathMin(RiskPercent, MaxRiskPercentHardCap);
   if(ReduceRiskAfterLoss && gConsecLosses > 0)
      pct *= MathMax(0.1, MathPow(LossRiskFactor, MathMin(3, gConsecLosses)));
   double riskMoney = capital * pct / 100.0;
   if(riskMoney <= 0) { riskUsed = 0; note = "ZERO RISK"; return 0; }

   double slPoints = slDistancePrice / gPoint;
   if(slPoints <= 0) { riskUsed = 0; note = "BAD SL"; return 0; }

   // Solve: lots * (pointValue001/0.01) * slPoints + lots/0.01 * commRT = riskMoney
   double perLotPointValue = PointValue(1.0);
   double lossPerLot = perLotPointValue * slPoints + CommissionRT(1.0);
   if(lossPerLot <= 0) { riskUsed = 0; note = "BAD MODEL"; return 0; }

   double raw = riskMoney / lossPerLot;
   double lots = NormalizeLots(raw);

   // Micro-account reality check: if even the minimum lot breaks the cap,
   // refuse the trade rather than silently over-leveraging a 200 USD account.
   if(raw < gMinLot - 1e-8)
     {
      double minLoss = PointValue(gMinLot) * slPoints + CommissionRT(gMinLot);
      double minPct  = minLoss / capital * 100.0;
      if(minPct > MaxRiskPercentHardCap && !AllowMinLotOverride)
        {
         riskUsed = minPct;
         note = "MIN LOT RISK " + Fmt(minPct, 2) + "% > CAP";
         return 0;
        }
      lots = gMinLot;
      note = "MIN LOT";
     }

   // Margin sanity: never commit more than 25% of free margin.
   double marginPerLot = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
   if(marginPerLot > 0)
     {
      double affordable = (AccountFreeMargin() * 0.25) / marginPerLot;
      if(affordable < lots)
        {
         lots = NormalizeLots(affordable);
         note = (note == "" ? "MARGIN CAP" : note + "+MARGIN");
        }
     }
   if(lots < gMinLot - 1e-8) { riskUsed = 0; if(note=="") note="TOO SMALL"; return 0; }

   riskUsed = (PointValue(lots) * slPoints + CommissionRT(lots)) / capital * 100.0;
   if(note == "") note = "RISK " + Fmt(pct, 2) + "%";
   return lots;
  }

//==================================================================//
//              S L   /   T P   C O N S T R U C T I O N             //
//==================================================================//
double ComputeStopDistance(int type, int shift)
  {
   double atr = iATR(NULL, 0, MathMax(1, ATRLength), shift);
   double dist = atr * MathMax(0.1, StopLossATR);

   if(StopLossMode == SF_SL_FIXED)
      dist = MathMax(1.0, StopLossPoints) * gPoint;

   else if(StopLossMode == SF_SL_STRUCTURE)
     {
      int look = MathMax(3, StructureSwingBars);
      double ref = (type == OP_BUY) ? DonchianLow(shift, look) : DonchianHigh(shift, look);
      double px  = (type == OP_BUY) ? Bid : Ask;
      double raw = MathAbs(px - ref) + atr * MathMax(0.0, StructureBufferATR);
      dist = MathMax(raw, atr * 0.6);   // never hug price too tightly
     }

   else if(StopLossMode == SF_SL_RISK)
     {
      double capital = RiskCapital();
      double money   = capital * MathMin(RiskPercent, MaxRiskPercentHardCap) / 100.0;
      double pv      = PointValue(gMinLot);
      if(pv > 0 && money > 0)
         dist = MathMax(atr * 0.8, ((money - CommissionRT(gMinLot)) / pv) * gPoint);
     }

   // The stop must clear spread + commission, otherwise the cost model alone
   // can turn a technically-correct stop into a guaranteed loss.
   double costGuard = TotalCostPoints() * 1.5 * gPoint;
   dist = MathMax(dist, costGuard);
   dist = MathMax(dist, MinStopDistance());
   return dist;
  }

double ComputeTakeDistance(int shift)
  {
   double atr = iATR(NULL, 0, MathMax(1, ATRLength), shift);
   double dist = atr * MathMax(0.1, TakeProfitATR);
   if(TakeProfitMode == SF_TP_FIXED) dist = MathMax(1.0, TakeProfitPoints) * gPoint;
   if(TakeProfitMode == SF_TP_COST)  dist = TotalCostPoints() * MathMax(1.0, TakeProfitCostMultiple) * gPoint;

   // Enforce the cost-aware minimum target. On Exness Raw gold the round turn
   // is ~70 points of commission plus live spread; a target that does not
   // clear a multiple of that has negative expectancy no matter the win rate.
   double minTP = TotalCostPoints() * MathMax(1.0, MinTPtoCostRatio) * gPoint;
   dist = MathMax(dist, minTP);
   dist = MathMax(dist, MinStopDistance());
   return dist;
  }

// True break-even: entry price shifted by spread + commission, so "flat"
// really means flat after the broker has been paid.
double BreakEvenPrice(int type, double entry, double lots)
  {
   double commPoints = gCostPointsRT;                  // round turn, in points
   double spreadPts  = SpreadPoints();
   double shift = (commPoints + spreadPts) * gPoint;
   if(!BreakEvenIncludesCost) shift = 0;
   double lock = MathMax(0.0, BreakEvenLockPoints) * gPoint;
   return (type == OP_BUY) ? entry + shift + lock : entry - shift - lock;
  }

//==================================================================//
//              O R D E R   O P E R A T I O N S                     //
//==================================================================//
int CountOwnPositions(int &type, int &ticket)
  {
   int n = 0; type = -1; ticket = -1;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      n++;
      if(ticket < 0) { ticket = OrderTicket(); type = OrderType(); }
     }
   return n;
  }

bool SafeModify(int ticket, double price, double sl, double tp)
  {
   for(int a = 0; a < MathMax(1, OrderRetries); a++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
      if(MathAbs(OrderStopLoss() - sl) < gPoint * 0.5 &&
         MathAbs(OrderTakeProfit() - tp) < gPoint * 0.5) return true;
      if(OrderModify(ticket, price, NormalizeDouble(sl, gDigits),
                     NormalizeDouble(tp, gDigits), 0, clrNONE)) return true;
      int err = GetLastError();
      if(err == 1) return true;
      Sleep(120); RefreshRates();
     }
   return false;
  }

bool CloseAllOwn(string reason)
  {
   bool all = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      bool ok = false;
      for(int a = 0; a < MathMax(1, OrderRetries) && !ok; a++)
        {
         RefreshRates();
         double px = (OrderType() == OP_BUY) ? Bid : Ask;
         ok = OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(px, gDigits),
                         SlippagePoints, clrNONE);
         if(!ok) Sleep(120);
        }
      if(!ok) { all = false; Journal("CLOSE FAILED " + IntegerToString(GetLastError())); }
     }
   if(all) Journal("CLOSED: " + reason);
   return all;
  }

bool OpenTrade(int type, int shift)
  {
   RefreshRates();

   double slDist = ComputeStopDistance(type, shift);
   double tpDist = ComputeTakeDistance(shift);

   double riskUsed = 0; string note = "";
   double lots = CalculateLots(slDist, riskUsed, note);
   if(lots < gMinLot - 1e-8)
     { gBlockReason = "SIZE: " + note; Journal("BLOCKED " + gBlockReason); return false; }

   double entry = (type == OP_BUY) ? Ask : Bid;
   double sl = (type == OP_BUY) ? entry - slDist : entry + slDist;
   double tp = (type == OP_BUY) ? entry + tpDist : entry - tpDist;
   sl = NormalizeDouble(sl, gDigits);
   tp = NormalizeDouble(tp, gDigits);

   int ticket = -1;
   for(int a = 0; a < MathMax(1, OrderRetries) && ticket < 0; a++)
     {
      RefreshRates();
      entry = (type == OP_BUY) ? Ask : Bid;
      ticket = OrderSend(Symbol(), type, lots, NormalizeDouble(entry, gDigits),
                         SlippagePoints, sl, tp, TradeComment, MagicNumber, 0,
                         type == OP_BUY ? clrDodgerBlue : clrTomato);
      if(ticket < 0)
        {
         int err = GetLastError();
         if(err == 130 || err == 145)   // invalid stops -> send naked, then modify
           {
            ticket = OrderSend(Symbol(), type, lots, NormalizeDouble(entry, gDigits),
                               SlippagePoints, 0, 0, TradeComment, MagicNumber, 0, clrNONE);
            if(ticket > 0)
              {
               sl = (type == OP_BUY) ? entry - slDist : entry + slDist;
               tp = (type == OP_BUY) ? entry + tpDist : entry - tpDist;
               SafeModify(ticket, entry, sl, tp);
              }
           }
         else Sleep(150);
        }
     }

   if(ticket < 0)
     {
      gBlockReason = "SEND ERR " + IntegerToString(GetLastError());
      Journal(gBlockReason);
      return false;
     }

   gDayTrades++;
   gLastTradeBar = Time[0];
   double costUsd = CommissionRT(lots) + (SpreadPoints() * PointValue(lots));
   Journal(StringFormat("%s %.2f lots @ %s | SL %.0fp TP %.0fp | risk %.2f%% | cost %.2f USD",
           (type == OP_BUY ? "BUY" : "SELL"), lots, Fmt(entry, gDigits),
           slDist / gPoint, tpDist / gPoint, riskUsed, costUsd));

   if(AlertOnEntry) Alert("Signal Forge PRO: ", (type == OP_BUY ? "BUY " : "SELL "), Symbol(), " ", lots);
   if(PushOnEntry)  SendNotification("SF-PRO " + (type == OP_BUY ? "BUY " : "SELL ") + Symbol() +
                                     " " + DoubleToString(lots, 2) + " @ " + Fmt(entry, gDigits));
   return true;
  }

//==================================================================//
//              T R A D E   M A N A G E M E N T                     //
//==================================================================//
bool WasPartialed(datetime key)
  {
   for(int i = 0; i < gPartialCount; i++) if(gPartialDone[i] == key) return true;
   return false;
  }
void MarkPartialed(datetime key)
  {
   if(gPartialCount >= 64) { for(int i = 0; i < 63; i++) gPartialDone[i] = gPartialDone[i+1]; gPartialCount = 63; }
   gPartialDone[gPartialCount++] = key;
  }
bool WasBreakEven(datetime key)
  {
   for(int i = 0; i < gBECount; i++) if(gBEDone[i] == key) return true;
   return false;
  }
void MarkBreakEven(datetime key)
  {
   if(gBECount >= 64) { for(int i = 0; i < 63; i++) gBEDone[i] = gBEDone[i+1]; gBECount = 63; }
   gBEDone[gBECount++] = key;
  }

void ManageOpenTrades()
  {
   double atr = iATR(NULL, 0, MathMax(1, ATRLength), 1);
   if(atr <= 0) return;
   double minStop = MinStopDistance();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      RefreshRates();
      int      ticket = OrderTicket();
      datetime key    = OrderOpenTime();   // survives partial closes
      double   entry  = OrderOpenPrice();
      double lots   = OrderLots();
      double px     = (type == OP_BUY) ? Bid : Ask;
      double moved  = (type == OP_BUY) ? (px - entry) : (entry - px);
      double curSL  = OrderStopLoss();
      double curTP  = OrderTakeProfit();

      //---------------- partial close at TP1 ----------------
      if(UsePartialClose && !WasPartialed(key) &&
         moved >= atr * MathMax(0.1, PartialTriggerATR))
        {
         double part = NormalizeDouble(lots * MathMax(1.0, MathMin(90.0, PartialClosePercent)) / 100.0, 2);
         part = MathFloor(part / gLotStep + 1e-8) * gLotStep;
         if(part >= gMinLot && (lots - part) >= gMinLot)
           {
            if(OrderClose(ticket, part, NormalizeDouble(px, gDigits), SlippagePoints, clrGold))
              {
               MarkPartialed(key);
               Journal("PARTIAL " + Fmt(part, 2) + " BANKED @ " + Fmt(atr * PartialTriggerATR / gPoint, 0) + "p");
               continue;   // order list changed
              }
           }
         else MarkPartialed(key);   // cannot split a minimum position
        }

      //---------------- true break-even ----------------
      if(UseBreakEven && !WasBreakEven(key) &&
         moved >= atr * MathMax(0.1, BreakEvenTriggerATR))
        {
         double be = BreakEvenPrice(type, entry, lots);
         bool better = (type == OP_BUY) ? (curSL < be - gPoint * 0.5) : (curSL > be + gPoint * 0.5 || curSL == 0);
         bool valid  = (type == OP_BUY) ? (be < Bid - minStop) : (be > Ask + minStop);
         if(better && valid && SafeModify(ticket, entry, be, curTP))
           {
            MarkBreakEven(key);
            Journal("BREAK-EVEN+COST LOCKED @ " + Fmt(be, gDigits));
            curSL = be;
           }
        }

      //---------------- trailing ----------------
      if(TrailingMode != SF_TRAIL_OFF && moved >= MathMax(0.0, TrailingStartPoints) * gPoint)
        {
         double newSL = 0;
         if(TrailingMode == SF_TRAIL_POINTS)
           {
            double d = MathMax(minStop, TrailingDistancePoints * gPoint);
            newSL = (type == OP_BUY) ? Bid - d : Ask + d;
           }
         else if(TrailingMode == SF_TRAIL_ATR)
           {
            double d = MathMax(minStop, atr * MathMax(0.2, TrailingATRMultiple));
            newSL = (type == OP_BUY) ? Bid - d : Ask + d;
           }
         else // chandelier
           {
            int look = MathMax(3, ChandelierLookback);
            double k = atr * MathMax(0.2, TrailingATRMultiple);
            if(type == OP_BUY)
              {
               int hi = iHighest(NULL, 0, MODE_HIGH, look, 0);
               newSL = High[hi < 0 ? 0 : hi] - k;
              }
            else
              {
               int lo = iLowest(NULL, 0, MODE_LOW, look, 0);
               newSL = Low[lo < 0 ? 0 : lo] + k;
              }
           }

         newSL = NormalizeDouble(newSL, gDigits);
         double step = MathMax(1.0, TrailingStepPoints) * gPoint;
         bool improves = (type == OP_BUY)
                         ? (curSL == 0 || newSL - curSL >= step)
                         : (curSL == 0 || curSL - newSL >= step);
         bool safe = (type == OP_BUY) ? (newSL < Bid - minStop) : (newSL > Ask + minStop);
         // Never trail into a worse-than-break-even stop once in profit.
         double floorSL = BreakEvenPrice(type, entry, lots);
         if(WasBreakEven(key))
            safe = safe && ((type == OP_BUY) ? (newSL >= floorSL - gPoint) : (newSL <= floorSL + gPoint));
         if(improves && safe) SafeModify(ticket, entry, newSL, curTP);
        }

      //---------------- time stop ----------------
      if(UseTimeStop)
        {
         int barsOpen = iBarShift(Symbol(), Period(), OrderOpenTime(), false);
         if(barsOpen >= MathMax(1, TimeStopBars))
           {
            double rDist = MathAbs(entry - (curSL == 0 ? entry - atr : curSL));
            double progressR = (rDist > 0) ? moved / rDist : 0;
            if(progressR < TimeStopMinProgressR)
              {
               if(OrderClose(ticket, lots, NormalizeDouble(px, gDigits), SlippagePoints, clrSilver))
                  Journal("TIME STOP after " + IntegerToString(barsOpen) + " bars");
              }
           }
        }
     }
  }

void TrackClosedTrades()
  {
   int total = OrdersHistoryTotal();
   if(total == gLastHistoryCount) return;
   if(gLastHistoryCount < 0) { gLastHistoryCount = total; return; }
   gLastHistoryCount = total;

   datetime newest = 0; double newestNet = 0; bool found = false;
   for(int i = total - 1; i >= 0 && i >= total - 10; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderCloseTime() > newest)
        { newest = OrderCloseTime(); newestNet = OrderProfit() + OrderSwap() + OrderCommission(); found = true; }
     }
   if(!found) return;

   gDayNet += newestNet;
   if(newestNet < 0)
     {
      gConsecLosses++;
      if(MaxConsecutiveLosses > 0 && gConsecLosses >= MaxConsecutiveLosses)
        {
         gCooldownUntil = TimeCurrent() + MathMax(1, CooldownMinutes) * 60;
         Journal("COOLDOWN " + IntegerToString(CooldownMinutes) + "m after " +
                 IntegerToString(gConsecLosses) + " losses");
         gConsecLosses = 0;
        }
     }
   else gConsecLosses = 0;
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
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      gStatTrades++;
      gStatNet += net;
      gStatCommission += MathAbs(OrderCommission());
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
         double nt = OrderProfit() + OrderSwap() + OrderCommission();
         gTrkLots[b]   += OrderLots();
         gTrkProfit[b] += nt;
         gTrkComm[b]   += MathAbs(OrderCommission());
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
            before += OrderProfit() + OrderSwap() + OrderCommission();
        }
      dayOpen[od] = before;
      gTrkGainPct[od] = (before > 0) ? gTrkProfit[od] / before * 100.0 : 0.0;
     }

   double run = start, peak = start;
   gStatMaxDD = 0;
   if(gEquityPoints < 512) gEquityCurve[gEquityPoints++] = start;
   for(int j = 0; j < total && gEquityPoints < 512; j++)
     {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      run += OrderProfit() + OrderSwap() + OrderCommission();
      peak = MathMax(peak, run);
      if(peak > 0) gStatMaxDD = MathMax(gStatMaxDD, (peak - run) / peak * 100.0);
      gEquityCurve[gEquityPoints++] = run;
     }
  }

//==================================================================//
//              C A N V A S   P R I M I T I V E S                   //
//==================================================================//
struct SFButton
  {
   int      x, y, w, h;
   string   id;
  };
SFButton gButtons[16];
int      gButtonCount = 0;

void RegisterButton(string id, int x, int y, int w, int h)
  {
   if(gButtonCount >= 16) return;
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
      if(quad == 0)      { gHud.PixelSet(cx - x, cy - y, clr); gHud.PixelSet(cx - y, cy - x, clr); }
      else if(quad == 1) { gHud.PixelSet(cx + x, cy - y, clr); gHud.PixelSet(cx + y, cy - x, clr); }
      else if(quad == 2) { gHud.PixelSet(cx - x, cy + y, clr); gHud.PixelSet(cx - y, cy + x, clr); }
      else               { gHud.PixelSet(cx + x, cy + y, clr); gHud.PixelSet(cx + y, cy + x, clr); }
      y++;
      if(err < 0) err += 2 * y + 1;
      else { x--; err += 2 * (y - x) + 1; }
     }
  }

void RoundRect(int x, int y, int w, int h, int r, uint fill, uint border, bool drawBorder = true)
  {
   if(w <= 0 || h <= 0) return;
   r = MathMax(0, MathMin(r, MathMin(w, h) / 2));
   gHud.FillRectangle(x + r, y,         x + w - r, y + h,     fill);
   gHud.FillRectangle(x,     y + r,     x + r,     y + h - r, fill);
   gHud.FillRectangle(x + w - r, y + r, x + w,     y + h - r, fill);
   if(r > 0)
     {
      gHud.FillCircle(x + r,         y + r,         r, fill);
      gHud.FillCircle(x + w - r - 1, y + r,         r, fill);
      gHud.FillCircle(x + r,         y + h - r - 1, r, fill);
      gHud.FillCircle(x + w - r - 1, y + h - r - 1, r, fill);
     }
   if(drawBorder)
     {
      gHud.Line(x + r, y,         x + w - r, y,         border);
      gHud.Line(x + r, y + h - 1, x + w - r, y + h - 1, border);
      gHud.Line(x,         y + r, x,         y + h - r, border);
      gHud.Line(x + w - 1, y + r, x + w - 1, y + h - r, border);
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
   gHud.Line(x + r,     y + 1,     x + w - r - 1, y + 1,         TLite);
   gHud.Line(x + 1,     y + r,     x + 1,         y + h - r - 1, TLite);
   // shadow: bottom + right
   gHud.Line(x + r,     y + h - 2, x + w - r - 1, y + h - 2,     TDark);
   gHud.Line(x + w - 2, y + r,     x + w - 2,     y + h - r - 1, TDark);
  }

// Inset/sunken well - used for meter tracks and table bodies.
void SunkenWell(int x, int y, int w, int h, int r, uint fill)
  {
   if(w <= 2 || h <= 2) return;
   RoundRect(x, y, w, h, r, fill, TDark);
   gHud.Line(x + r, y + 1, x + w - r - 1, y + 1, TDark);
   gHud.Line(x + 1, y + r, x + 1, y + h - r - 1, TDark);
   gHud.Line(x + r, y + h - 2, x + w - r - 1, y + h - 2, TLite);
  }

// Glowing accent bar - a vivid 3px spine used to tag panels and rows.
void AccentSpine(int x, int y, int h, uint c)
  {
   gHud.FillRectangle(x,     y, x + 2, y + h, c);
   gHud.FillRectangle(x + 3, y, x + 3, y + h, A(C'0,0,0',90));
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
      gHud.Line(x, y + i, x + w, y + i, c);
     }
  }

void Text(int x, int y, string s, uint c, int size = 8, string font = "Segoe UI", uint flags = 0)
  {
   gHud.FontSet(font, SC(size) * -10, flags);
   gHud.TextOut(x, y, s, c, SF_AL_LEFT | SF_AL_TOP);
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
   gHud.FontSet(font, SC(size) * -10, flags);
   int tw = 0, th = 0;
   gHud.TextSize(s, tw, th);
   gHud.TextOut(x, y + (h - th) / 2, s, c, SF_AL_LEFT | SF_AL_TOP);
  }

void TextCenterVC(int cx, int y, int h, string s, uint c, int size = 8,
                  string font = "Segoe UI", uint flags = 0)
  {
   gHud.FontSet(font, SC(size) * -10, flags);
   int tw = 0, th = 0;
   gHud.TextSize(s, tw, th);
   gHud.TextOut(cx, y + (h - th) / 2, s, c, SF_AL_CENTER | SF_AL_TOP);
  }

void TextRight(int x, int y, string s, uint c, int size = 8, string font = "Segoe UI", uint flags = 0)
  {
   gHud.FontSet(font, SC(size) * -10, flags);
   gHud.TextOut(x, y, s, c, SF_AL_RIGHT | SF_AL_TOP);
  }

void TextCenter(int x, int y, string s, uint c, int size = 8, string font = "Segoe UI", uint flags = 0)
  {
   gHud.FontSet(font, SC(size) * -10, flags);
   gHud.TextOut(x, y, s, c, SF_AL_CENTER | SF_AL_TOP);
  }

// Horizontal meter with a filled portion - used for score, risk and cost.
// blend two ARGB colours (t = 0..1)
uint MixC(uint a, uint b, double t)
  {
   t = MathMax(0.0, MathMin(1.0, t));
   int ar = (int)((a >> 16) & 0xFF), ag = (int)((a >> 8) & 0xFF), ab = (int)(a & 0xFF);
   int br = (int)((b >> 16) & 0xFF), bg = (int)((b >> 8) & 0xFF), bb = (int)(b & 0xFF);
   int rr = (int)(ar + (br - ar) * t);
   int rg = (int)(ag + (bg - ag) * t);
   int rb = (int)(ab + (bb - ab) * t);
   return (uint)(0xFF000000 | ((uint)rr << 16) | ((uint)rg << 8) | (uint)rb);
  }

// Strength-graded fill: weak -> amber, mid -> accent, strong -> bull/bear.
// Lets you read signal conviction from the bar colour, not just its length.
uint StrengthColor(double pct01, uint strongC)
  {
   pct01 = MathMax(0.0, MathMin(1.0, pct01));
   if(pct01 < 0.5) return MixC(TWarn, TAccent, pct01 / 0.5);
   return MixC(TAccent, strongC, (pct01 - 0.5) / 0.5);
  }

void Meter(int x, int y, int w, int h, double pct01, uint fill, uint track)
  {
   pct01 = MathMax(0.0, MathMin(1.0, pct01));
   SunkenWell(x, y, w, h, h / 2, track);
   int fw = (int)MathRound((w - 2) * pct01);
   if(fw <= 0) return;
   if(fw > h) RoundRect(x + 1, y + 1, fw, h - 2, (h - 2) / 2, fill, fill, false);
   else gHud.FillRectangle(x + 1, y + 1, x + 1 + fw, y + h - 1, fill);
   // glossy top edge on the filled portion
   gHud.Line(x + 2, y + 2, x + fw - 1, y + 2, A(C'255,255,255',70));
  }

void MeterGraded(int x, int y, int w, int h, double pct01, uint strongC, uint track)
  {
   Meter(x, y, w, h, pct01, StrengthColor(pct01, strongC), track);
  }


// Semi-circular conviction gauge. The needle sweeps from full bear (left)
// to full bull (right); the arc itself is coloured by the live score.
void ScoreGauge(int cx, int cy, int radius, double score)
  {
   double norm = MathMax(-100.0, MathMin(100.0, score));
   uint  col   = (norm >=  EntryScoreThreshold) ? TBull :
                 (norm <= -EntryScoreThreshold) ? TBear : TFlat;

   for(int deg = 180; deg <= 360; deg++)
     {
      double rad = deg * M_PI / 180.0;
      double frac = (deg - 180) / 180.0;                // 0 = far left
      double val  = -100.0 + frac * 200.0;
      bool lit = (norm >= 0) ? (val >= 0 && val <= norm) : (val <= 0 && val >= norm);
      uint c = lit ? col : TGridC;
      for(int t = 0; t < SC(7); t++)
        {
         int px = cx + (int)MathRound(MathCos(rad) * (radius - t));
         int py = cy + (int)MathRound(MathSin(rad) * (radius - t));
         gHud.PixelSet(px, py, c);
        }
     }
   // centre zero tick
   gHud.Line(cx, cy - radius, cx, cy - radius + SC(9), TTextDim);

   // needle
   double ndeg = 180.0 + (norm + 100.0) / 200.0 * 180.0;
   double nrad = ndeg * M_PI / 180.0;
   int nx = cx + (int)MathRound(MathCos(nrad) * (radius - SC(11)));
   int ny = cy + (int)MathRound(MathSin(nrad) * (radius - SC(11)));
   gHud.Line(cx, cy, nx, ny, col);
   gHud.Line(cx, cy - 1, nx, ny - 1, col);
   gHud.FillCircle(cx, cy, SC(4), col);
  }

// Compact sparkline of the closed-trade equity curve.
void Sparkline(int x, int y, int w, int h, uint line, uint fill)
  {
   if(gEquityPoints < 2)
     {
      TextCenter(x + w / 2, y + h / 2 - SC(6), "NO CLOSED TRADES YET", TTextDim, 7);
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
      gHud.Line(prevX, prevY, cx, cy, line);
      gHud.Line(prevX, prevY + 1, cx, cy + 1, line);
      for(int fy = (cy > y ? cy : y); fy < y + h; fy += 3) gHud.PixelSet(cx, fy, fill);
      prevX = cx; prevY = cy;
     }
  }

void StatusDot(int x, int y, int r, bool on, uint onC, uint offC)
  {
   gHud.FillCircle(x, y, r, on ? onC : offC);
   gHud.Circle(x, y, r + 1, on ? onC : TGridC);
  }

//==================================================================//
//              Q U A N T U M   H U D                               //
//==================================================================//
string StateText()
  {
   if(gPaused) return "PAUSED";
   if(gHalted) return gHaltReason;
   if(InCooldown()) return "COOLDOWN";
   if(gBlockReason != "") return gBlockReason;
   return "ARMED";
  }

uint StateColor()
  {
   if(gPaused || gHalted) return TBear;
   if(InCooldown() || gBlockReason != "") return TFlat;
   return TBull;
  }

void DestroyHud()
  {
   if(gHudReady) gHud.Destroy();
   gHudReady = false; gHudW = 0; gHudH = 0;
   ObjectDelete(0, PFX + "HUD");
  }

bool EnsureHud(int w, int h)
  {
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

void DrawChip(int x, int y, int w, int h, string label, string value, uint valueColor, uint accent)
  {
   RaisedPlate(x, y, w, h, SC(6), TPanel, TBorder);
   AccentSpine(x + SC(3), y + SC(5), h - SC(10), accent);
   Text(x + SC(12), y + SC(6),  label, TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
   Text(x + SC(12), y + SC(19), value, valueColor, 10, "Segoe UI Black", SF_FW_BLACK);
  }

void DrawButton(int x, int y, int w, int h, string id, string caption, bool active, uint accent)
  {
   bool hover = (gHoverId == id);
   uint fill  = active ? accent : (hover ? TPanelHi : TPanel);
   uint edge  = active ? accent : (hover ? TAccent : TBorder);
   uint txt   = active ? A(C'6,10,18',255) : (hover ? TAccent : TText);
   RaisedPlate(x, y, w, h, SC(5), fill, edge, true, 2);
   if(hover && !active) gHud.Line(x + SC(6), y + h - 3, x + w - SC(6), y + h - 3, TAccent);
   TextCenterVC(x + w / 2, y, h, caption, txt, 8, "Segoe UI Semibold", SF_FW_SEMI);
   RegisterButton(id, HudMargin + x, HudMargin + y, w, h);
  }

void PaintHud()
  {
   if(!ShowHUD) { DestroyHud(); return; }

   long chartW = 0, chartH = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chartW);
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chartH);

   int W = SC(430);
   if(W > (int)chartW - HudMargin * 2) W = (int)chartW - HudMargin * 2;
   if(W < SC(300)) { DestroyHud(); return; }

   int headerH = SC(54);
   // Each page owns its natural height, so no page shows dead space.
   int pageH = SC(652);                       // CORE
   if(gHudPage == 1) pageH = SC(500);         // FILTERS
   if(gHudPage == 2) pageH = SC(700);         // TRACKER
   int H = gHudCollapsed ? headerH + SC(8) : pageH;
   if(H > (int)chartH - HudMargin * 2) H = (int)chartH - HudMargin * 2;
   if(H < headerH + SC(8)) return;

   if(!EnsureHud(W, H)) return;
   gButtonCount = 0;
   gHud.Erase(A(C'0,0,0', 0));

   //================= shell =================
   RaisedPlate(0, 0, W, H, SC(12), TBg, TBorder, false, 0);
   GradientRect(3, 3, W - 6, headerH - 5, TPanelHi, TBg2);
   gHud.Line(SC(10), headerH - 1, W - SC(10), headerH - 1, TAccent);
   gHud.Line(SC(10), headerH,     W - SC(10), headerH,     TDark);

   //================= header =================
   // Header is laid out RIGHT-TO-LEFT from the window edge, and the PRO badge
   // is positioned from the MEASURED width of the wordmark (CCanvas::TextWidth)
   // rather than a hardcoded offset - hardcoding it made the badge land on top
   // of the wordmark whenever the installed font metrics differed from mine.
   int hx = SC(14), hy = SC(10);
   gHud.FillCircle(hx + SC(10), hy + SC(14), SC(11), TAccent2);
   gHud.FillCircle(hx + SC(10), hy + SC(14), SC(7),  TBg);
   gHud.FillCircle(hx + SC(10), hy + SC(14), SC(3),  TAccent);

   int txtX = hx + SC(28);
   string mark = "SIGNAL FORGE";
   gHud.FontSet("Segoe UI Black", SC(11) * -10, SF_FW_BLACK);
   int markW = gHud.TextWidth(mark);
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
      TextCenter(badgeX + badgeW / 2, hy + SC(2), "PRO", A(C'6,10,18',255), 7,
                 "Segoe UI Black", SF_FW_BLACK);
     }

   Text(txtX, hy + SC(18), Symbol() + "  ·  M" + IntegerToString(Period()) +
        "  ·  RAW  ·  v2.03", TTextDim, 7);

   RaisedPlate(pillX, hy + SC(3), pillW, pillH, SC(10), TPanelHi, StateColor(), true, 1);
   StatusDot(pillX + SC(12), hy + SC(14), SC(4), !gPaused && !gHalted, StateColor(), TGridC);
   TextCenter(pillX + SC(13) + (pillW - SC(13)) / 2, hy + SC(6), st, StateColor(), 7,
              "Segoe UI Semibold", SF_FW_SEMI);

   DrawButton(colX, hy + SC(3), colW, pillH, "BTN_COLLAPSE",
              gHudCollapsed ? "+" : "–", false, TAccent);

   if(gHudCollapsed) { gHud.Update(); ChartRedraw(0); return; }

   int y = headerH + SC(6);
   int pad = SC(12);
   int innerW = W - pad * 2;

   //================= navigation tabs =================
   int tabW = (innerW - SC(16)) / 3;
   DrawButton(pad,                  y, tabW, SC(24), "TAB_CORE",    "CORE",    gHudPage == 0, TAccent);
   DrawButton(pad + tabW + SC(8),   y, tabW, SC(24), "TAB_FILTERS", "FILTERS", gHudPage == 1, TAccent);
   DrawButton(pad + (tabW + SC(8)) * 2, y, tabW, SC(24), "TAB_LOG", "TRACKER", gHudPage == 2, TAccent);
   y += SC(32);

   //================================================================
   //                        PAGE 0 : CORE
   //================================================================
   if(gHudPage == 0)
     {
      //---------- conviction gauge ----------
      int gaugeH = SC(126);
      RaisedPlate(pad, y, innerW, gaugeH, SC(10), TPanel, TBorder);
      AccentSpine(pad + SC(4), y + SC(7), SC(13), TAccent);
      Text(pad + SC(13), y + SC(6), "CONFLUENCE CONVICTION", TText, 8, "Segoe UI Black", SF_FW_BLACK);

      int cx = pad + innerW / 2, cy = y + gaugeH - SC(18);
      ScoreGauge(cx, cy, SC(58), gScore);

      uint sc = (gScore >= EntryScoreThreshold) ? TBull :
                (gScore <= -EntryScoreThreshold) ? TBear : TFlat;
      string dir = (gScore >= EntryScoreThreshold) ? "LONG" :
                   (gScore <= -EntryScoreThreshold) ? "SHORT" : "NEUTRAL";
      TextCenter(cx, cy - SC(48), Signed(gScore, 0), sc, 19, "Segoe UI Black", SF_FW_BLACK);
      TextCenter(cx, cy - SC(19), dir, sc, 8, "Segoe UI Semibold", SF_FW_SEMI);
      Text(pad + SC(14), cy - SC(6), "-100", TTextDim, 7);
      TextRight(pad + innerW - SC(14), cy - SC(6), "+100", TTextDim, 7);

      // threshold markers on the arc
      Text(pad + SC(12), y + SC(22), "ARM ±" + Fmt(EntryScoreThreshold, 0), TAccent, 7);
      string htf = (gHTFBias > 0) ? "HTF UP" : (gHTFBias < 0 ? "HTF DOWN" : "HTF FLAT");
      TextRight(pad + innerW - SC(12), y + SC(22), htf,
                gHTFBias > 0 ? TBull : (gHTFBias < 0 ? TBear : TFlat), 7, "Segoe UI Semibold", SF_FW_SEMI);
      y += gaugeH + SC(8);

      //---------- cost intelligence ----------
      int costH = SC(92);
      RaisedPlate(pad, y, innerW, costH, SC(10), TPanel, TBorder);
      AccentSpine(pad + SC(4), y + SC(7), SC(13), TAccent2);
      Text(pad + SC(13), y + SC(6), "COST INTELLIGENCE  ·  RAW SPREAD", TText, 8, "Segoe UI Black", SF_FW_BLACK);

      double spPts  = SpreadPoints();
      double cost   = TotalCostPoints();
      double atrP   = ATRPoints(1);
      double costPct= (atrP > 0) ? cost / atrP : 1.0;
      uint costCol  = (costPct < 0.12) ? TBull : (costPct < 0.25 ? TFlat : TBear);

      int col = innerW / 3;
      Text(pad + SC(12), y + SC(26), "SPREAD", TTextDim, 7);
      Text(pad + SC(12), y + SC(37), Fmt(spPts, 0) + " pts",
           spPts <= MaxSpreadPoints ? TText : TBear, 10, "Segoe UI Semibold", SF_FW_SEMI);

      Text(pad + SC(12) + col, y + SC(26), "COMMISSION", TTextDim, 7);
      Text(pad + SC(12) + col, y + SC(37), Fmt(gCostPointsRT, 0) + " pts", TText, 10, "Segoe UI Semibold", SF_FW_SEMI);

      Text(pad + SC(12) + col * 2, y + SC(26), "ROUND TURN", TTextDim, 7);
      Text(pad + SC(12) + col * 2, y + SC(37), Fmt(cost, 0) + " pts", costCol, 10, "Segoe UI Semibold", SF_FW_SEMI);

      Text(pad + SC(12), y + SC(57), "COST / ATR(" + IntegerToString(ATRLength) + ")", TTextDim, 7);
      TextRight(pad + innerW - SC(12), y + SC(57), Fmt(costPct * 100.0, 1) + "% of ATR", costCol, 7,
                "Segoe UI Semibold", SF_FW_SEMI);
      Meter(pad + SC(12), y + SC(72), innerW - SC(24), SC(8), costPct * 4.0, costCol, TGridC);
      y += costH + SC(8);

      //---------- account / risk chips ----------
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

      //---------- risk console ----------
      int riskH = SC(112);
      RaisedPlate(pad, y, innerW, riskH, SC(10), TPanel, TBorder);
      AccentSpine(pad + SC(4), y + SC(7), SC(13), TFlat);
      Text(pad + SC(13), y + SC(6), "RISK CONSOLE", TText, 8, "Segoe UI Black", SF_FW_BLACK);

      double dl = (DailyLossLimitPercent > 0) ? MathMax(0.0, -DayPnLPercent()) / DailyLossLimitPercent : 0;
      double dp = (DailyProfitTargetPct  > 0) ? MathMax(0.0,  DayPnLPercent()) / DailyProfitTargetPct  : 0;
      double tr = (MaxTradesPerDay > 0) ? (double)gDayTrades / MaxTradesPerDay : 0;

      Text(pad + SC(12), y + SC(26), "DAILY LOSS BUDGET", TTextDim, 7);
      TextRight(pad + innerW - SC(12), y + SC(26), Fmt(dl * 100, 0) + "%", dl > 0.7 ? TBear : TText, 7,
                "Segoe UI Semibold", SF_FW_SEMI);
      Meter(pad + SC(12), y + SC(39), innerW - SC(24), SC(7), dl, dl > 0.7 ? TBear : TFlat, TGridC);

      Text(pad + SC(12), y + SC(54), "DAILY TARGET", TTextDim, 7);
      TextRight(pad + innerW - SC(12), y + SC(54), Fmt(dp * 100, 0) + "%", TBull, 7, "Segoe UI Semibold", SF_FW_SEMI);
      Meter(pad + SC(12), y + SC(67), innerW - SC(24), SC(7), dp, TBull, TGridC);

      Text(pad + SC(12), y + SC(82), "TRADES TODAY  " + IntegerToString(gDayTrades) + " / " +
           IntegerToString(MaxTradesPerDay), TTextDim, 7);
      TextRight(pad + innerW - SC(12), y + SC(82), "STREAK " + IntegerToString(gConsecLosses) + "L",
                gConsecLosses > 0 ? TBear : TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
      Meter(pad + SC(12), y + SC(95), innerW - SC(24), SC(7), tr, TAccent2, TGridC);
      y += riskH + SC(8);

      //---------- live trade ticket ----------
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
         Text(pad + SC(12) + c3 * 2, y + SC(38), "BREAK-EVEN", TTextDim, 7);
         Text(pad + SC(12) + c3 * 2, y + SC(48),
              Fmt(BreakEvenPrice(OrderType(), OrderOpenPrice(), OrderLots()), gDigits), TAccent, 8);
        }
      else
        {
         TextCenter(pad + innerW / 2, y + SC(16), "NO OPEN POSITION", TTextDim, 9, "Segoe UI Semibold", SF_FW_SEMI);
         TextCenter(pad + innerW / 2, y + SC(34), "SESSION: " + ActiveSessionName() +
                    "   ·   " + (gBlockReason == "" ? "SCANNING" : gBlockReason), TTextDim, 7);
         double atrNow = ATRPoints(1);
         TextCenter(pad + innerW / 2, y + SC(50), "ATR " + Fmt(atrNow, 0) + " pts   ·   REGIME " +
                    Fmt(ATRRatio(1), 2) + "x", TTextDim, 7);
        }
      y += tkH + SC(8);

      //---------- control strip ----------
      int bw = (innerW - SC(16)) / 3;
      DrawButton(pad,                    y, bw, SC(26), "BTN_PAUSE",
                 gPaused ? "RESUME" : "PAUSE", gPaused, TFlat);
      DrawButton(pad + bw + SC(8),       y, bw, SC(26), "BTN_CLOSE", "CLOSE ALL", false, TBear);
      DrawButton(pad + (bw + SC(8)) * 2, y, bw, SC(26), "BTN_THEME", "OVERLAY",
                 DrawIndicatorOverlay, TAccent2);
     }

   //================================================================
   //                      PAGE 1 : FILTERS
   //================================================================
   else if(gHudPage == 1)
     {
      SunkenWell(pad, y, innerW, SC(26), SC(6), TBg2);
      TextVC(pad + SC(10), y, SC(26), "FILTER", TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
      TextVC(pad + SC(142), y, SC(26), "BIAS", TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
      TextVC(pad + SC(212), y, SC(26), "WGT", TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(10), y + SC(9), "CONTRIBUTION", TAccent, 7,
                "Segoe UI Black", SF_FW_BLACK);
      y += SC(30);

      double totalW = 0;
      for(int i = 0; i < SF_FILTERS; i++) if(gEnabled[i]) totalW += gWeight[i];
      if(totalW <= 0) totalW = 1;

      int rowH = SC(27);
      for(int i = 0; i < SF_FILTERS; i++)
        {
         if(!gShowAllFilters && !gEnabled[i]) continue;
         if(y + rowH > H - SC(46)) break;
         uint rowBg = (i % 2 == 0) ? TPanel : TBg2;
         RoundRect(pad, y, innerW, rowH - SC(3), SC(4), rowBg, rowBg, false);
         if(gEnabled[i]) AccentSpine(pad + 1, y + SC(3), rowH - SC(9),
                                     gBull[i] ? TBull : (gBear[i] ? TBear : TFlat));

         int cellH = rowH - SC(3);
         StatusDot(pad + SC(12), y + SC(11), SC(3), gEnabled[i], TAccent, TGridC);
         TextVC(pad + SC(22), y, cellH, gFilterName[i], gEnabled[i] ? TText : TTextDim, 7,
                "Segoe UI Semibold", SF_FW_SEMI);

         // BIAS card: SOLID RAISED, background carries the state colour and
         // the text is always white so it reads at a glance.
         string bias = gBull[i] ? "BULLISH" : (gBear[i] ? "BEARISH" : "FLAT");
         uint bgC, edC;
         if(!gEnabled[i])      { bgC = TGridC;    edC = TBorder; }
         else if(gBull[i])     { bgC = TBullDeep; edC = TBull;   }
         else if(gBear[i])     { bgC = TBearDeep; edC = TBear;   }
         else                  { bgC = TGreyDeep; edC = TLite;   }  // FLAT = grey
         int bW = SC(62), bH = SC(17);
         int bX = pad + SC(142), bY = y + (cellH - bH) / 2;
         RaisedPlate(bX, bY, bW, bH, SC(3), bgC, edC, true, 1);
         TextCenterVC(bX + bW / 2, bY, bH, bias, A(C'255,255,255',255), 7,
                      "Segoe UI Black", SF_FW_BLACK);

         TextVC(pad + SC(216), y, cellH, Fmt(gWeight[i], 1),
                gEnabled[i] ? TText : TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);

         // contribution bar, colour graded by this filter's share of the vote
         double share = gEnabled[i] ? gWeight[i] / totalW : 0;
         double norm  = MathMin(1.0, share * 2.5);
         int barX = pad + SC(248), barW = innerW - SC(260);
         if(!gEnabled[i]) Meter(barX, y + (cellH - SC(7)) / 2, barW, SC(7), 0, TGridC, TGridC);
         else
           {
            uint strongC = gBull[i] ? TBull : (gBear[i] ? TBear : TFlat);
            MeterGraded(barX, y + (cellH - SC(7)) / 2, barW, SC(7), norm, strongC, TGridC);
           }
         y += rowH;
        }

      y = H - SC(40);
      int bw2 = (innerW - SC(8)) / 2;
      DrawButton(pad, y, bw2, SC(26), "BTN_VIEW",
                 gShowAllFilters ? "SHOWING ALL" : "ACTIVE ONLY", gShowAllFilters, TAccent);
      DrawButton(pad + bw2 + SC(8), y, bw2, SC(26), "BTN_PAUSE",
                 gPaused ? "RESUME" : "PAUSE", gPaused, TFlat);
     }

   //================================================================
   //            PAGE 2 : PERFORMANCE TRACKER
   //================================================================
   else
     {
      RebuildStats();

      //---------- headline KPI strip ----------
      double wr = (gStatTrades > 0) ? 100.0 * gStatWins / gStatTrades : 0;
      double pf = (gStatGL > 0) ? gStatGP / gStatGL : (gStatGP > 0 ? 99.9 : 0);
      int kpiH = SC(52);
      int kw = (innerW - SC(12)) / 4;
      string klbl[4]; klbl[0]="TRADES"; klbl[1]="WIN RATE"; klbl[2]="P/FACTOR"; klbl[3]="MAX DD";
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
      Text(pad + SC(13), y + SC(6), "PERFORMANCE TRACKER", TText, 8, "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(10), y + SC(7), "LAST " + IntegerToString(SF_TRACK_DAYS) + " DAYS",
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
      string cH[6]; cH[0]="DATE"; cH[1]="LOTS"; cH[2]="PROFIT"; cH[3]="GAIN%"; cH[4]="WIN%"; cH[5]="COMM";

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
      Text(cx2 + SC(6), ry + SC(6), "TOTAL", TAccent, 7, "Segoe UI Black", SF_FW_BLACK);
      cx2 += cW[0];
      double sumLots = 0, sumComm = 0;
      for(int a2 = 0; a2 < SF_TRACK_DAYS; a2++) { sumLots += gTrkLots[a2]; sumComm += gTrkComm[a2]; }
      TextRight(cx2 + cW[1] - SC(6), ry + SC(6), Fmt(sumLots, 2), TText, 7, "Segoe UI Black", SF_FW_BLACK);
      cx2 += cW[1];
      TextRight(cx2 + cW[2] - SC(6), ry + SC(5), Signed(gStatNet, 2),
                gStatNet >= 0 ? TBull : TBear, 8, "Segoe UI Black", SF_FW_BLACK);
      cx2 += cW[2];
      double totGain = (gTrkStartBal > 0) ? gStatNet / gTrkStartBal * 100.0 : 0;
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
      int flH = SC(46);
      double gross = gStatNet + gStatCommission;
      RaisedPlate(pad, y, innerW, flH, SC(8),
                  gStatNet >= 0 ? TBullDeep : TBearDeep, gStatNet >= 0 ? TBull : TBear);
      AccentSpine(pad + SC(4), y + SC(8), flH - SC(16), gStatNet >= 0 ? TBull : TBear);
      Text(pad + SC(13), y + SC(6), "FINAL P/L  (NET OF COMMISSION)", TText, 7,
           "Segoe UI Semibold", SF_FW_SEMI);
      Text(pad + SC(13), y + SC(20), Signed(gStatNet, 2) + "  USD",
           gStatNet >= 0 ? TBull : TBear, 15, "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(12), y + SC(8), "GROSS " + Signed(gross, 2), TTextDim, 7,
                "Segoe UI Semibold", SF_FW_SEMI);
      TextRight(pad + innerW - SC(12), y + SC(20), "FEES -" + Fmt(gStatCommission, 2), TWarn, 8,
                "Segoe UI Black", SF_FW_BLACK);
      TextRight(pad + innerW - SC(12), y + SC(32), "BAL " + Fmt(AccountBalance(), 2), TText, 7,
                "Segoe UI Semibold", SF_FW_SEMI);
      y += flH + SC(8);

      //---------- equity sparkline ----------
      int sparkH = H - y - SC(40);
      if(sparkH >= SC(54))
        {
         RaisedPlate(pad, y, innerW, sparkH, SC(8), TPanel, TBorder);
         AccentSpine(pad + SC(4), y + SC(7), SC(12), TAccent2);
         Text(pad + SC(13), y + SC(6), "EQUITY CURVE", TText, 7, "Segoe UI Black", SF_FW_BLACK);
         TextRight(pad + innerW - SC(10), y + SC(6),
                   "TODAY " + Signed(gStatToday, 2) + "   WK " + Signed(gStatWeek, 2) +
                   "   MO " + Signed(gStatMonth, 2), TTextDim, 7, "Segoe UI Semibold", SF_FW_SEMI);
         SunkenWell(pad + SC(8), y + SC(21), innerW - SC(16), sparkH - SC(29), SC(4), TBg);
         Sparkline(pad + SC(12), y + SC(25), innerW - SC(24), sparkH - SC(37),
                   gStatNet >= 0 ? TBull : TBear, TGridC);
         y += sparkH + SC(6);
        }

      DrawButton(pad, H - SC(34), innerW, SC(26), "BTN_PAUSE",
                 gPaused ? "RESUME TRADING" : "PAUSE TRADING", gPaused, TFlat);
     }

   gHud.Update();
  }

//==================================================================//
//              C H A R T   V I S U A L S                           //
//==================================================================//
string gBuyOrb = "", gSellOrb = "";

void BuildOrb(bool buy)
  {
   int side = MathMax(20, SC(SignalOrbSize) * 2);
   int c = side / 2;
   double radius = c - 1;
   uint px[]; ArrayResize(px, side * side); ArrayInitialize(px, 0);
   uint core = buy ? A(C'0,230,160',255) : A(C'255,70,102',255);
   uint ring = buy ? A(C'0,110,84',255)  : A(C'120,20,40',255);
   uint glow = buy ? A(C'120,255,215',255) : A(C'255,150,175',255);
   for(int y = 0; y < side; y++)
      for(int x = 0; x < side; x++)
        {
         double dx = x - c + 0.5, dy = y - c + 0.5;
         double d = MathSqrt(dx * dx + dy * dy);
         if(d > radius) continue;
         uint v = (d > radius - 2) ? ring : core;
         if(d > radius - 3 && x < c && y < c) v = glow;
         px[y * side + x] = v;
        }
   string pat[7];
   if(buy)
     { pat[0]="11110"; pat[1]="10001"; pat[2]="10001"; pat[3]="11110";
       pat[4]="10001"; pat[5]="10001"; pat[6]="11110"; }
   else
     { pat[0]="01111"; pat[1]="10000"; pat[2]="10000"; pat[3]="01110";
       pat[4]="00001"; pat[5]="00001"; pat[6]="11110"; }
   int scale = MathMax(1, MathMin(3, side / 12));
   int sx = (side - 5 * scale) / 2, sy = (side - 7 * scale) / 2;
   uint white = A(C'255,255,255',255);
   for(int r = 0; r < 7; r++)
      for(int col = 0; col < 5; col++)
         if(StringSubstr(pat[r], col, 1) == "1")
            for(int py = 0; py < scale; py++)
               for(int pxx = 0; pxx < scale; pxx++)
                 {
                  int dx2 = sx + col * scale + pxx, dy2 = sy + r * scale + py;
                  if(dx2 >= 0 && dx2 < side && dy2 >= 0 && dy2 < side) px[dy2 * side + dx2] = white;
                 }
   string res = buy ? gBuyOrb : gSellOrb;
   ResourceFree(res);
   ResourceCreate(res, px, side, side, 0, 0, side, COLOR_FORMAT_ARGB_NORMALIZE);
  }

void DrawOrb(bool buy, int shift)
  {
   if(shift < 0 || shift >= Bars) return;
   datetime when = Time[shift];
   double atr = iATR(NULL, 0, MathMax(1, ATRLength), shift);
   double price = buy ? Low[shift] - atr * 0.7 : High[shift] + atr * 0.7;
   string base = PFX + "ORB_" + IntegerToString((int)when) + (buy ? "_B" : "_S");
   if(ObjectFind(0, base) < 0) ObjectCreate(0, base, OBJ_BITMAP, 0, when, price);
   ObjectMove(0, base, 0, when, price);
   ObjectSetString(0, base, OBJPROP_BMPFILE, 0, buy ? gBuyOrb : gSellOrb);
   ObjectSetInteger(0, base, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, base, OBJPROP_BACK, true);
   ObjectSetInteger(0, base, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, base, OBJPROP_HIDDEN, true);

   string link = base + "_L";
   double anchor = buy ? Low[shift] : High[shift];
   if(ObjectFind(0, link) < 0) ObjectCreate(0, link, OBJ_TREND, 0, when, anchor, when, price);
   ObjectMove(0, link, 0, when, anchor);
   ObjectMove(0, link, 1, when, price);
   ObjectSetInteger(0, link, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, link, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, link, OBJPROP_COLOR, buy ? C'0,230,160' : C'255,70,102');
   ObjectSetInteger(0, link, OBJPROP_BACK, true);
   ObjectSetInteger(0, link, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, link, OBJPROP_HIDDEN, true);
  }

void BuildHistoricalOrbs()
  {
   if(!DrawSignalOrbs || gSignalHistoryBuilt != 0) return;
   int maxBars = MathMax(10, MathMin(SignalHistoryBars, Bars - 5));
   int bull[SF_FILTERS], bear[SF_FILTERS];
   bool prevL = false, prevS = false;
   for(int shift = maxBars + 1; shift >= 1; shift--)
     {
      EvaluateFilters(shift, bull, bear);
      double sc = ConfluenceScore(bull, bear);
      bool l = false, s = false;
      ResolveSignal(bull, bear, sc, l, s);
      if(shift <= maxBars)
        {
         if(l && !prevL) DrawOrb(true, shift);
         if(s && !prevS) DrawOrb(false, shift);
        }
      prevL = l; prevS = s;
     }
   gSignalHistoryBuilt = Time[0];
  }

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

void PlotSegment(int filter, int line, int shift, double v0, double v1, color c, int w)
  {
   if(v0 == EMPTY_VALUE || v1 == EMPTY_VALUE) return;
   string n = PFX + "OV_" + IntegerToString(filter) + "_" + IntegerToString(line) + "_" + IntegerToString(shift);
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TREND, 0, Time[shift + 1], v0, Time[shift], v1);
   ObjectMove(0, n, 0, Time[shift + 1], v0);
   ObjectMove(0, n, 1, Time[shift], v1);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

// Overlay plotting used to call SupertrendDir()/SessionVWAP() once per bar,
// which reseeded a 600-bar loop on every request - roughly 100k redundant
// iterations per candle. Both series are now built in a single backward pass.
void BuildSTSeries(int maxShift, double &line[], int &dir[])
  {
   ArrayResize(line, maxShift + 2); ArrayResize(dir, maxShift + 2);
   ArrayInitialize(line, EMPTY_VALUE); ArrayInitialize(dir, 0);
   bool ready = false;
   double pUp = 0, pLo = 0, pLine = 0, pClose = 0;
   int oldest = MathMin(Bars - 2, maxShift + 600);
   for(int i = oldest; i >= 0; i--)
     {
      double atr = iATR(NULL, 0, MathMax(1, SupertrendLength), i);
      double mid = (High[i] + Low[i]) * 0.5;
      double up = mid + SupertrendFactor * atr, dn = mid - SupertrendFactor * atr;
      double fu = up, fl = dn, ln = up; int dr = 1;
      if(!ready || atr <= 0) { if(atr > 0) ready = true; }
      else
        {
         fu = (up < pUp || pClose > pUp) ? up : pUp;
         fl = (dn > pLo || pClose < pLo) ? dn : pLo;
         if(pLine == pUp) ln = (Close[i] > fu) ? fl : fu;
         else             ln = (Close[i] < fl) ? fu : fl;
         dr = (ln == fl) ? -1 : 1;
        }
      pUp = fu; pLo = fl; pLine = ln; pClose = Close[i];
      if(i <= maxShift + 1) { line[i] = ready ? ln : EMPTY_VALUE; dir[i] = ready ? dr : 0; }
     }
  }

void BuildVWAPSeries(int maxShift, double &vw[])
  {
   ArrayResize(vw, maxShift + 2);
   ArrayInitialize(vw, EMPTY_VALUE);
   double pv = 0, vol = 0;
   datetime curDay = 0;
   int oldest = MathMin(Bars - 2, maxShift + 1);
   for(int i = oldest; i >= 0; i--)
     {
      datetime day = DayStart(Time[i]);
      if(day != curDay) { curDay = day; pv = 0; vol = 0; }   // reset each session
      double typical = (High[i] + Low[i] + Close[i]) / 3.0;
      double v = (double)MathMax(1, Volume[i]);
      pv += typical * v; vol += v;
      vw[i] = (vol > 0) ? pv / vol : Close[i];
     }
  }

void DrawOverlay()
  {
   ObjectsDeleteAll(0, PFX + "OV_");
   if(!DrawIndicatorOverlay) return;
   int bars = MathMax(10, MathMin(OverlayBars, Bars - 5));

   if(gEnabled[6])   // EMA pair
      for(int s = bars; s >= 1; s--)
        {
         PlotSegment(6,0,s, iMA(NULL,0,EMAFastLength,0,MODE_EMA,PRICE_CLOSE,s+1),
                            iMA(NULL,0,EMAFastLength,0,MODE_EMA,PRICE_CLOSE,s), C'0,229,255', 1);
         PlotSegment(6,1,s, iMA(NULL,0,EMASlowLength,0,MODE_EMA,PRICE_CLOSE,s+1),
                            iMA(NULL,0,EMASlowLength,0,MODE_EMA,PRICE_CLOSE,s), C'150,100,255', 1);
        }

   if(gEnabled[3])   // Supertrend - one pass
     {
      double stl[]; int std[];
      BuildSTSeries(bars, stl, std);
      for(int s = bars; s >= 1; s--)
         if(stl[s] != EMPTY_VALUE && stl[s+1] != EMPTY_VALUE)
            PlotSegment(3,0,s, stl[s+1], stl[s], std[s] == -1 ? C'0,230,160' : C'255,70,102', 2);
     }

   if(gEnabled[13])  // VWAP - one pass
     {
      double vw[];
      BuildVWAPSeries(bars, vw);
      for(int s = bars; s >= 1; s--)
         if(vw[s] != EMPTY_VALUE && vw[s+1] != EMPTY_VALUE)
            PlotSegment(13,0,s, vw[s+1], vw[s], C'255,206,84', 1);
     }

   if(gEnabled[12])  // structure channel
      for(int s = bars; s >= 1; s--)
        {
         int look = MathMax(3, StructureLookback);
         PlotSegment(12,0,s, DonchianHigh(s+1,look), DonchianHigh(s,look), C'90,120,180', 1);
         PlotSegment(12,1,s, DonchianLow(s+1,look),  DonchianLow(s,look),  C'90,120,180', 1);
        }
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
   ObjectSetString(0, lbl, OBJPROP_FONT, bold ? "Arial Black" : "Consolas Bold");
   ObjectSetString(0, lbl, OBJPROP_TEXT, txt);
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

// --- find a vertical slot for a card whose x-span is [cx, cx+cw] so that
//     it clears every candle in that span, plus any card already placed ---
int FreeLaneY(int cx, int cw, int ch, int anchorY, bool preferAbove,
              int &oX1[], int &oY1[], int &oX2[], int &oY2[], int occN)
  {
   long chH = 0, chW = 0;
   ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chH);
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chW);
   int gap = MathMax(6, ResultCardGapPx);

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

   int cand[2];
   if(preferAbove) { cand[0] = yUp; cand[1] = yDn; }
   else            { cand[0] = yDn; cand[1] = yUp; }

   for(int pass = 0; pass < 2; pass++)
     {
      int y = cand[pass];
      if(y < 4 || y + ch > (int)chH - 4) continue;
      // nudge downward past any card already on screen
      for(int tries = 0; tries < 24; tries++)
        {
         bool clash = false;
         for(int k = 0; k < occN; k++)
           {
            if(cx < oX2[k] && cx + cw > oX1[k] && y < oY2[k] && y + ch > oY1[k])
              { clash = true; y = (preferAbove ? oY1[k] - ch - 4 : oY2[k] + 4); break; }
           }
         if(!clash) break;
         if(y < 4 || y + ch > (int)chH - 4) break;
        }
      if(y >= 4 && y + ch <= (int)chH - 4) return y;
     }
   // last resort: clamp inside the window
   int fy = anchorY - ch / 2;
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
   double gross = OrderProfit() + OrderSwap();
   double comm  = MathAbs(OrderCommission());
   if(comm <= 0) comm = CommissionPer001LotRT * (OrderLots() / 0.01);
   double net   = gross + OrderCommission();
   if(OrderCommission() == 0) net = gross - comm;
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
   int y = FreeLaneY(x, w, h, ey, !isBuy, oX1, oY1, oX2, oY2, occN);

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

      double net   = OrderProfit() + OrderSwap() + OrderCommission();
      double comm  = MathAbs(OrderCommission());
      double gross = OrderProfit() + OrderSwap();
      bool   won   = (net > 0);
      bool   isBuy = (OrderType() == OP_BUY);
      double pts   = isBuy ? (OrderClosePrice() - OrderOpenPrice()) / gPoint
                           : (OrderOpenPrice() - OrderClosePrice()) / gPoint;
      double gainPct = (gTrkStartBal > 0) ? net / gTrkStartBal * 100.0 : 0.0;
      int holdMin = (int)((ct - OrderOpenTime()) / 60);

      int ax = 0, ay = 0;
      if(!ChartTimePriceToXY(0, 0, ct, OrderClosePrice(), ax, ay)) continue;
      if(ax < -w || ax > (int)chW + w) continue;   // off screen horizontally

      int x = ax + SC(12);
      if(x + w > (int)chW - SC(4)) x = ax - w - SC(12);
      if(x < 2) x = 2;
      int y = FreeLaneY(x, w, h, ay, isBuy, oX1, oY1, oX2, oY2, occN);

      color bgHead = won ? C'0,138,96'  : C'158,28,56';
      color bgBody = won ? C'8,58,46'   : C'74,18,32';
      color edge   = won ? C'0,255,170' : C'255,80,120';
      color txtBd  = won ? C'150,255,215' : C'255,180,195';

      string b = PFX + "RES_" + IntegerToString(OrderTicket()) + "_";
      CardRow(b + "R0", x, y, w, headH,
              (won ? "WIN " : "LOSS ") + (net >= 0 ? "+" : "") +
              DoubleToString(net, 2) + " USD", bgHead, C'255,255,255', fsHd, true);
      CardRow(b + "R1", x, y + headH, w, rowH,
              (isBuy ? "BUY  " : "SELL ") + DoubleToString(OrderLots(), 2) + " lot  " +
              (pts >= 0 ? "+" : "") + DoubleToString(MathRound(pts), 0) + "p",
              bgBody, txtBd, fs, false);
      CardRow(b + "R2", x, y + headH + rowH, w, rowH,
              "GROSS " + (gross >= 0 ? "+" : "") + DoubleToString(gross, 2) +
              "  FEE -" + DoubleToString(comm, 2), bgBody, txtBd, fs, false);
      CardRow(b + "R3", x, y + headH + rowH * 2, w, rowH,
              "GAIN " + (gainPct >= 0 ? "+" : "") + DoubleToString(gainPct, 2) + "%  " +
              IntegerToString(holdMin) + "m", bgBody, txtBd, fs, false);

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
  }

void ApplySkin()
  {
   if(!ApplyChartSkin) return;
   color bg, fg, grid, up, dn;
   switch(HudTheme)
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
bool MayOpenNewTrade(string &why)
  {
   why = "";
   if(gPaused)  { why = "PAUSED";  return false; }
   if(gHalted)  { why = gHaltReason; return false; }
   if(InCooldown())
     {
      why = "COOLDOWN " + IntegerToString((int)((gCooldownUntil - TimeCurrent()) / 60)) + "m";
      return false;
     }
   if(!IsTradeAllowed())      { why = "TRADE NOT ALLOWED"; return false; }
   if(IsTradeContextBusy())   { why = "CONTEXT BUSY";      return false; }

   string sw = "";
   if(!SessionAllows(sw)) { why = sw; return false; }
   if(!VolatilityAllows(TradeOnClosedBar ? 1 : 0, sw)) { why = sw; return false; }

   double sp = SpreadPoints();
   if(MaxSpreadPoints > 0 && sp > MaxSpreadPoints)
     { why = "SPREAD " + Fmt(sp, 0) + "p"; return false; }
   if(UseAdaptiveSpreadCap && gSpreadCount >= 20 && gMedianSpread > 0 &&
      sp > gMedianSpread * AdaptiveSpreadFactor)
     { why = "SPREAD SPIKE"; return false; }

   if(MinBarsBetweenTrades > 0 && gLastTradeBar > 0)
     {
      int barsSince = iBarShift(Symbol(), Period(), gLastTradeBar, false);
      if(barsSince < MinBarsBetweenTrades)
        { why = "COOLING " + IntegerToString(MinBarsBetweenTrades - barsSince) + "b"; return false; }
     }
   return true;
  }

//==================================================================//
//              O N   I N I T   /   D E I N I T                     //
//==================================================================//
int OnInit()
  {
   LoadTheme();
   CacheSymbolSpec();
   RecalcCostPoints();
   LoadFilterConfig();
   ParseBlackout();

   gBuyOrb  = "::SFP_BUY_"  + IntegerToString((int)ChartID());
   gSellOrb = "::SFP_SELL_" + IntegerToString((int)ChartID());
   BuildOrb(true); BuildOrb(false);

   for(int i = 0; i < SF_FILTERS; i++) { gBull[i] = 0; gBear[i] = 0; }
   gShowAllFilters = (FilterView == SF_VIEW_ALL);

   gDayStamp       = DayStart(TimeCurrent());
   gDayStartEquity = AccountEquity();
   gDayPeakEquity  = AccountEquity();

   if(HudInteractive) ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   if(!IsTesting() || IsVisualMode()) ApplySkin();
   if(!IsTesting()) EventSetMillisecondTimer(MathMax(100, HudRefreshMs));

   if(Digits != 3 && StringFind(Symbol(), "XAU") >= 0)
      Print("[SF-PRO] NOTE: symbol has ", Digits, " digits. Tuned for 3-digit gold; ",
            "point-based inputs may need scaling.");

   Journal("SF-PRO v2.03 online | comm " + Fmt(gCostPointsRT, 0) + " pts RT | " +
           "min " + Fmt(gMinLot, 2) + " lot");
   gLastBar = 0;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(IsTesting() && IsVisualMode() && KeepVisualsAfterTest)
     {
      // Canvas dies with the EA; leave the chart objects for review.
      DestroyHud();
      ChartRedraw(0);
      return;
     }
   DestroyHud();
   ObjectsDeleteAll(0, PFX);
   if(gBuyOrb  != "") ResourceFree(gBuyOrb);
   if(gSellOrb != "") ResourceFree(gSellOrb);
   ChartRedraw(0);
  }

//==================================================================//
//              T I M E R  /  E V E N T S                           //
//==================================================================//
void OnTimer()
  {
   UpdateGuardians();
   TrackClosedTrades();
   DrawTradeLevelLines();
   DrawResultPills();
   PaintHud();
   ChartRedraw(0);
  }

void HandleHudAction(string hit)
  {
   if(hit == "") return;

   if(hit == "BTN_COLLAPSE") gHudCollapsed = !gHudCollapsed;
   else if(hit == "TAB_CORE")    gHudPage = 0;
   else if(hit == "TAB_FILTERS") gHudPage = 1;
   else if(hit == "TAB_LOG")     gHudPage = 2;
   else if(hit == "BTN_VIEW")    gShowAllFilters = !gShowAllFilters;
   else if(hit == "BTN_PAUSE")
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
      DrawOverlay();
      Journal("OVERLAY REDRAWN");
     }
   PaintHud();
   ChartRedraw(0);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(!HudInteractive) return;

   //--- track the cursor: powers hover states and gives OBJECT_CLICK its coords
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      gMouseX = (int)lparam; gMouseY = (int)dparam;
      string h = HitButton(gMouseX, gMouseY);
      if(h != gHoverId) { gHoverId = h; PaintHud(); ChartRedraw(0); }
      return;
     }

   // Non-selectable canvas objects normally pass the click through as
   // CHARTEVENT_CLICK; some builds report OBJECT_CLICK instead, so accept both.
   if(id == CHARTEVENT_CLICK)
      HandleHudAction(HitButton((int)lparam, (int)dparam));

   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PFX + "HUD")
      HandleHudAction(HitButton(gMouseX, gMouseY));

   if(id == CHARTEVENT_KEYDOWN)
     {
      // MT4 delivers virtual key codes, which match the uppercase ASCII values.
      if(lparam == 'P') { gPaused = !gPaused; Journal(gPaused ? "HOTKEY PAUSE" : "HOTKEY RESUME"); }
      if(lparam == 'H') gHudCollapsed = !gHudCollapsed;
      if(lparam == 'C') CloseAllOwn("HOTKEY CLOSE ALL");
      PaintHud(); ChartRedraw(0);
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      // Result cards are pixel-anchored, so they must re-resolve their
      // time/price anchor the moment the chart scrolls or zooms.
      gCardsDirty = true;
      DrawResultPills();
      DrawTradeLevelLines();
      PaintHud();
     }
  }

//==================================================================//
//              O N   T I C K                                       //
//==================================================================//
void OnTick()
  {
   if(Bars < 200) return;

   PushSpreadSample();
   UpdateGuardians();
   TrackClosedTrades();
   ManageOpenTrades();

   bool graphics = (!IsTesting() || IsVisualMode());

   //--- weekend / session flattening ---------------------------------
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   int openType = -1, openTicket = -1;
   int openCount = CountOwnPositions(openType, openTicket);
   if(openCount > 0)
     {
      if(CloseBeforeWeekend && now.day_of_week == 5 && now.hour >= FridayCloseHour)
         CloseAllOwn("WEEKEND FLATTEN");
      else if(FlattenAtSessionEnd && UseSessionFilter && ActiveSessionName() == "CLOSED")
         CloseAllOwn("SESSION END FLATTEN");
      else if(gHalted && gHaltReason == "EQUITY DRAWDOWN")
         CloseAllOwn("KILL SWITCH");
     }

   //--- bar gate ------------------------------------------------------
   if(Time[0] == gLastBar)
     {
      // The live card shows running P&L, so it has to follow price on every
      // tick - not only when a new bar forms. In the tester OnTimer() never
      // fires, so this is also the tester's only repaint path.
      if(graphics)
        {
         uint tnow = GetTickCount();
         if(tnow - gLastHudPaint >= (uint)MathMax(100, HudRefreshMs))
           { DrawTradeLevelLines(); DrawResultPills(); PaintHud(); gLastHudPaint = tnow; }
        }
      return;
     }
   gLastBar = Time[0];

   int shift = TradeOnClosedBar ? 1 : 0;

   //--- evaluate confluence -------------------------------------------
   int bull[SF_FILTERS], bear[SF_FILTERS];
   EvaluateFilters(shift, bull, bear);
   for(int i = 0; i < SF_FILTERS; i++) { gBull[i] = bull[i]; gBear[i] = bear[i]; }

   gPrevScore = gScore;
   gScore = ConfluenceScore(bull, bear);
   ResolveSignal(bull, bear, gScore, gLongSignal, gShortSignal);

   //--- previous bar state for a fresh-cross test ----------------------
   int pbull[SF_FILTERS], pbear[SF_FILTERS];
   EvaluateFilters(shift + 1, pbull, pbear);
   double prevScore = ConfluenceScore(pbull, pbear);
   bool prevL = false, prevS = false;
   ResolveSignal(pbull, pbear, prevScore, prevL, prevS);

   bool enterLong  = gLongSignal  && (!RequireFreshCross || !prevL);
   bool enterShort = gShortSignal && (!RequireFreshCross || !prevS);

   //--- visuals --------------------------------------------------------
   if(graphics)
     {
      BuildHistoricalOrbs();
      DrawOverlay();
      if(DrawSignalOrbs && enterLong)  DrawOrb(true,  shift);
      if(DrawSignalOrbs && enterShort) DrawOrb(false, shift);
     }

   //--- flip on opposite signal ----------------------------------------
   openCount = CountOwnPositions(openType, openTicket);
   if(CloseOnOppositeSignal && openCount > 0)
     {
      if((openType == OP_BUY && gShortSignal) || (openType == OP_SELL && gLongSignal))
         if(CloseAllOwn("OPPOSITE SIGNAL"))
            openCount = 0;
     }

   //--- entry ----------------------------------------------------------
   string why = "";
   if(MayOpenNewTrade(why))
     {
      gBlockReason = "";
      if(!OnePositionOnly || openCount == 0)
        {
         if(enterLong && !enterShort)       OpenTrade(OP_BUY,  shift);
         else if(enterShort && !enterLong)  OpenTrade(OP_SELL, shift);
        }
      else if(enterLong || enterShort) gBlockReason = "POSITION OPEN";
     }
   else gBlockReason = why;

   //--- repaint --------------------------------------------------------
   if(graphics)
     {
      DrawTradeLevelLines();
      DrawResultPills();
      PaintHud();
      ChartRedraw(0);
     }
  }
//+------------------------------------------------------------------+
