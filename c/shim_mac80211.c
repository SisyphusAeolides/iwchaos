// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — mac80211 ABI shim
 *
 * Bridges the kernel mac80211 subsystem to the Rust RFL core.
 * Contains no driver logic. All decision-making lives in Rust.
 */

#include <linux/kernel.h>
#include <linux/skbuff.h>
#include <linux/ieee80211.h>
#include <net/mac80211.h>
#include "iwchaos_shim.h"

void iwchaos_dev_kfree_skb_any(struct sk_buff *skb)
{
    dev_kfree_skb_any(skb);
}

/*
 * mac80211 op: transmit an 802.11 frame.
 * hw->priv holds the struct iwchaos_dev pointer set at alloc_hw() time.
 */
void iwchaos_mac_tx(struct ieee80211_hw *hw,
                    struct ieee80211_tx_control *control,
                    struct sk_buff *skb)
{
    void **priv = hw->priv;
    if (priv && *priv) {
        iwchaos_mac_tx_rust(*priv, skb);
    } else {
        dev_kfree_skb_any(skb);
    }
}

/*
 * mac80211 op: bring the device up.
 * Returns 0 on success, negative errno on failure.
 */
int iwchaos_mac_start(struct ieee80211_hw *hw)
{
    return 0;
}

/*
 * mac80211 op: take the device down.
 * suspend is true when called for system sleep.
 */
void iwchaos_mac_stop(struct ieee80211_hw *hw, bool suspend)
{
    (void)suspend;
}

static const struct ieee80211_ops iwchaos_mac_ops = {
    .tx    = iwchaos_mac_tx,
    .start = iwchaos_mac_start,
    .stop  = iwchaos_mac_stop,
};

const struct ieee80211_ops *iwchaos_get_mac80211_ops(void)
{
    return &iwchaos_mac_ops;
}

struct ieee80211_hw *iwchaos_mac80211_alloc(struct device *dev)
{
    struct ieee80211_hw *hw;

    /* We allocate space in hw->priv to hold the void* to our Rust struct */
    hw = ieee80211_alloc_hw(sizeof(void *), &iwchaos_mac_ops);
    if (!hw)
        return NULL;

    strscpy(hw->wiphy->fw_version, "iwchaos 1.0.0-chaos",
            sizeof(hw->wiphy->fw_version));

    hw->wiphy->max_scan_ie_len = 2048;

    /* Expose minimal capabilities for now */
    hw->wiphy->interface_modes = BIT(NL80211_IFTYPE_STATION) |
                                 BIT(NL80211_IFTYPE_AP);
    hw->queues = 4;

    return hw;
}

int iwchaos_mac80211_register(void *rust_ctx, struct ieee80211_hw *hw)
{
    void **priv = hw->priv;
    *priv = rust_ctx; /* Save the Rust context */

    return ieee80211_register_hw(hw);
}

void iwchaos_mac80211_unregister(struct ieee80211_hw *hw)
{
    ieee80211_unregister_hw(hw);
    ieee80211_free_hw(hw);
}
