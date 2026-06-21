#ifndef __BTMM_EQUITYPROTECTION_MQH__
#define __BTMM_EQUITYPROTECTION_MQH__

#include "BTMM_Pricing.mqh"

//==================================================================
// FIX 2: EQUITY DRAWDOWN CIRCUIT BREAKER
// Global kill switch to prevent catastrophic losses
//==================================================================

struct SEquitySnapshot
{
   double equity;
   double balance;
   double peak_equity;
   double current_drawdown_pct;
   bool protection_active;
   datetime snapshot_time;
};

class CEquityProtection
{
private:
   string m_symbol;
   double m_max_drawdown_pct;
   bool m_persist_state;
   bool m_enabled;
   
public:
   double m_peak_equity;
   bool m_protection_active;
   
private:
   void SaveStateInternal();
   void LoadStateInternal();
   string GetStateFilename();

public:
   CEquityProtection(string symbol);
   ~CEquityProtection();
   
   void Configure(double max_drawdown_pct, bool persist_state);
   void Enable();
   void Disable();
   bool Update();
   
   void SaveState();
   void LoadState();
   
   SEquitySnapshot GetSnapshot();
   double GetPeakEquity();
   double GetCurrentDrawdownPercent();
   bool IsProtectionActive();
};

CEquityProtection::CEquityProtection(string symbol)
{
   m_symbol = symbol;
   m_max_drawdown_pct = 15.0;
   m_persist_state = true;
   m_enabled = false;
   m_peak_equity = 0;
   m_protection_active = false;
}

CEquityProtection::~CEquityProtection()
{
   if(m_persist_state)
      SaveStateInternal();
}

void CEquityProtection::Configure(double max_drawdown_pct, bool persist_state)
{
   m_max_drawdown_pct = max_drawdown_pct;
   m_persist_state = persist_state;
   m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
}

void CEquityProtection::Enable()
{
   m_enabled = true;
   m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("Equity Protection ENABLED | Max Drawdown: ", m_max_drawdown_pct, "% | Peak: ", DoubleToString(m_peak_equity, 2));
}

void CEquityProtection::Disable()
{
   m_enabled = false;
   m_protection_active = false;
}

bool CEquityProtection::Update()
{
   if(!m_enabled)
      return true;
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update peak equity if new high reached
   if(current_equity > m_peak_equity)
   {
      m_peak_equity = current_equity;
      m_protection_active = false;  // Reset protection on new peak
      Print("New Peak Equity: ", DoubleToString(m_peak_equity, 2));
      return true;
   }
   
   // Calculate current drawdown
   double drawdown = m_peak_equity - current_equity;
   double drawdown_pct = (drawdown / m_peak_equity) * 100.0;
   
   // Check protection threshold
   if(drawdown_pct >= m_max_drawdown_pct)
   {
      m_protection_active = true;
      
      if(drawdown_pct == m_max_drawdown_pct)  // Log only on threshold hit
      {
         Print("EQUITY PROTECTION TRIGGERED! | Drawdown: ", DoubleToString(drawdown_pct, 2),
               "% | Equity: ", DoubleToString(current_equity, 2), " | Peak: ", DoubleToString(m_peak_equity, 2));
      }
      
      return false;  // Block new trades
   }
   else if(m_protection_active && drawdown_pct < m_max_drawdown_pct * 0.95)  // Hysteresis
   {
      m_protection_active = false;
      Print("Equity Protection CLEARED | Drawdown: ", DoubleToString(drawdown_pct, 2), "%");
      return true;
   }
   
   return !m_protection_active;
}

string CEquityProtection::GetStateFilename()
{
   return "BTMM_States/" + m_symbol + "_EquityProtection.bin";
}

void CEquityProtection::SaveStateInternal()
{
   if(!m_persist_state)
      return;
   
   int file_handle = FileOpen(GetStateFilename(), FILE_WRITE | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
   {
      Print("WARNING: Could not open file for equity protection state save");
      return;
   }
   
   FileWriteDouble(file_handle, m_peak_equity);
   FileWriteBool(file_handle, m_protection_active);
   FileWriteDouble(file_handle, m_max_drawdown_pct);
   FileWriteLong(file_handle, (long)TimeCurrent());
   
   FileClose(file_handle);
   Print("Equity protection state saved");
}

void CEquityProtection::LoadStateInternal()
{
   if(!m_persist_state)
      return;
   
   int file_handle = FileOpen(GetStateFilename(), FILE_READ | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
   {
      Print("No previous equity protection state found");
      return;
   }
   
   m_peak_equity = FileReadDouble(file_handle);
   m_protection_active = FileReadBool(file_handle);
   double saved_threshold = FileReadDouble(file_handle);
   long saved_time = FileReadLong(file_handle);
   
   FileClose(file_handle);
   
   Print("Equity protection state loaded | Peak: ", DoubleToString(m_peak_equity, 2),
         " | Protected: ", m_protection_active);
}

void CEquityProtection::SaveState()
{
   SaveStateInternal();
}

void CEquityProtection::LoadState()
{
   LoadStateInternal();
}

SEquitySnapshot CEquityProtection::GetSnapshot()
{
   SEquitySnapshot snap;
   ZeroMemory(snap);
   
   snap.equity = AccountInfoDouble(ACCOUNT_EQUITY);
   snap.balance = AccountInfoDouble(ACCOUNT_BALANCE);
   snap.peak_equity = m_peak_equity;
   
   if(m_peak_equity > 0)
      snap.current_drawdown_pct = ((m_peak_equity - snap.equity) / m_peak_equity) * 100.0;
   else
      snap.current_drawdown_pct = 0;
   
   snap.protection_active = m_protection_active;
   snap.snapshot_time = TimeCurrent();
   
   return snap;
}

double CEquityProtection::GetPeakEquity()
{
   return m_peak_equity;
}

double CEquityProtection::GetCurrentDrawdownPercent()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(m_peak_equity <= 0)
      return 0;
   
   return ((m_peak_equity - equity) / m_peak_equity) * 100.0;
}

bool CEquityProtection::IsProtectionActive()
{
   return m_protection_active;
}

#endif
