// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — global chaos hooks (MVM rs/tx path → Rust)
 */

#include "iwchaos_chaos.h"

extern void iwchaos_chaos_tick_rust(void);
extern u8 iwchaos_chaos_rate_bias_rust(u8 index, u8 low, u8 high);
extern void iwchaos_chaos_tx_feedback_rust(int success, int snr_db);

void iwchaos_chaos_tick(void)
{
	iwchaos_chaos_tick_rust();
}

u8 iwchaos_chaos_rate_bias(u8 index, u8 low, u8 high)
{
	return iwchaos_chaos_rate_bias_rust(index, low, high);
}

void iwchaos_chaos_tx_feedback(int success, int snr_db)
{
	iwchaos_chaos_tx_feedback_rust(success, snr_db);
}
