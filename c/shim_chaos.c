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
extern u16 iwchaos_chaos_scan_iter_count_rust(u8 ctx, u16 channel, u8 band_2ghz);
extern u16 iwchaos_chaos_scan_dwell_tu_rust(u8 ctx, u16 base);
extern u32 iwchaos_chaos_power_timeout_us_rust(u8 ctx, u32 base);
extern u16 iwchaos_chaos_coex_agg_limit_rust(u8 sta_id, u16 intel);
extern u32 iwchaos_chaos_quota_adjust_rust(u8 binding, u32 intel);

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

u16 iwchaos_chaos_scan_iter_count(u8 ctx, u16 channel, bool band_2ghz)
{
	u16 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_scan_iter_count_rust(ctx, channel, band_2ghz);
	kernel_fpu_end();
	return out;
}

u16 iwchaos_chaos_scan_dwell_tu(u8 ctx, u16 base_dwell_tu)
{
	u16 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_scan_dwell_tu_rust(ctx, base_dwell_tu);
	kernel_fpu_end();
	return out;
}

u32 iwchaos_chaos_power_timeout_us(u8 ctx, u32 base_timeout_us)
{
	u32 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_power_timeout_us_rust(ctx, base_timeout_us);
	kernel_fpu_end();
	return out;
}

u16 iwchaos_chaos_coex_agg_limit(u8 sta_id, u16 intel_limit)
{
	u16 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_coex_agg_limit_rust(sta_id, intel_limit);
	kernel_fpu_end();
	return out;
}

u32 iwchaos_chaos_quota_adjust(u8 binding, u32 intel_quota)
{
	u32 out;

	kernel_fpu_begin();
	out = iwchaos_chaos_quota_adjust_rust(binding, intel_quota);
	kernel_fpu_end();
	return out;
}
