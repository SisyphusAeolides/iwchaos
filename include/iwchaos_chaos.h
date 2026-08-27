/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IWCHAOS_CHAOS_H
#define IWCHAOS_CHAOS_H

#include <linux/types.h>

#define IWCHAOS_STA_MAX 32
#define IWCHAOS_CTX_GLOBAL 0

void iwchaos_chaos_tick(u8 sta_id);
u8 iwchaos_chaos_rate_select(u8 sta_id, u8 index, int low, int high);
void iwchaos_chaos_tx_feedback(u8 sta_id, int success, int snr_db);

/* Phase B: scan (Rössler), power (Lorenz), coex/quota (logistic) */
u16 iwchaos_chaos_scan_iter_count(u8 ctx, u16 channel, bool band_2ghz);
u16 iwchaos_chaos_scan_dwell_tu(u8 ctx, u16 base_dwell_tu);
u32 iwchaos_chaos_power_timeout_us(u8 ctx, u32 base_timeout_us);
u16 iwchaos_chaos_coex_agg_limit(u8 sta_id, u16 intel_limit);
u32 iwchaos_chaos_quota_adjust(u8 binding, u32 intel_quota);

/* Phase C: Lorenz thermal/agg, shared chaos-math crate */
u32 iwchaos_chaos_thermal_backoff_us(u8 ctx, u32 intel_backoff_us);
u16 iwchaos_chaos_agg_time_limit(u8 sta_id, u16 coex_limit);

/*
 * Per-station table uses sta_id % IWCHAOS_STA_MAX (32 slots). Collisions
 * share attractor state; use IWCHAOS_CTX_GLOBAL (0) for device-wide paths.
 */

#endif /* IWCHAOS_CHAOS_H */
