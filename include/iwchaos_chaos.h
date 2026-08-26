/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IWCHAOS_CHAOS_H
#define IWCHAOS_CHAOS_H

#include <linux/types.h>

/* Global chaos hooks called from vendored MVM (rs.c / tx.c). */
void iwchaos_chaos_tick(void);
u8 iwchaos_chaos_rate_bias(u8 index, u8 low, u8 high);
void iwchaos_chaos_tx_feedback(int success, int snr_db);

#endif /* IWCHAOS_CHAOS_H */
