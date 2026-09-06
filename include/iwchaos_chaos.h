/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IWCHAOS_CHAOS_H
#define IWCHAOS_CHAOS_H

#include <linux/types.h>

/*
 * The normal Intel rate scaler remains authoritative. This optional policy
 * can only return a value inside the range supplied by that scaler.
 */
u8 iwchaos_chaos_rate_select(u8 sta_id, u8 index, int low, int high);
void iwchaos_chaos_tx_feedback(u8 sta_id, int success, int snr_db);
void iwchaos_chaos_sta_release(u8 sta_id);

#endif /* IWCHAOS_CHAOS_H */
