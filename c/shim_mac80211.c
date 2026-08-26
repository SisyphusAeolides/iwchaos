// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — mac80211 ABI shim (delegates all logic to Rust)
 */

#include <linux/kernel.h>
#include <linux/skbuff.h>
#include <linux/ieee80211.h>
#include <net/mac80211.h>
#include "iwchaos_shim.h"

static void *iwchaos_priv(struct ieee80211_hw *hw)
{
	void **p = hw->priv;

	return (p && *p) ? *p : NULL;
}

void iwchaos_dev_kfree_skb_any(struct sk_buff *skb)
{
	dev_kfree_skb_any(skb);
}

static void iwchaos_mac_tx(struct ieee80211_hw *hw,
			   struct ieee80211_tx_control *control,
			   struct sk_buff *skb)
{
	void *ctx = iwchaos_priv(hw);

	(void)control;
	if (ctx)
		iwchaos_mac_tx_rust(ctx, skb);
	else
		dev_kfree_skb_any(skb);
}

static int iwchaos_mac_start(struct ieee80211_hw *hw)
{
	void *ctx = iwchaos_priv(hw);

	return ctx ? iwchaos_mac_start_rust(ctx) : -EINVAL;
}

static void iwchaos_mac_stop(struct ieee80211_hw *hw, bool suspend)
{
	void *ctx = iwchaos_priv(hw);

	if (ctx)
		iwchaos_mac_stop_rust(ctx, suspend);
}

static int iwchaos_mac_add_interface(struct ieee80211_hw *hw,
				     struct ieee80211_vif *vif)
{
	(void)hw;
	(void)vif;
	return 0;
}

static void iwchaos_mac_remove_interface(struct ieee80211_hw *hw,
					 struct ieee80211_vif *vif)
{
	(void)hw;
	(void)vif;
}

static int iwchaos_mac_config(struct ieee80211_hw *hw, int radio_idx, u32 changed)
{
	void *ctx = iwchaos_priv(hw);

	(void)radio_idx;
	(void)changed;
	if (!ctx)
		return -EINVAL;

	iwchaos_mac_rx_rust(ctx);
	return 0;
}

static int iwchaos_mac_hw_scan(struct ieee80211_hw *hw,
			       struct ieee80211_vif *vif,
			       struct ieee80211_scan_request *req)
{
	void *ctx = iwchaos_priv(hw);
	bool prefer_5ghz = false;
	int ret;

	(void)vif;
	if (!ctx || !req)
		return -EINVAL;

	if (req->req.n_channels > 0) {
		u32 freq = req->req.channels[0]->center_freq;

		prefer_5ghz = freq >= 5000;
	}

	ret = iwchaos_hw_scan_rust(ctx, prefer_5ghz);
	if (ret)
		return ret;

	iwchaos_scan_complete_rust(ctx);
	return 0;
}

static void iwchaos_mac_cancel_hw_scan(struct ieee80211_hw *hw,
				       struct ieee80211_vif *vif)
{
	void *ctx = iwchaos_priv(hw);

	(void)vif;
	if (ctx)
		iwchaos_scan_complete_rust(ctx);
}

static void iwchaos_mac_bss_info_changed(struct ieee80211_hw *hw,
					 struct ieee80211_vif *vif,
					 struct ieee80211_bss_conf *info,
					 u64 changed)
{
	void *ctx = iwchaos_priv(hw);

	(void)vif;
	(void)info;
	if (!ctx)
		return;

	if (changed & BSS_CHANGED_ASSOC) {
		if (vif->cfg.assoc)
			iwchaos_connect_rust(ctx);
		else
			iwchaos_disconnect_rust(ctx);
	}
}

static const struct ieee80211_ops iwchaos_mac_ops = {
	.tx                  = iwchaos_mac_tx,
	.start               = iwchaos_mac_start,
	.stop                = iwchaos_mac_stop,
	.add_interface       = iwchaos_mac_add_interface,
	.remove_interface    = iwchaos_mac_remove_interface,
	.config              = iwchaos_mac_config,
	.hw_scan             = iwchaos_mac_hw_scan,
	.cancel_hw_scan      = iwchaos_mac_cancel_hw_scan,
	.bss_info_changed    = iwchaos_mac_bss_info_changed,
};

struct ieee80211_hw *iwchaos_mac80211_alloc(struct device *dev)
{
	struct ieee80211_hw *hw;
	struct ieee80211_supported_band bands[] = {
		{
			.band = NL80211_BAND_2GHZ,
			.n_channels = 1,
		},
	};

	hw = ieee80211_alloc_hw(sizeof(void *), &iwchaos_mac_ops);
	if (!hw)
		return NULL;

	SET_IEEE80211_DEV(hw, dev);
	strscpy(hw->wiphy->fw_version, "iwchaos 2.0-chaos",
		sizeof(hw->wiphy->fw_version));

	hw->wiphy->max_scan_ie_len = 2048;
	hw->wiphy->interface_modes = BIT(NL80211_IFTYPE_STATION);
	hw->queues = 4;
	hw->extra_tx_headroom = 24;

	(void)bands;

	return hw;
}

int iwchaos_mac80211_register(void *rust_ctx, struct ieee80211_hw *hw)
{
	void **priv = hw->priv;

	*priv = rust_ctx;
	return ieee80211_register_hw(hw);
}

void iwchaos_mac80211_unregister(struct ieee80211_hw *hw)
{
	ieee80211_unregister_hw(hw);
	ieee80211_free_hw(hw);
}
