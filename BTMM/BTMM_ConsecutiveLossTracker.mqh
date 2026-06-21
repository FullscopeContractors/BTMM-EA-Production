#ifndef __BTMM_CONSECUTIVELOSSTRACKER_MQH__
#define __BTMM_CONSECUTIVELOSSTRACKER_MQH__

#include "BTMM_Pricing.mqh"

//==================================================================
// FIX 5: CONSECUTIVE LOSS PROTECTION
// Suspends trading after N consecutive losses
//==================================================================

struct SConsecutiveLossSnapshot
{
   int consecutive_losses;
   int consecutive_wins;
   int total_trades;
   bool trading_suspended;
   datetime last_trade_time;
};

class CConsecutiveLossTracker
{
private:
   string m_symbol;
   int m_magic;
   int m_max_consecutive_losses;
   bool m_persist_state;
   
public:
   int m_consecutive_losses;
   int m_consecutive_wins;
   int m_total_trades;
   bool m_trading_suspended;
   datetime m_last_trade_time;
   
private:
   void SaveStateInternal();
   void LoadStateInternal();
   string GetStateFilename();
   void CheckForNewTrade();

public:
   CConsecutiveLossTracker(string symbol, int magic);
   ~CConsecutiveLossTracker();
   
   void Configure(int max_losses, bool persist_state);
   void Update();
   void RecordWin();
   void RecordLoss();
   void ResetSuspension();
   
   void SaveState();
   void LoadState();
   
   SConsecutiveLossSnapshot GetSnapshot();
   int GetConsecutiveLosses();
   int GetConsecutiveWins();
   bool IsSuspended();
};

CConsecutiveLossTracker::CConsecutiveLossTracker(string symbol, int magic)
{
   m_symbol = symbol;
   m_magic = magic;
   m_max_consecutive_losses = 5;
   m_persist_state = true;
   m_consecutive_losses = 0;
   m_consecutive_wins = 0;
   m_total_trades = 0;
   m_trading_suspended = false;
   m_last_trade_time = 0;
}

CConsecutiveLossTracker::~CConsecutiveLossTracker()
{
   if(m_persist_state)
      SaveStateInternal();
}

void CConsecutiveLossTracker::Configure(int max_losses, bool persist_state)
{
   m_max_consecutive_losses = MathMax(1, max_losses);
   m_persist_state = persist_state;
}

void CConsecutiveLossTracker::CheckForNewTrade()
{
   // Check if a new deal was executed
   int deals_total = HistoryDealsTotal();
   
   for(int i = deals_total - 1; i >= MathMax(0, deals_total - 10); i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      datetime deal_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      
      if(deal_time <= m_last_trade_time)
         continue;  // Already processed
      
      long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      
      if(deal_magic != m_magic)
         continue;  // Not our trade
      
      // Check if this is a closing deal (has opposing profit)
      if(deal_type == DEAL_TYPE_SELL || deal_type == DEAL_TYPE_BUY)
      {
         m_last_trade_time = deal_time;
         m_total_trades++;
         
         if(profit >= 0)
         {
            RecordWin();
            Print("Trade WIN recorded | Consecutive Wins: ", m_consecutive_wins, " | Losses: ", m_consecutive_losses);
         }
         else
         {
            RecordLoss();
            Print("Trade LOSS recorded | Consecutive Losses: ", m_consecutive_losses, " | Wins: ", m_consecutive_wins);
            
            if(m_consecutive_losses >= m_max_consecutive_losses)
            {
               m_trading_suspended = true;
               Print("!!! CONSECUTIVE LOSS LIMIT REACHED (", m_consecutive_losses, "/", m_max_consecutive_losses, ") - TRADING SUSPENDED !!!");
            }
         }
      }
   }
}

void CConsecutiveLossTracker::Update()
{
   CheckForNewTrade();
}

void CConsecutiveLossTracker::RecordWin()
{
   m_consecutive_wins++;
   m_consecutive_losses = 0;
}

void CConsecutiveLossTracker::RecordLoss()
{
   m_consecutive_losses++;
   m_consecutive_wins = 0;
}

void CConsecutiveLossTracker::ResetSuspension()
{
   m_trading_suspended = false;
   m_consecutive_losses = 0;
   m_consecutive_wins = 0;
   Print("Consecutive loss suspension manually RESET");
}

string CConsecutiveLossTracker::GetStateFilename()
{
   return "BTMM_States/" + m_symbol + "_ConsecutiveLosses.bin";
}

void CConsecutiveLossTracker::SaveStateInternal()
{
   if(!m_persist_state)
      return;
   
   int file_handle = FileOpen(GetStateFilename(), FILE_WRITE | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
   {
      Print("WARNING: Could not open file for consecutive loss state save");
      return;
   }
   
   FileWriteInteger(file_handle, m_consecutive_losses);
   FileWriteInteger(file_handle, m_consecutive_wins);
   FileWriteInteger(file_handle, m_total_trades);
   FileWriteBool(file_handle, m_trading_suspended);
   FileWriteLong(file_handle, (long)m_last_trade_time);
   FileWriteLong(file_handle, (long)TimeCurrent());
   
   FileClose(file_handle);
   Print("Consecutive loss state saved | Losses: ", m_consecutive_losses, " | Suspended: ", m_trading_suspended);
}

void CConsecutiveLossTracker::LoadStateInternal()
{
   if(!m_persist_state)
      return;
   
   int file_handle = FileOpen(GetStateFilename(), FILE_READ | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
   {
      Print("No previous consecutive loss state found");
      return;
   }
   
   m_consecutive_losses = FileReadInteger(file_handle);
   m_consecutive_wins = FileReadInteger(file_handle);
   m_total_trades = FileReadInteger(file_handle);
   m_trading_suspended = FileReadBool(file_handle);
   m_last_trade_time = (datetime)FileReadLong(file_handle);
   
   FileClose(file_handle);
   
   Print("Consecutive loss state loaded | Losses: ", m_consecutive_losses,
         " | Wins: ", m_consecutive_wins, " | Suspended: ", m_trading_suspended);
}

void CConsecutiveLossTracker::SaveState()
{
   SaveStateInternal();
}

void CConsecutiveLossTracker::LoadState()
{
   LoadStateInternal();
}

SConsecutiveLossSnapshot CConsecutiveLossTracker::GetSnapshot()
{
   SConsecutiveLossSnapshot snap;
   ZeroMemory(snap);
   
   snap.consecutive_losses = m_consecutive_losses;
   snap.consecutive_wins = m_consecutive_wins;
   snap.total_trades = m_total_trades;
   snap.trading_suspended = m_trading_suspended;
   snap.last_trade_time = m_last_trade_time;
   
   return snap;
}

int CConsecutiveLossTracker::GetConsecutiveLosses()
{
   return m_consecutive_losses;
}

int CConsecutiveLossTracker::GetConsecutiveWins()
{
   return m_consecutive_wins;
}

bool CConsecutiveLossTracker::IsSuspended()
{
   return m_trading_suspended;
}

#endif
