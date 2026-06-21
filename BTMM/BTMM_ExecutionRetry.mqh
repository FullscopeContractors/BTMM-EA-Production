#ifndef __BTMM_EXECUTIONRETRY_MQH__
#define __BTMM_EXECUTIONRETRY_MQH__

#include <Trade\Trade.mqh>

//==================================================================
// FIX 3: EXECUTION RETRY FRAMEWORK
// Recovers from transient broker/network errors
//==================================================================

enum ENUM_RETRY_RESULT
{
   RETRY_SUCCESS = 0,
   RETRY_PERMANENT_FAILURE = 1,
   RETRY_MAX_ATTEMPTS_EXCEEDED = 2,
   RETRY_TRANSIENT_FAILURE = 3
};

struct SRetryAttempt
{
   int attempt_number;
   uint retcode;
   string retcode_description;
   datetime attempt_time;
   bool is_transient;
};

class CExecutionRetry
{
private:
   int m_max_retries;
   int m_retry_delay_ms;
   bool m_log_attempts;
   
   SRetryAttempt m_last_attempts[];
   int m_attempt_count;
   
   bool IsTransientError(uint retcode);
   bool IsPermanentError(uint retcode);
   string GetRetcodeDescription(uint retcode);

public:
   CExecutionRetry();
   ~CExecutionRetry();
   
   void Configure(int max_retries, int retry_delay_ms, bool log_attempts);
   
   ENUM_RETRY_RESULT SubmitWithRetry(CTrade &trade, 
                                      ENUM_ORDER_TYPE order_type,
                                      double volume,
                                      string symbol,
                                      double sl,
                                      double tp,
                                      string comment,
                                      double &execution_price);
   
   SRetryAttempt GetLastAttempt(int index);
   int GetAttemptCount();
};

CExecutionRetry::CExecutionRetry()
{
   m_max_retries = 3;
   m_retry_delay_ms = 250;
   m_log_attempts = true;
   m_attempt_count = 0;
}

CExecutionRetry::~CExecutionRetry()
{
}

void CExecutionRetry::Configure(int max_retries, int retry_delay_ms, bool log_attempts)
{
   m_max_retries = MathMax(1, max_retries);
   m_retry_delay_ms = MathMax(100, retry_delay_ms);
   m_log_attempts = log_attempts;
}

bool CExecutionRetry::IsTransientError(uint retcode)
{
   // Transient errors that warrant retry
   return (retcode == TRADE_RETCODE_REQUOTE ||
           retcode == TRADE_RETCODE_PRICE_CHANGED ||
           retcode == TRADE_RETCODE_TIMEOUT ||
           retcode == TRADE_RETCODE_CONNECTION ||
           retcode == TRADE_RETCODE_LOCKED);
}

bool CExecutionRetry::IsPermanentError(uint retcode)
{
   // Permanent errors - no retry
   return (retcode == TRADE_RETCODE_INVALID_VOLUME ||
           retcode == TRADE_RETCODE_INVALID_PRICE ||
           retcode == TRADE_RETCODE_NO_MONEY ||
           retcode == TRADE_RETCODE_MARKET_CLOSED ||
           retcode == TRADE_RETCODE_INVALID_EXPIRATION ||
           retcode == TRADE_RETCODE_INVALID_COMMENT ||
           retcode == TRADE_RETCODE_TRADE_DISABLED ||
           retcode == TRADE_RETCODE_INSUFFICIENT_RIGHTS);
}

string CExecutionRetry::GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:           return "REQUOTE (market moved)";
      case TRADE_RETCODE_REJECT:            return "REJECT";
      case TRADE_RETCODE_CANCEL:            return "CANCEL";
      case TRADE_RETCODE_PLACED:            return "PLACED";
      case TRADE_RETCODE_DONE:              return "DONE";
      case TRADE_RETCODE_DONE_PARTIAL:      return "DONE_PARTIAL";
      case TRADE_RETCODE_ERROR:             return "ERROR (generic)";
      case TRADE_RETCODE_TIMEOUT:           return "TIMEOUT (network delay)";
      case TRADE_RETCODE_INVALID_VOLUME:    return "INVALID_VOLUME (permanent)";
      case TRADE_RETCODE_INVALID_PRICE:     return "INVALID_PRICE (permanent)";
      case TRADE_RETCODE_INVALID_STOPS:     return "INVALID_STOPS";
      case TRADE_RETCODE_TRADE_DISABLED:    return "TRADE_DISABLED (permanent)";
      case TRADE_RETCODE_MARKET_CLOSED:     return "MARKET_CLOSED (permanent)";
      case TRADE_RETCODE_NO_MONEY:          return "NO_MONEY (permanent)";
      case TRADE_RETCODE_PRICE_CHANGED:     return "PRICE_CHANGED (transient)";
      case TRADE_RETCODE_PRICE_OFF:         return "PRICE_OFF";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "INVALID_EXPIRATION";
      case TRADE_RETCODE_ORDER_CHANGED:     return "ORDER_CHANGED";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "TOO_MANY_REQUESTS";
      case TRADE_RETCODE_NO_CHANGES:        return "NO_CHANGES";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "SERVER_DISABLES_AT";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "CLIENT_DISABLES_AT";
      case TRADE_RETCODE_LOCKED:            return "LOCKED (transient)";
      case TRADE_RETCODE_FROZEN:            return "FROZEN";
      case TRADE_RETCODE_INVALID_FILLING:   return "INVALID_FILLING";
      case TRADE_RETCODE_CONNECTION:        return "CONNECTION (transient)";
      case TRADE_RETCODE_ONLY_CLOSES:       return "ONLY_CLOSES";
      case TRADE_RETCODE_LIMIT_ORDERS:      return "LIMIT_ORDERS";
      case TRADE_RETCODE_LIMIT_VOLUME:      return "LIMIT_VOLUME";
      case TRADE_RETCODE_INVALID_ORDER:     return "INVALID_ORDER";
      case TRADE_RETCODE_POSITION_CLOSED:   return "POSITION_CLOSED";
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME: return "INVALID_CLOSE_VOLUME";
      case TRADE_RETCODE_CLOSE_ORDER_EXIST: return "CLOSE_ORDER_EXIST";
      case TRADE_RETCODE_LIMIT_CLIENTS_ORDERS: return "LIMIT_CLIENTS_ORDERS";
      case TRADE_RETCODE_HARD_STOP:         return "HARD_STOP";
      case TRADE_RETCODE_INVALID_DEEPENING: return "INVALID_DEEPENING";
      case TRADE_RETCODE_INVALID_COMMENT:   return "INVALID_COMMENT";
      case TRADE_RETCODE_NOT_ENOUGH_MONEY_FOR_MODIFIED: return "NOT_ENOUGH_MONEY_FOR_MODIFIED";
      default:                              return "UNKNOWN (" + (string)retcode + ")";
   }
}

ENUM_RETRY_RESULT CExecutionRetry::SubmitWithRetry(CTrade &trade,
                                                    ENUM_ORDER_TYPE order_type,
                                                    double volume,
                                                    string symbol,
                                                    double sl,
                                                    double tp,
                                                    string comment,
                                                    double &execution_price)
{
   m_attempt_count = 0;
   ArrayResize(m_last_attempts, 0);
   
   for(int attempt = 1; attempt <= m_max_retries; attempt++)
   {
      SRetryAttempt attempt_log;
      ZeroMemory(attempt_log);
      attempt_log.attempt_number = attempt;
      attempt_log.attempt_time = TimeCurrent();
      
      // Submit order
      bool submit_result = false;
      if(order_type == ORDER_TYPE_BUY)
         submit_result = trade.Buy(volume, symbol, 0, sl, tp, comment);
      else if(order_type == ORDER_TYPE_SELL)
         submit_result = trade.Sell(volume, symbol, 0, sl, tp, comment);
      
      uint retcode = trade.ResultRetcode();
      attempt_log.retcode = retcode;
      attempt_log.retcode_description = GetRetcodeDescription(retcode);
      attempt_log.is_transient = IsTransientError(retcode);
      
      // Log attempt
      if(m_log_attempts)
      {
         Print("Execution Retry Attempt ", attempt, "/", m_max_retries,
               " | RetCode: ", (int)retcode, " (", attempt_log.retcode_description, ")");
      }
      
      ArrayResize(m_last_attempts, m_attempt_count + 1);
      m_last_attempts[m_attempt_count] = attempt_log;
      m_attempt_count++;
      
      // Check for success
      if(submit_result || retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         if(m_log_attempts)
            Print("Execution SUCCESS on attempt ", attempt);
         return RETRY_SUCCESS;
      }
      
      // Check for permanent failure
      if(IsPermanentError(retcode))
      {
         if(m_log_attempts)
            Print("Permanent execution error - aborting retries");
         return RETRY_PERMANENT_FAILURE;
      }
      
      // For transient errors, retry after delay
      if(IsTransientError(retcode) && attempt < m_max_retries)
      {
         if(m_log_attempts)
            Print("Transient error detected - retrying after ", m_retry_delay_ms, "ms");
         Sleep(m_retry_delay_ms);
      }
   }
   
   // All retries exhausted
   if(m_log_attempts)
      Print("Execution failed after ", m_max_retries, " attempts");
   
   return RETRY_MAX_ATTEMPTS_EXCEEDED;
}

SRetryAttempt CExecutionRetry::GetLastAttempt(int index)
{
   SRetryAttempt empty;
   ZeroMemory(empty);
   
   if(index < 0 || index >= m_attempt_count)
      return empty;
   
   return m_last_attempts[index];
}

int CExecutionRetry::GetAttemptCount()
{
   return m_attempt_count;
}

#endif
