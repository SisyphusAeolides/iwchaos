/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * iwchaos — C ABI header (thin shims → Rust core)
 *
 * All chaos math and driver policy live in iwchaos_rust.rs. This header
 * declares only the cross-language boundary.
 */

#ifndef IWCHAOS_SHIM_H
#define IWCHAOS_SHIM_H

#include <linux/types.h>
#include <linux/pci.h>
#include <net/mac80211.h>
#include <net/cfg80211.h>

/* repr(C) chaos types — mirrors Rust (for any legacy callers) */
struct iwchaos_lorenz_state { double x, y, z; };
struct iwchaos_rossler_state { double x, y, z; };
struct iwchaos_lyapunov_state {
	struct iwchaos_lorenz_state traj;
	double dx, dy, dz;
	double sum;
	u64 steps;
};
struct iwchaos_duffing_state { double x, y, z; };
struct iwchaos_logistic_state { double x, r; };
struct iwchaos_chaos_params {
	u64 backoff_us;
	u32 power_state;
	s32 snr_delta_centidecibels;
	u32 channel_24ghz;
	u32 channel_5ghz;
	u32 tx_power_mw;
	u32 jitter_us;
	double adaptive_dt;
	double lyapunov_est;
};

/* ── Rust core ──────────────────────────────────────────────────────────── */

void *iwchaos_core_alloc(struct ieee80211_hw *hw, void __iomem *mmio,
			 struct device *dev);
void  iwchaos_core_free(void *rust_ctx);
int   iwchaos_core_load_firmware(void *rust_ctx, const u8 *fw, size_t len);

int   iwchaos_mac_start_rust(void *rust_ctx);
void  iwchaos_mac_stop_rust(void *rust_ctx, bool suspend);
void  iwchaos_mac_tx_rust(void *rust_ctx, struct sk_buff *skb);
void  iwchaos_mac_rx_rust(void *rust_ctx);
int   iwchaos_hw_scan_rust(void *rust_ctx, bool prefer_5ghz);
void  iwchaos_scan_complete_rust(void *rust_ctx);
int   iwchaos_connect_rust(void *rust_ctx);
void  iwchaos_disconnect_rust(void *rust_ctx);
u8    iwchaos_rate_select_rust(void *rust_ctx, u8 n_rates, const u8 *table);
void  iwchaos_rate_feedback_rust(void *rust_ctx, int tx_success, int snr_db);
int   iwchaos_channel_select_rust(void *rust_ctx, struct wiphy *wiphy,
				    bool prefer_5ghz);
void  iwchaos_led_set_rust(void *rust_ctx, unsigned int brightness);

void iwchaos_dev_kfree_skb_any(struct sk_buff *skb);

/* ── Thin C shims ───────────────────────────────────────────────────────── */

int  iwchaos_mac80211_register(void *rust_ctx, struct ieee80211_hw *hw);
void iwchaos_mac80211_unregister(struct ieee80211_hw *hw);
struct ieee80211_hw *iwchaos_mac80211_alloc(struct device *dev);

int  iwchaos_pci_register(void);
void iwchaos_pci_unregister(void);

u8   iwchaos_rate_select(void *rust_ctx, u8 n_rates, const u8 *rate_table);
void iwchaos_rate_feedback(void *rust_ctx, int tx_success, int snr_db);
int  iwchaos_channel_select(void *rust_ctx, struct wiphy *wiphy, bool prefer_5ghz);

#endif /* IWCHAOS_SHIM_H */
