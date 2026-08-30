// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — bounded rate policy bridge for the target kernel's MVM module.
 */

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/spinlock.h>

#include "iwchaos_chaos.h"

extern u8 iwchaos_chaos_rate_select_rust(u8 sta_id, u8 index, int low, int high);
extern void iwchaos_chaos_tx_feedback_rust(u8 sta_id, int success, int snr_db);
extern void iwchaos_chaos_sta_release_rust(u8 sta_id);

static DEFINE_SPINLOCK(iwchaos_state_lock);
static bool iwchaos_enabled = true;

module_param_named(iwchaos, iwchaos_enabled, bool, 0644);
MODULE_PARM_DESC(iwchaos,
		 "enable the bounded iwchaos rate policy (default: true)");

u8 iwchaos_chaos_rate_select(u8 sta_id, u8 index, int low, int high)
{
	unsigned long flags;
	u8 out;

	if (!READ_ONCE(iwchaos_enabled))
		return index;

	spin_lock_irqsave(&iwchaos_state_lock, flags);
	out = iwchaos_chaos_rate_select_rust(sta_id, index, low, high);
	spin_unlock_irqrestore(&iwchaos_state_lock, flags);

	return out;
}
EXPORT_SYMBOL_GPL(iwchaos_chaos_rate_select);

void iwchaos_chaos_tx_feedback(u8 sta_id, int success, int snr_db)
{
	unsigned long flags;

	if (!READ_ONCE(iwchaos_enabled))
		return;

	spin_lock_irqsave(&iwchaos_state_lock, flags);
	iwchaos_chaos_tx_feedback_rust(sta_id, success, snr_db);
	spin_unlock_irqrestore(&iwchaos_state_lock, flags);
}
EXPORT_SYMBOL_GPL(iwchaos_chaos_tx_feedback);

void iwchaos_chaos_sta_release(u8 sta_id)
{
	unsigned long flags;

	spin_lock_irqsave(&iwchaos_state_lock, flags);
	iwchaos_chaos_sta_release_rust(sta_id);
	spin_unlock_irqrestore(&iwchaos_state_lock, flags);
}
EXPORT_SYMBOL_GPL(iwchaos_chaos_sta_release);

static int __init iwchaos_policy_init(void)
{
	return 0;
}

static void __exit iwchaos_policy_exit(void)
{
}

module_init(iwchaos_policy_init);
module_exit(iwchaos_policy_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded fixed-point iwchaos policy bridge");
