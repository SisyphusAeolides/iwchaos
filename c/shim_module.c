// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — module entry (C required for module_init / MODULE_* macros).
 * All policy and chaos dynamics live in the freestanding Rust staticlib.
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>

extern int iwchaos_iwlwifi_init(void);
extern void iwchaos_iwlwifi_exit(void);
extern int iwchaos_mvm_init(void);
extern void iwchaos_mvm_exit(void);

static int __init iwchaos_init(void)
{
	int err;

	pr_info("iwchaos: chaos-enhanced Intel Wi-Fi stack loading\n");

	err = iwchaos_iwlwifi_init();
	if (err) {
		pr_err("iwchaos: PCI/transport init failed: %d\n", err);
		return err;
	}

	err = iwchaos_mvm_init();
	if (err) {
		pr_err("iwchaos: MVM init failed: %d\n", err);
		iwchaos_iwlwifi_exit();
		return err;
	}

	pr_info("iwchaos: ready (replaces iwlwifi/iwlmvm)\n");
	return 0;
}

static void __exit iwchaos_exit(void)
{
	iwchaos_mvm_exit();
	iwchaos_iwlwifi_exit();
	pr_info("iwchaos: unloaded\n");
}

module_init(iwchaos_init);
module_exit(iwchaos_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Kenny Glowner");
MODULE_DESCRIPTION("Chaos-driven Intel Wi-Fi driver (iwchaos)");
MODULE_VERSION("0.1.0");
MODULE_SOFTDEP("pre: cfg80211 mac80211");
MODULE_ALIAS("iwlwifi");
MODULE_ALIAS("iwlmvm");
