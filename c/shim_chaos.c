// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — per-sta chaos hooks for vendored MVM (rs/tx) → Rust staticlib.
 */

#include <linux/kernel.h>
#include <asm/fpu/api.h>
#include "iwchaos_chaos.h"

extern void iwchaos_chaos_tick_rust(u8 sta_id);
extern u8 iwchaos_chaos_rate_select_rust(u8 sta_id, u8 index, int low, int high);
extern void iwchaos_chaos_tx_feedback_rust(u8 sta_id, int success, int snr_db);

void iwchaos_chaos_tick(u8 sta_id)
{
	kernel_fpu_begin();
	iwchaos_chaos_tick_rust(sta_id);
	kernel_fpu_end();
}

u8 iwchaos_chaos_rate_select(u8 sta_id, u8 index, int low, int high)
{
	u8 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_rate_select_rust(sta_id, index, low, high);
	kernel_fpu_end();
	return out;
}

void iwchaos_chaos_tx_feedback(u8 sta_id, int success, int snr_db)
{
	kernel_fpu_begin();
	iwchaos_chaos_tx_feedback_rust(sta_id, success, snr_db);
	kernel_fpu_end();
}
