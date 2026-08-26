// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — rate control ABI stub (logic in Rust)
 */

#include "iwchaos_shim.h"

u8 iwchaos_rate_select(void *rust_ctx, u8 n_rates, const u8 *rate_table_mcs)
{
	return iwchaos_rate_select_rust(rust_ctx, n_rates, rate_table_mcs);
}

void iwchaos_rate_feedback(void *rust_ctx, int tx_success, int snr_db)
{
	iwchaos_rate_feedback_rust(rust_ctx, tx_success, snr_db);
}
