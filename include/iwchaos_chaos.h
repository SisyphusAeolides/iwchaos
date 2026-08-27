/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IWCHAOS_CHAOS_H
#define IWCHAOS_CHAOS_H

#include <linux/types.h>

#define IWCHAOS_STA_MAX 32

void iwchaos_chaos_tick(u8 sta_id);
u8 iwchaos_chaos_rate_select(u8 sta_id, u8 index, int low, int high);
void iwchaos_chaos_tx_feedback(u8 sta_id, int success, int snr_db);

#endif /* IWCHAOS_CHAOS_H */
