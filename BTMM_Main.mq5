#include <BTMM/BTMM_Defines.mqh>
#include <BTMM/BTMM_Pricing.mqh>
#include <BTMM/BTMM_Sessions.mqh>
#include <BTMM/BTMM_MarketCycle.mqh>
#include <BTMM/BTMM_Indicators.mqh>
#include <BTMM/BTMM_SignalEngine.mqh>
#include <BTMM/BTMM_TradeManager.mqh>
#include <BTMM/BTMM_Dashboard.mqh>
#include <BTMM/BTMM_MarketMaker.mqh>
#include <BTMM/PRIORITY_3_LiquidityEngine.mqh>
#include <BTMM/PRIORITY_4_ExecutionValidator.mqh>
#include <BTMM/BTMM_PortfolioRisk.mqh>
#include <BTMM/BTMM_EquityProtection.mqh>
#include <BTMM/BTMM_ExecutionRetry.mqh>
#include <BTMM/BTMM_ConsecutiveLossTracker.mqh>
#include <BTMM/BTMM_StateManager.mqh>
#include <BTMM/BTMM_SignalArbitrator.mqh>

//==================================================================
//  INPUT PARAMETERS
//==================================================================

// --- General ---
input group "=== General Settings ==="
input int     InpMagicNumber    = 20240101;   // Magic number
input int     InpGMTOffset      = 2;          // Broker GMT offset (hours)
input bool    InpAutoDetectGMT  = false;      // Auto-detect GMT offset

// --- Trading ---
input group "=== Trading Settings ==="
input bool    InpEnableTrading  = true;       // Auto-open trades on signal
input double  InpRiskPct        = 1.0;        // Risk per trade (% of balance)
input double  InpMaxLots        = 10.0;       // Maximum lot size
input bool    InpUseFixedLots   = true;       // Use fixed lot size
input double  InpFixedLots      = 0.1;        // Fixed lot size (if enabled)
input int     InpMinConfluence  = 50;         // Minimum confluence score (0-100)

// --- Setup Filters ---
input group "=== Setup Filters ==="
input bool    InpTrade_MW_Leg2  = true;       // Trade: M/W Leg 2 (bread & butter)
input bool    InpTrade_33       = true;       // Trade: 33 Setup
input bool    InpTrade_NYC      = true;       // Trade: NYC Reversal
input bool    InpTrade_EMA200   = true;       // Trade: EMA200 Bounce
input bool    InpTrade_Swing    = false;      // Trade: Swing (manual preferred)
input bool    InpTrade_Straight = false;      // Trade: Straightaway
input bool    InpTrade_HalfBat  = false;      // Trade: Half Batman
input bool    InpTrade_StopHunt = false;      // Trade: Stop Hunt Fade (1st leg)

// --- Time Filters ---
input group "=== Time Filters ==="
input bool    InpTradeAsiaLondon= true;       // Trade Asia/London window (01-05 ET)
input bool    InpTradeUSOpen    = true;       // Trade US Open window (08-11 ET)
input bool    InpRequireTimeWindow = false;   // Restrict entries to session windows only
input bool    InpAvoidNFP       = true;       // Avoid Non-Farm Payroll (Fri 08:30 ET)
input bool    InpAvoidDecJan    = true;       // Avoid mid-Dec through mid-Jan

// --- Exits ---
input group "=== Exit Settings ==="
input bool    InpUseTrailingStop= true;       // Use 32-pip trailing stop
input bool    InpUseScaleIn     = true;       // Use 5:4:3:2:1 scale-in
input bool    InpScratchTrades  = true;       // Scratch if no move within 2h
input double  InpTP1_Pips       = 50.0;       // TP1 (initial target, pips)

// --- Risk Limits ---
input group "=== Portfolio Risk Limits ==="
input double  InpMaxOpenRiskPct = 3.0;        // Max open portfolio risk (%)
input double  InpMaxDailyLossPct = 5.0;        // Max daily loss (%)
input double  InpMaxWeeklyLossPct= 10.0;       // Max weekly loss (%)
input int     InpMaxOpenTrades  = 3;          // Max simultaneous trades
input double  InpMaxSpreadPips  = 3.0;        // Max spread (pips)
input double  InpMaxExposurePct = 15.0;       // Max symbol exposure (%)

// --- Equity Protection ---
input group "=== Equity Protection ==="
input bool    InpEnableEquityProtection = true;
input double  InpMaxEquityDrawdownPercent = 15.0;
input bool    InpPersistProtectionState = true;

// --- Execution Retry ---
input group "=== Execution Retry Settings ==="
input int     InpMaxExecutionRetries = 3;
input int     InpRetryDelayMilliseconds = 250;
input bool    InpLogRetryAttempts = true;

// --- Consecutive Loss Protection ---
input group "=== Consecutive Loss Protection ==="
input int     InpMaxConsecutiveLosses = 5;
input bool    InpPersistConsecutiveLossState = true;

// --- Display ---
input group "=== Display Settings ==="
input bool    InpShowDashboard  = true;       // Show on-chart dashboard
input bool    InpShowAsianRange = true;       // Draw Asian range box
input bool    InpShowPivots     = true;       // Draw pivot lines
input bool    InpShowADR        = true;       // Draw ADR lines
input bool    InpShowMWPattern  = true;       // Draw M/W pattern
input int     InpPanelX         = 10;         // Panel X position (pixels)
input int     InpPanelY         = 30;         // Panel Y position (pixels)

// --- Alerts ---
input group "=== Alert Settings ==="
input bool    InpAlertPopup     = false;      // Alert popup
input bool    InpAlertPush      = false;      // Push notification
input bool    InpAlertEmail     = false;      // Email alert
input bool    InpAlertSound     = true;       // Sound alert

//==================================================================
//  GLOBAL OBJECTS
//==================================================================
CSessionManager  *g_session    = NULL;
CMarketCycle     *g_cycle      = NULL;
CIndicatorEngine *g_indicators = NULL;
CSignalEngine    *g_signals    = NULL;
CTradeManager    *g_trader     = NULL;
CDashboard       *g_dashboard  = NULL;
CLiquidityEngine *g_liquidity  = NULL;
CExecutionValidator *g_validator = NULL;
CPortfolioRiskManager *g_portfolio = NULL;
CMarketMakerEngine *g_market_maker = NULL;
CEquityProtection *g_equity_protection = NULL;
CConsecutiveLossTracker *g_loss_tracker = NULL;
CStateManager *g_state_manager = NULL;
CSignalArbitrator *g_arbitrator = NULL;

STradeSignal      g_last_signal;
datetime          g_last_bar   = 0;
bool              g_initialized= false;

// Previous day HOD/LOD storage
double            g_prev_hod   = 0;
double            g_prev_lod   = DBL_MAX;

//==================================================================
//  INITIALIZATION
//==================================================================
int OnInit()
  {
   Print("====================================================");
   Print("  BTMM Expert Advisor v", BTMM_VERSION, " initializing...");
   Print("  Symbol: ", _Symbol, " | TF: ", EnumToString(_Period));
   Print("====================================================");

   PricingInit(_Symbol);

   // Recommended timeframe check
   if(_Period != PERIOD_M15 && _Period != PERIOD_H1)
      Print("WARNING: BTMM works best on M15 or H1 charts");

   // Detect GMT offset
   int gmt_off = InpAutoDetectGMT ? (int)(TimeCurrent() - TimeGMT()) / 3600
                                   : InpGMTOffset;
   Print("GMT Offset: ", gmt_off, "h");

   //--- Create engines
   g_session    = new CSessionManager(_Symbol, _Period, gmt_off);
   g_cycle      = new CMarketCycle(_Symbol, _Period, g_session);
   g_indicators = new CIndicatorEngine(_Symbol, _Period);
   g_signals    = new CSignalEngine(_Symbol, _Period,
                                     g_session, g_cycle, g_indicators);
   g_trader     = new CTradeManager(_Symbol, _Period, InpMagicNumber);
   g_dashboard  = new CDashboard(_Symbol, _Period,
                                  g_session, g_cycle, g_indicators,
                                  InpPanelX, InpPanelY);
   g_liquidity  = new CLiquidityEngine(_Symbol, _Period);
   g_validator  = new CExecutionValidator(_Symbol);
   g_portfolio  = new CPortfolioRiskManager(_Symbol, InpMagicNumber);
   g_market_maker = new CMarketMakerEngine(_Symbol, _Period, g_indicators);

   g_validator.SetMaxSpread(InpMaxSpreadPips);
   g_validator.SetMaxRisk(InpRiskPct);
   g_validator.SetMaxDailyLoss(InpMaxDailyLossPct);
   g_validator.SetMaxExposure(InpMaxExposurePct);

   g_portfolio.Configure(InpMaxOpenRiskPct, InpMaxDailyLossPct, InpMaxWeeklyLossPct,
                         InpMaxOpenTrades, InpMaxExposurePct);

   g_signals.SetLiquidityEngine(g_liquidity);
   g_signals.SetMarketMakerEngine(g_market_maker);
   g_market_maker.SetLiquidityEngine(g_liquidity);
   g_market_maker.SetSessionManager(g_session);
   g_trader.SetExecutionValidator(g_validator);
   g_trader.SetPortfolioRisk(g_portfolio);

   //--- Init indicators
   if(!g_indicators.Init())
     {
      Print("FATAL: Indicator init failed");
      return INIT_FAILED;
     }

   //--- Risk configuration
   if(InpUseFixedLots)
      g_trader.SetFixedLots(InpFixedLots);
   else
      g_trader.SetRisk(InpRiskPct, InpMaxLots);

   //--- Behaviour flags
   g_trader.SetScaleIn (InpUseScaleIn);
   g_trader.SetTrailing(InpUseTrailingStop);
   g_trader.SetScratch (InpScratchTrades);
   g_trader.SyncOpenPosition();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("WARNING: Terminal trading disabled - enable it in MT5 toolbar");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      Print("WARNING: Algo Trading is OFF - click Algo Trading button in MT5");

   //--- History rebuild
   g_indicators.Refresh();
   g_cycle.Rebuild(500);
   Print("History rebuild complete (500 bars)");

   //--- Store prev day HOD/LOD
   g_prev_hod = iHigh(_Symbol, PERIOD_D1, 1);
   g_prev_lod = iLow (_Symbol, PERIOD_D1, 1);
   g_signals.SetPrevHODLOD(g_prev_hod, g_prev_lod);

   ZeroMemory(g_last_signal);
   g_last_bar   = 0;
   g_initialized= true;

   // Initial chart refresh
   if(InpShowDashboard)
     {
      g_dashboard.SetDisplayFlags(InpShowPivots, InpShowADR,
                                  InpShowAsianRange, InpShowMWPattern);
      STradeSignal empty; ZeroMemory(empty);
      g_dashboard.FullRedraw(empty);
     }

   // Set chart properties for BTMM style
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,  clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL,  clrLimeGreen);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR,  clrRed);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,     clrLimeGreen);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,   clrRed);
   ChartSetInteger(0, CHART_SHOW_GRID,          false);
   ChartSetInteger(0, CHART_SHIFT,              true);

   //--- Initialize equity protection
   g_equity_protection = new CEquityProtection(_Symbol);
   g_equity_protection.Configure(InpMaxEquityDrawdownPercent, InpPersistProtectionState);
   if(InpPersistProtectionState)
      g_equity_protection.LoadState();
   g_equity_protection.Enable();
   
   Print("Equity Protection Initialized | Max Drawdown: ", InpMaxEquityDrawdownPercent, "%");

   //--- Initialize consecutive loss tracker
   g_loss_tracker = new CConsecutiveLossTracker(_Symbol, InpMagicNumber);
   g_loss_tracker.Configure(InpMaxConsecutiveLosses, InpPersistConsecutiveLossState);
   if(InpPersistConsecutiveLossState)
      g_loss_tracker.LoadState();
   
   Print("Consecutive Loss Tracker initialized | Max losses: ", InpMaxConsecutiveLosses);

   //--- Initialize state manager
   g_state_manager = new CStateManager(_Symbol, InpMagicNumber);
   
   SPersistedState loaded_state;
   if(g_state_manager.StateExists())
   {
      if(g_state_manager.LoadState(loaded_state))
      {
         if(g_equity_protection != NULL)
         {
            g_equity_protection.m_peak_equity = loaded_state.peak_equity;
            g_equity_protection.m_protection_active = loaded_state.equity_protection_active;
            Print("Equity protection state restored: Peak=", loaded_state.peak_equity,
                  " | Active=", loaded_state.equity_protection_active);
         }
         
         if(g_loss_tracker != NULL)
         {
            g_loss_tracker.m_consecutive_losses = loaded_state.consecutive_losses;
            g_loss_tracker.m_consecutive_wins = loaded_state.consecutive_wins;
            g_loss_tracker.m_trading_suspended = loaded_state.trading_suspended;
            Print("Consecutive loss state restored: Losses=", loaded_state.consecutive_losses,
                  " | Suspended=", loaded_state.trading_suspended);
         }
      }
   }
   else
   {
      Print("No previous state found - starting fresh");
   }

   //--- Initialize signal arbitrator
   g_arbitrator = new CSignalArbitrator(_Symbol, _Period, g_session, g_cycle, g_indicators);
   g_arbitrator.SetLiquidityEngine(g_liquidity);
   g_arbitrator.SetMarketMakerEngine(g_market_maker);
   g_arbitrator.SetMinConfluence(InpMinConfluence);
   g_arbitrator.SetLiquidityRequired(true);
   g_arbitrator.SetRegimeConfirmationRequired(true);
   
   Print("Signal Arbitrator initialized");

   Print("BTMM EA initialized successfully");
   return INIT_SUCCEEDED;
  }

//==================================================================
//  DEINITIALIZATION
//==================================================================
void OnDeinit(const int reason)
  {
   Print("BTMM EA deinitializing... reason=", reason);

   // Save all state before shutdown
   if(g_state_manager != NULL)
   {
      SPersistedState state_to_save;
      ZeroMemory(state_to_save);
      
      if(g_equity_protection != NULL)
      {
         state_to_save.peak_equity = g_equity_protection.GetPeakEquity();
         state_to_save.equity_protection_active = g_equity_protection.IsProtectionActive();
         state_to_save.current_drawdown_pct = g_equity_protection.GetCurrentDrawdownPercent();
      }
      
      if(g_loss_tracker != NULL)
      {
         state_to_save.consecutive_losses = g_loss_tracker.GetConsecutiveLosses();
         state_to_save.consecutive_wins = g_loss_tracker.GetConsecutiveWins();
         state_to_save.trading_suspended = g_loss_tracker.IsSuspended();
      }
      
      state_to_save.last_update = TimeCurrent();
      state_to_save.system_healthy = true;
      
      g_state_manager.SaveState(state_to_save);
      delete g_state_manager;
   }
   g_state_manager = NULL;

   if(g_dashboard  != NULL) { g_dashboard.ClearAll(); delete g_dashboard; }
   if(g_arbitrator != NULL) delete g_arbitrator;
   if(g_equity_protection != NULL) { g_equity_protection.SaveState(); delete g_equity_protection; }
   if(g_loss_tracker != NULL) { g_loss_tracker.SaveState(); delete g_loss_tracker; }
   if(g_trader     != NULL) delete g_trader;
   if(g_signals    != NULL) delete g_signals;
   if(g_indicators != NULL) delete g_indicators;
   if(g_cycle      != NULL) delete g_cycle;
   if(g_session    != NULL) delete g_session;
   if(g_liquidity  != NULL) delete g_liquidity;
   if(g_validator  != NULL) delete g_validator;
   if(g_portfolio  != NULL) delete g_portfolio;
   if(g_market_maker != NULL) delete g_market_maker;

   g_dashboard  = NULL;
   g_arbitrator = NULL;
   g_equity_protection = NULL;
   g_loss_tracker = NULL;
   g_trader     = NULL;
   g_signals    = NULL;
   g_indicators = NULL;
   g_cycle      = NULL;
   g_session    = NULL;
   g_liquidity  = NULL;
   g_validator  = NULL;
   g_portfolio  = NULL;
   g_market_maker = NULL;

   Print("BTMM EA shutdown complete");
  }

//==================================================================
//  ON TICK
//==================================================================
void OnTick()
  {
   if(!g_initialized) return;

   //--- Manage open trades on every tick
   if(g_trader != NULL) 
      g_trader.ManageTrades();

   //--- New bar check (bar-based logic)
   datetime cur_bar = iTime(_Symbol, _Period, 0);
   if(cur_bar == g_last_bar) return;
   g_last_bar = cur_bar;
   
   Print(">>> OnNewBar() executing - ", TimeToString(TimeCurrent()));
   OnNewBar();
  }

//==================================================================
//  ON NEW BAR
//==================================================================
void OnNewBar()
  {
   if(!g_initialized) return;

   // Update loss tracking
   if(g_loss_tracker != NULL)
      g_loss_tracker.Update();

   // Check consecutive loss suspension BEFORE other processing
   if(g_loss_tracker != NULL && g_loss_tracker.IsSuspended())
   {
      Print("BTMM: Consecutive loss suspension active - trading blocked");
      return;
   }

   //--- Check equity protection FIRST
   if(g_equity_protection != NULL)
   {
      if(!g_equity_protection.Update())
      {
         Print("BTMM: Equity protection active - new trades blocked");
         return;
      }
   }

   //--- Refresh indicators first
   g_indicators.Refresh();

   if(g_liquidity != NULL)
      g_liquidity.UpdateLiquidityLevels();

   if(g_market_maker != NULL)
      g_market_maker.UpdatePhase();

   //--- Update cycle for new bar
   g_cycle.OnNewBar(0);

   //--- Update session
   datetime t = iTime(_Symbol, _Period, 0);
   g_session.ResetDaily(t);
   g_session.UpdateAsianRange(t,
                               iHigh(_Symbol, _Period, 0),
                               iLow (_Symbol, _Period, 0));

   //--- Daily HOD/LOD reset check
   if(g_session.IsDailyResetTime(t))
     {
      g_prev_hod = g_cycle.GetHOD();
      g_prev_lod = g_cycle.GetLOD();
      g_signals.SetPrevHODLOD(g_prev_hod, g_prev_lod);
      Print("Daily reset | Prev HOD=", g_prev_hod, " | Prev LOD=", g_prev_lod);
     }

   //--- Seasonal / news filters
   bool allow_new_trade = CheckSeasonalFilter(t) && CheckNFPFilter(t);
   if(!allow_new_trade)
      Print("DEBUG: Seasonal/NFP filter active - new trades blocked this bar");

   //--- Get ALL signals
   STradeSignal sig = {};
   STradeSignal sig_mw_leg2 = IsSetupEnabled(SETUP_MW_LEG2) ? g_signals.Signal_MW_Leg2() : sig;
   STradeSignal sig_ema200 = IsSetupEnabled(SETUP_EMA200_BOUNCE) ? g_signals.Signal_EMA200Bounce() : sig;
   STradeSignal sig_trade33 = IsSetupEnabled(SETUP_TRADE_33) ? g_signals.Signal_Trade33() : sig;
   STradeSignal sig_nyc = IsSetupEnabled(SETUP_NYC_REVERSAL) ? g_signals.Signal_NYCReversal() : sig;
   STradeSignal sig_swing = IsSetupEnabled(SETUP_SWING) ? g_signals.Signal_Swing() : sig;
   STradeSignal sig_straightaway = IsSetupEnabled(SETUP_STRAIGHTAWAY) ? g_signals.Signal_Straightaway() : sig;
   STradeSignal sig_half_batman = IsSetupEnabled(SETUP_HALF_BATMAN) ? g_signals.Signal_HalfBatman() : sig;
   STradeSignal sig_stop_hunt = IsSetupEnabled(SETUP_STOP_HUNT) ? g_signals.Signal_StopHuntFade() : sig;

   //--- USE ARBITRATOR to select best signal
   if(g_arbitrator != NULL)
   {
      sig = g_arbitrator.SelectBestSignal(
         sig_mw_leg2, sig_ema200, sig_trade33, sig_nyc,
         sig_swing, sig_straightaway, sig_half_batman, sig_stop_hunt
      );
   }

   //--- Execute trade automatically at market
   if(sig.valid && InpEnableTrading && !g_trader.IsInTrade())
     {
      bool window_ok = !InpRequireTimeWindow || IsWindowActive(t);

      if(allow_new_trade && window_ok)
        {
         if(InpTP1_Pips > 0)
           {
            double tp1_dist = PipsToPrice(InpTP1_Pips);
            sig.tp1 = (sig.direction == DIR_LONG) ?
                       sig.entry + tp1_dist :
                       sig.entry - tp1_dist;
           }
         if(g_trader.OpenTrade(sig))
           {
            g_last_signal = sig;
            FireAlerts(sig);
            Print("BTMM TRADE OPENED: ", sig.notes);
           }
         else
           {
            Print("ERROR: Failed to open trade");
           }
        }
     }

   //--- Dashboard refresh
   if(InpShowDashboard)
      g_dashboard.Refresh(sig.valid ? sig : g_last_signal);

   //--- Console log
   PrintStatus(sig);
  }

//==================================================================
//  HELPER: Is this setup type enabled by inputs?
//==================================================================
bool IsSetupEnabled(ENUM_BTMM_SETUP setup)
  {
   switch(setup)
     {
      case SETUP_MW_LEG2:       return InpTrade_MW_Leg2;
      case SETUP_TRADE_33:      return InpTrade_33;
      case SETUP_NYC_REVERSAL:  return InpTrade_NYC;
      case SETUP_EMA200_BOUNCE: return InpTrade_EMA200;
      case SETUP_SWING:         return InpTrade_Swing;
      case SETUP_STRAIGHTAWAY:  return InpTrade_Straight;
      case SETUP_HALF_BATMAN:   return InpTrade_HalfBat;
      case SETUP_STOP_HUNT:     return InpTrade_StopHunt;
      default:                  return false;
     }
  }

//==================================================================
//  HELPER: Trading window active?
//==================================================================
bool IsWindowActive(datetime t)
  {
   bool london_ok = InpTradeAsiaLondon && g_session.IsLondonTradingWindow(t);
   bool us_ok     = InpTradeUSOpen     && g_session.IsUSOpenWindow(t);
   return (london_ok || us_ok);
  }

//==================================================================
//  HELPER: Seasonal filter
//==================================================================
bool CheckSeasonalFilter(datetime t)
  {
   if(!InpAvoidDecJan) return true;
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(dt.mon == 12 && dt.day >= 15) return false;
   if(dt.mon == 1  && dt.day <= 15) return false;
   return true;
  }

//==================================================================
//  HELPER: NFP filter
//==================================================================
bool CheckNFPFilter(datetime t)
  {
   if(!InpAvoidNFP) return true;
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(dt.day_of_week != 5) return true;
   if(dt.day > 7)          return true;
   
   int et_hour = dt.hour - InpGMTOffset + 5;
   if(et_hour < 0) et_hour += 24;
   if(et_hour > 23) et_hour -= 24;
   
   if(et_hour >= 8 && et_hour <= 9) 
      return false;
   
   return true;
  }

//==================================================================
//  HELPER: Fire alerts
//==================================================================
void FireAlerts(const STradeSignal &sig)
  {
   string msg = StringFormat(
     "BTMM SIGNAL | %s | %s | %s | C=%d%% | E:%.5f SL:%.5f TP:%.5f",
     sig.symbol,
     sig.direction==DIR_LONG ? "LONG ^" : "SHORT v",
     EnumToString(sig.setup_type),
     sig.confluence_score,
     sig.entry, sig.stop_loss, sig.tp1
   );

   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("BTMM Signal: " + sig.symbol, msg);
   if(InpAlertSound) PlaySound("alert.wav");
  }

//==================================================================
//  HELPER: Status log
//==================================================================
void PrintStatus(const STradeSignal &sig)
  {
   static int bar_count = 0;
   bar_count++;
   if(bar_count % 10 != 0) return;

   Print("_____________________________________________ ");
   Print(" BTMM | ", _Symbol, " | ", TimeToString(TimeCurrent()));
   
   if(g_equity_protection != NULL)
   {
      SEquitySnapshot snap = g_equity_protection.GetSnapshot();
      Print(" Equity: ", DoubleToString(snap.equity, 2),
            " | Drawdown: ", DoubleToString(snap.current_drawdown_pct, 2), "%",
            " | Protection: ", snap.protection_active ? "ACTIVE ⚠" : "OK");
   }

   if(g_loss_tracker != NULL)
   {
      SConsecutiveLossSnapshot snap = g_loss_tracker.GetSnapshot();
      Print(" Losses: ", snap.consecutive_losses, "/", InpMaxConsecutiveLosses,
            " | Wins: ", snap.consecutive_wins,
            " | Suspended: ", snap.trading_suspended ? "YES ⚠" : "NO");
   }

   Print(" Level: ", g_cycle.LevelDescription());
   if(g_market_maker != NULL)
      Print(" MM Phase: ", g_market_maker.GetPhaseDescription());
   Print(" Phase: ", g_cycle.PhaseDescription());
   SAsianRange ar = g_session.GetAsianRange();
   if(ar.valid)
      Print(" Asian Range: ", ar.range_pips, " pips");
   if(sig.valid)
      Print(" SIGNAL: ", EnumToString(sig.setup_type), " | C=", sig.confluence_score, "%");
   if(g_trader.IsInTrade())
      Print(" TRADE: ", g_trader.StatusString());
   Print("_____________________________________________ ");
  }

//==================================================================
//  ON CHART EVENT
//==================================================================
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_KEYDOWN)
     {
      if(lparam == 82 && InpShowDashboard)
        {
         STradeSignal empty; ZeroMemory(empty);
         g_dashboard.FullRedraw(g_last_signal.valid ? g_last_signal : empty);
         Print("BTMM: Manual redraw triggered");
        }
      if(lparam == 67 && g_trader != NULL)
        {
         g_trader.CloseAllTrades();
         Print("BTMM: Manual close all trades");
        }
      if(lparam == 83 && g_trader != NULL && g_trader.IsInTrade())
        {
         g_trader.ConvertToSwing();
         Print("BTMM: Converted to swing trade");
        }
     }
  }

//==================================================================
//  ON TRADE TRANSACTION
//==================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
         Print("BTMM Transaction: Deal added | Ticket=", trans.deal,
               " | Volume=", trans.volume, " | Price=", trans.price);
     }
  }
//+------------------------------------------------------------------+