#ifndef __BTMM_SIGNALARBITRATOR_MQH__
#define __BTMM_SIGNALARBITRATOR_MQH__

#include "BTMM_Defines.mqh"
#include "BTMM_Pricing.mqh"
#include "BTMM_Sessions.mqh"
#include "BTMM_MarketCycle.mqh"
#include "BTMM_Indicators.mqh"
#include "PRIORITY_3_LiquidityEngine.mqh"
#include "BTMM_MarketMaker.mqh"

//==================================================================
// FIX 4: SIGNAL ARBITRATION ENGINE
// Selects best signal when multiple setups trigger simultaneously
// Scoring: 40% Confluence + 25% Liquidity + 20% Regime + 15% R/R
//==================================================================

struct SSignalScore
{
   STradeSignal signal;
   double confluence_score;
   double liquidity_score;
   double regime_score;
   double rr_score;
   double final_score;
   bool passed_minimum_gates;
   string rejection_reason;
};

class CSignalArbitrator
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_period;
   CSessionManager *m_session;
   CMarketCycle *m_cycle;
   CIndicatorEngine *m_indicators;
   CLiquidityEngine *m_liquidity;
   CMarketMakerEngine *m_market_maker;
   
   int m_min_confluence;
   bool m_liquidity_required;
   bool m_regime_confirmation_required;
   
   SSignalScore m_evaluated_signals[];
   int m_signal_count;
   
   double ScoreLiquidity(const STradeSignal &sig);
   double ScoreRegime(const STradeSignal &sig);
   double ScoreRiskReward(const STradeSignal &sig);
   bool ValidateMinimumGates(const STradeSignal &sig);
   SSignalScore EvaluateSignal(const STradeSignal &sig);

public:
   CSignalArbitrator(string symbol, ENUM_TIMEFRAMES period,
                    CSessionManager *session, CMarketCycle *cycle,
                    CIndicatorEngine *indicators);
   ~CSignalArbitrator();
   
   void SetLiquidityEngine(CLiquidityEngine *liquidity);
   void SetMarketMakerEngine(CMarketMakerEngine *market_maker);
   void SetMinConfluence(int min_confluence);
   void SetLiquidityRequired(bool required);
   void SetRegimeConfirmationRequired(bool required);
   
   STradeSignal SelectBestSignal(
      const STradeSignal &sig1, const STradeSignal &sig2,
      const STradeSignal &sig3, const STradeSignal &sig4,
      const STradeSignal &sig5, const STradeSignal &sig6,
      const STradeSignal &sig7, const STradeSignal &sig8
   );
   
   SSignalScore GetLastEvaluatedSignal(int index);
   int GetEvaluatedSignalCount();
};

CSignalArbitrator::CSignalArbitrator(string symbol, ENUM_TIMEFRAMES period,
                                     CSessionManager *session, CMarketCycle *cycle,
                                     CIndicatorEngine *indicators)
{
   m_symbol = symbol;
   m_period = period;
   m_session = session;
   m_cycle = cycle;
   m_indicators = indicators;
   m_liquidity = NULL;
   m_market_maker = NULL;
   m_min_confluence = 50;
   m_liquidity_required = true;
   m_regime_confirmation_required = true;
   m_signal_count = 0;
}

CSignalArbitrator::~CSignalArbitrator()
{
}

void CSignalArbitrator::SetLiquidityEngine(CLiquidityEngine *liquidity)
{
   m_liquidity = liquidity;
}

void CSignalArbitrator::SetMarketMakerEngine(CMarketMakerEngine *market_maker)
{
   m_market_maker = market_maker;
}

void CSignalArbitrator::SetMinConfluence(int min_confluence)
{
   m_min_confluence = MathMax(0, MathMin(100, min_confluence));
}

void CSignalArbitrator::SetLiquidityRequired(bool required)
{
   m_liquidity_required = required;
}

void CSignalArbitrator::SetRegimeConfirmationRequired(bool required)
{
   m_regime_confirmation_required = required;
}

bool CSignalArbitrator::ValidateMinimumGates(const STradeSignal &sig)
{
   // Gate 1: Signal must be valid
   if(!sig.valid)
      return false;
   
   // Gate 2: Confluence must meet minimum
   if(sig.confluence_score < m_min_confluence)
      return false;
   
   // Gate 3: SL and TP must be non-zero and properly oriented
   if(sig.stop_loss <= 0 || sig.tp1 <= 0)
      return false;
   
   if(sig.direction == DIR_LONG)
   {
      if(sig.stop_loss >= sig.entry || sig.tp1 <= sig.entry)
         return false;
   }
   else if(sig.direction == DIR_SHORT)
   {
      if(sig.stop_loss <= sig.entry || sig.tp1 >= sig.entry)
         return false;
   }
   
   return true;
}

double CSignalArbitrator::ScoreLiquidity(const STradeSignal &sig)
{
   if(m_liquidity == NULL)
      return 50.0;
   
   double close = iClose(m_symbol, m_period, 0);
   double score = 40.0;
   
   // Check for nearby liquidity levels
   SLiquidityLevel above = m_liquidity.GetNearestLiquidityAbove(close);
   SLiquidityLevel below = m_liquidity.GetNearestLiquidityBelow(close);
   
   if(sig.direction == DIR_LONG && below.price > 0)
   {
      double distance_pips = PriceToPips(close - below.price);
      if(distance_pips <= 100.0)  // Within 100 pips
         score += 30.0;
      else if(distance_pips <= 200.0)
         score += 15.0;
   }
   else if(sig.direction == DIR_SHORT && above.price > 0)
   {
      double distance_pips = PriceToPips(above.price - close);
      if(distance_pips <= 100.0)
         score += 30.0;
      else if(distance_pips <= 200.0)
         score += 15.0;
   }
   
   return MathMin(score, 100.0);
}

double CSignalArbitrator::ScoreRegime(const STradeSignal &sig)
{
   if(m_market_maker == NULL)
      return 50.0;
   
   double score = 50.0;
   ENUM_MM_PHASE phase = m_market_maker.GetCurrentPhase();
   
   // Score based on setup type alignment with market phase
   switch(sig.setup_type)
   {
      case SETUP_MW_LEG2:
      case SETUP_STOP_HUNT:
      case SETUP_HALF_BATMAN:
         if(phase == MM_PHASE_MANIPULATION)
            score = 85.0;  // Ideal phase for these setups
         else if(phase == MM_PHASE_ACCUMULATION)
            score = 70.0;
         break;
      
      case SETUP_STRAIGHTAWAY:
      case SETUP_SWING:
         if(phase == MM_PHASE_EXPANSION)
            score = 85.0;  // Ideal for expansion setups
         else if(phase == MM_PHASE_DISTRIBUTION)
            score = 60.0;
         break;
      
      case SETUP_TRADE_33:
         if(phase == MM_PHASE_ACCUMULATION)
            score = 80.0;  // 1/3-2/3 setups work well in accumulation
         else if(phase == MM_PHASE_EXPANSION)
            score = 65.0;
         break;
      
      case SETUP_EMA200_BOUNCE:
      case SETUP_NYC_REVERSAL:
         if(phase == MM_PHASE_MANIPULATION || phase == MM_PHASE_EXPANSION)
            score = 75.0;
         break;
      
      default:
         score = 50.0;
   }
   
   return MathMin(score, 100.0);
}

double CSignalArbitrator::ScoreRiskReward(const STradeSignal &sig)
{
   double risk_dist = MathAbs(sig.entry - sig.stop_loss);
   double reward_dist = MathAbs(sig.tp1 - sig.entry);
   
   if(risk_dist <= 0 || reward_dist <= 0)
      return 0.0;
   
   double rr_ratio = reward_dist / risk_dist;
   
   double score = 50.0;
   
   if(rr_ratio >= 2.0)
      score = 90.0;  // Excellent R/R
   else if(rr_ratio >= 1.5)
      score = 75.0;  // Good R/R
   else if(rr_ratio >= 1.0)
      score = 60.0;  // Fair R/R
   else if(rr_ratio >= 0.8)
      score = 40.0;  // Poor R/R
   else
      score = 20.0;  // Very poor R/R
   
   return MathMin(score, 100.0);
}

SSignalScore CSignalArbitrator::EvaluateSignal(const STradeSignal &sig)
{
   SSignalScore score_result;
   ZeroMemory(score_result);
   score_result.signal = sig;
   score_result.confluence_score = sig.confluence_score;
   
   // Check minimum gates first
   if(!ValidateMinimumGates(sig))
   {
      score_result.passed_minimum_gates = false;
      score_result.rejection_reason = "Failed minimum gates";
      score_result.final_score = 0.0;
      return score_result;
   }
   
   score_result.passed_minimum_gates = true;
   
   // Calculate component scores
   score_result.liquidity_score = ScoreLiquidity(sig);
   score_result.regime_score = ScoreRegime(sig);
   score_result.rr_score = ScoreRiskReward(sig);
   
   // Calculate final score: 40% Confluence + 25% Liquidity + 20% Regime + 15% R/R
   score_result.final_score = (sig.confluence_score * 0.40) +
                              (score_result.liquidity_score * 0.25) +
                              (score_result.regime_score * 0.20) +
                              (score_result.rr_score * 0.15);
   
   return score_result;
}

STradeSignal CSignalArbitrator::SelectBestSignal(
   const STradeSignal &sig1, const STradeSignal &sig2,
   const STradeSignal &sig3, const STradeSignal &sig4,
   const STradeSignal &sig5, const STradeSignal &sig6,
   const STradeSignal &sig7, const STradeSignal &sig8)
{
   m_signal_count = 0;
   ArrayResize(m_evaluated_signals, 0);
   
   // Collect all signals
   STradeSignal all_signals[8] = {sig1, sig2, sig3, sig4, sig5, sig6, sig7, sig8};
   
   // Evaluate each signal
   for(int i = 0; i < 8; i++)
   {
      SSignalScore evaluated = EvaluateSignal(all_signals[i]);
      
      if(evaluated.passed_minimum_gates)
      {
         ArrayResize(m_evaluated_signals, m_signal_count + 1);
         m_evaluated_signals[m_signal_count] = evaluated;
         m_signal_count++;
         
         if(all_signals[i].valid)
         {
            Print("Signal Evaluation: ", EnumToString(all_signals[i].setup_type),
                  " | Final Score: ", DoubleToString(evaluated.final_score, 2),
                  " | Conf: ", (int)evaluated.confluence_score,
                  " | Liq: ", (int)evaluated.liquidity_score,
                  " | Regime: ", (int)evaluated.regime_score,
                  " | RR: ", (int)evaluated.rr_score);
         }
      }
      else if(all_signals[i].valid)
      {
         Print("Signal REJECTED: ", EnumToString(all_signals[i].setup_type),
               " | Reason: ", evaluated.rejection_reason);
      }
   }
   
   // Select best signal (highest final score)
   if(m_signal_count == 0)
   {
      STradeSignal empty;
      ZeroMemory(empty);
      Print("No valid signals after arbitration");
      return empty;
   }
   
   int best_index = 0;
   double best_score = m_evaluated_signals[0].final_score;
   
   for(int i = 1; i < m_signal_count; i++)
   {
      if(m_evaluated_signals[i].final_score > best_score)
      {
         best_score = m_evaluated_signals[i].final_score;
         best_index = i;
      }
   }
   
   Print("ARBITRATOR SELECTED: ", EnumToString(m_evaluated_signals[best_index].signal.setup_type),
         " with score ", DoubleToString(best_score, 2));
   
   return m_evaluated_signals[best_index].signal;
}

SSignalScore CSignalArbitrator::GetLastEvaluatedSignal(int index)
{
   SSignalScore empty;
   ZeroMemory(empty);
   
   if(index < 0 || index >= m_signal_count)
      return empty;
   
   return m_evaluated_signals[index];
}

int CSignalArbitrator::GetEvaluatedSignalCount()
{
   return m_signal_count;
}

#endif
