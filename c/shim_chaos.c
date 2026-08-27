// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — chaos hooks for vendored MVM (rs/tx) → Rust staticlib.
 * FPU is guarded: attractor math uses double in process/BH context.
 */

#include <linux/kernel.h>
#include <asm/fpu/api.h>
#include "iwchaos_chaos.h"

extern void iwchaos_chaos_tick_rust(void);
extern u8 iwchaos_chaos_rate_bias_rust(u8 index, u8 low, u8 high);
extern void iwchaos_chaos_tx_feedback_rust(int success, int snr_db);

void iwchaos_chaos_tick(void)
{
	kernel_fpu_begin();
	iwchaos_chaos_tick_rust();
	kernel_fpu_end();
}

u8 iwchaos_chaos_rate_bias(u8 index, u8 low, u8 high)
{
	u8 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_rate_bias_rust(index, low, high);
	kernel_fpu_end();
	return out;
}

void iwchaos_chaos_tx_feedback(int success, int snr_db)
{
	kernel_fpu_begin();
	iwchaos_chaos_tx_feedback_rust(success, snr_db);
	kernel_fpu_end();
}
