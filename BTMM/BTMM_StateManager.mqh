#ifndef __BTMM_STATEMANAGER_MQH__
#define __BTMM_STATEMANAGER_MQH__

//==================================================================
// FIX 6: STATE PERSISTENCE
// Survives terminal restart, VPS reboot, crashes
//==================================================================

struct SPersistedState
{
   double peak_equity;
   bool equity_protection_active;
   double current_drawdown_pct;
   int consecutive_losses;
   int consecutive_wins;
   bool trading_suspended;
   datetime last_update;
   bool system_healthy;
};

class CStateManager
{
private:
   string m_symbol;
   int m_magic;
   string m_state_filename;
   
public:
   CStateManager(string symbol, int magic);
   ~CStateManager();
   
   bool SaveState(const SPersistedState &state);
   bool LoadState(SPersistedState &state);
   bool StateExists();
   bool DeleteState();
   datetime GetLastUpdateTime();
};

CStateManager::CStateManager(string symbol, int magic)
{
   m_symbol = symbol;
   m_magic = magic;
   m_state_filename = "BTMM_States/" + symbol + "_PersistedState.bin";
}

CStateManager::~CStateManager()
{
}

bool CStateManager::SaveState(const SPersistedState &state)
{
   int file_handle = FileOpen(m_state_filename, FILE_WRITE | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open state file for writing: ", m_state_filename);
      return false;
   }
   
   // Write state structure
   FileWriteDouble(file_handle, state.peak_equity);
   FileWriteBool(file_handle, state.equity_protection_active);
   FileWriteDouble(file_handle, state.current_drawdown_pct);
   FileWriteInteger(file_handle, state.consecutive_losses);
   FileWriteInteger(file_handle, state.consecutive_wins);
   FileWriteBool(file_handle, state.trading_suspended);
   FileWriteLong(file_handle, (long)state.last_update);
   FileWriteBool(file_handle, state.system_healthy);
   FileWriteLong(file_handle, (long)TimeCurrent());
   
   FileClose(file_handle);
   
   Print("State persisted to disk | Peak: ", DoubleToString(state.peak_equity, 2),
         " | Protected: ", state.equity_protection_active, " | Losses: ", state.consecutive_losses);
   
   return true;
}

bool CStateManager::LoadState(SPersistedState &state)
{
   int file_handle = FileOpen(m_state_filename, FILE_READ | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
   {
      Print("No state file found: ", m_state_filename);
      return false;
   }
   
   // Read state structure
   state.peak_equity = FileReadDouble(file_handle);
   state.equity_protection_active = FileReadBool(file_handle);
   state.current_drawdown_pct = FileReadDouble(file_handle);
   state.consecutive_losses = FileReadInteger(file_handle);
   state.consecutive_wins = FileReadInteger(file_handle);
   state.trading_suspended = FileReadBool(file_handle);
   state.last_update = (datetime)FileReadLong(file_handle);
   state.system_healthy = FileReadBool(file_handle);
   datetime file_write_time = (datetime)FileReadLong(file_handle);
   
   FileClose(file_handle);
   
   Print("State loaded from disk | Peak: ", DoubleToString(state.peak_equity, 2),
         " | Protected: ", state.equity_protection_active, " | Losses: ", state.consecutive_losses,
         " | File age: ", (int)((TimeCurrent() - file_write_time) / 60), " minutes");
   
   return true;
}

bool CStateManager::StateExists()
{
   return FileIsExist(m_state_filename, FILE_COMMON);
}

bool CStateManager::DeleteState()
{
   if(!StateExists())
      return true;
   
   return FileDelete(m_state_filename, FILE_COMMON);
}

datetime CStateManager::GetLastUpdateTime()
{
   int file_handle = FileOpen(m_state_filename, FILE_READ | FILE_BIN);
   if(file_handle == INVALID_HANDLE)
      return 0;
   
   // Skip to last_update field (8 bools/ints + 2 doubles = 56 bytes, then 1 long = 8 bytes into datetime)
   FileSeek(file_handle, 56, SEEK_SET);  // Move to last_update position
   datetime last_update = (datetime)FileReadLong(file_handle);
   
   FileClose(file_handle);
   return last_update;
}

#endif
