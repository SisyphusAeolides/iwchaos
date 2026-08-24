// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — mac80211 ABI shim
 *
 * Bridges the kernel mac80211 subsystem to the Rust RFL core.
 * Contains no driver logic. All decision-making lives in Rust.
 */

#include <linux/kernel.h>
#include <linux/ieee80211.h>
#include <net/mac80211.h>
#include "iwchaos_shim.h"

static struct ieee80211_ops iwchaos_mac_ops = {
    .tx           = (void *)iwchaos_mac_tx,
    .start        = (void *)iwchaos_mac_start,
    .stop         = (void *)iwchaos_mac_stop,
};

int iwchaos_mac80211_register(struct iwchaos_dev *dev,
                               struct ieee80211_hw *hw)
{
    hw->wiphy->interface_modes = BIT(NL80211_IFTYPE_STATION) |
                                 BIT(NL80211_IFTYPE_AP);
    hw->queues = 4;
    return ieee80211_register_hw(hw);
}

void iwchaos_mac80211_unregister(struct ieee80211_hw *hw)
{
    ieee80211_unregister_hw(hw);
}
