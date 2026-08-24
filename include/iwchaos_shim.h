/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * iwchaos — C shim: mac80211 / cfg80211 / PCIe ABI bridge
 *
 * This is the minimalist C translation layer between the mac80211/cfg80211
 * kernel structures and the Rust RFL core. It exists solely because these
 * subsystems pre-date the Rust kernel bindings and expose C-only APIs.
 *
 * Chaos engine overview (called from C shims via FFI-exported symbols):
 *
 *   iwchaos_lorenz_backoff()      — MAC CSMA/CA backoff delay [10, 1000] µs
 *   iwchaos_mandelbrot_power_state() — Coarse TX power state [0, 4]
 *   iwchaos_duffing_snr_delta()   — Fine SNR delta [−600, +600] centidB
 *   iwchaos_rossler_channels()    — Channel selection (2.4 / 5 GHz) + power
 *   iwchaos_logistic_jitter()     — Per-packet jitter [1, 100] µs
 *   iwchaos_lyapunov_tick()       — Adaptive integration dt
 *   iwchaos_update_all()          — Advance all six systems in one call
 */

#ifndef IWCHAOS_SHIM_H
#define IWCHAOS_SHIM_H

#include <linux/types.h>
#include <linux/pci.h>
#include <net/mac80211.h>
#include <net/cfg80211.h>

/* ── Opaque handle types ────────────────────────────────────────────────── */

struct iwchaos_dev;   /* defined in Rust, passed as opaque pointer */

/* ── Chaos engine attractor state types (mirror Rust repr(C) structs) ───── */

/* Lorenz RK4 integrator state */
struct iwchaos_lorenz_state {
    double x;
    double y;
    double z;
};

/* Rössler RK4 integrator state */
struct iwchaos_rossler_state {
    double x;
    double y;
    double z;
};

/* Lyapunov estimator state (co-integrates perturbation vector) */
struct iwchaos_lyapunov_state {
    struct iwchaos_lorenz_state traj;
    double dx, dy, dz;  /* perturbation vector */
    double sum;         /* log-growth accumulator */
    u64    steps;       /* number of accumulated steps */
};

/* Duffing oscillator state */
struct iwchaos_duffing_state {
    double x;   /* position → SNR delta */
    double y;   /* velocity → SNR rate of change */
    double t;   /* continuous time for periodic forcing */
};

/* Logistic map state */
struct iwchaos_logistic_state {
    double x;   /* current orbit value ∈ (0, 1) */
    double r;   /* growth rate (4.0 = full chaos) */
};

/* Unified chaos parameter snapshot — output of iwchaos_update_all() */
struct iwchaos_chaos_params {
    u64    backoff_us;                /* Lorenz MAC backoff [10, 1000] µs */
    u32    power_state;               /* Mandelbrot coarse power [0, 4] */
    s32    snr_delta_centidecibels;   /* Duffing SNR delta [−600, +600] */
    u32    channel_24ghz;             /* Rössler 2.4 GHz channel [1, 14] */
    u32    channel_5ghz;              /* Rössler 5 GHz channel (idx*4+36) */
    u32    tx_power_mw;               /* Rössler TX power [0, 100] mW */
    u32    jitter_us;                 /* Logistic per-packet jitter [1, 100] µs */
    double adaptive_dt;               /* Lyapunov adaptive integration timestep */
    double lyapunov_est;              /* Current Lyapunov exponent estimate */
};

/* ── Rust core chaos engine exports ─────────────────────────────────────── */

/* Primary interface: advance all six chaos systems, return snapshot */
void iwchaos_update_all(
    struct iwchaos_lorenz_state   *lorenz,
    struct iwchaos_rossler_state  *rossler,
    struct iwchaos_lyapunov_state *lyapunov,
    struct iwchaos_duffing_state  *duffing,
    struct iwchaos_logistic_state *logistic,
    double snr_real,
    double snr_imag,
    struct iwchaos_chaos_params   *out
);

/* ── Rust core exports (called from C) ─────────────────────────────────── */

u64  iwchaos_lorenz_backoff(struct iwchaos_lorenz_state *state);
u32  iwchaos_mandelbrot_power_state(double snr_real, double snr_imag);
void iwchaos_rossler_channels(struct iwchaos_rossler_state *state,
                              u32 *ch24_out, u32 *ch5_out, u32 *pwr_mw_out);
u32  iwchaos_logistic_jitter(struct iwchaos_logistic_state *state);
double iwchaos_lyapunov_tick(struct iwchaos_lyapunov_state *state);
double iwchaos_lyapunov_estimate(const struct iwchaos_lyapunov_state *state);
s32  iwchaos_duffing_snr_delta(struct iwchaos_duffing_state *state);

/* Lifecycle callbacks from C to Rust */
void *iwchaos_core_alloc(struct ieee80211_hw *hw, void __iomem *mmio_base);
void  iwchaos_core_free(void *rust_ctx);
void  iwchaos_mac_tx_rust(void *rust_ctx, struct sk_buff *skb);
void  iwchaos_led_set_rust(void *rust_ctx, unsigned int brightness);

/* C to C helpers for Rust */
void iwchaos_dev_kfree_skb_any(struct sk_buff *skb);

/* ── mac80211 shim (implemented in c/shim_mac80211.c) ─────────────────── */

int  iwchaos_mac80211_register(void *rust_ctx, struct ieee80211_hw *hw);
void iwchaos_mac80211_unregister(struct ieee80211_hw *hw);
const struct ieee80211_ops *iwchaos_get_mac80211_ops(void);
struct ieee80211_hw *iwchaos_mac80211_alloc(struct device *dev);

/* mac80211 op callbacks — correct kernel signatures */
void iwchaos_mac_tx(struct ieee80211_hw *hw,
                    struct ieee80211_tx_control *control,
                    struct sk_buff *skb);
int  iwchaos_mac_start(struct ieee80211_hw *hw);
void iwchaos_mac_stop(struct ieee80211_hw *hw, bool suspend);

/* ── cfg80211 shim (implemented in c/shim_cfg80211.c) ─────────────────── */

struct cfg80211_ops *iwchaos_get_cfg80211_ops(void);

/* cfg80211 op callbacks — correct kernel signatures */
int  iwchaos_cfg_scan(struct wiphy *wiphy,
                      struct cfg80211_scan_request *request);
int  iwchaos_cfg_connect(struct wiphy *wiphy, struct net_device *dev,
                         struct cfg80211_connect_params *sme);
int  iwchaos_cfg_disconnect(struct wiphy *wiphy, struct net_device *dev,
                            u16 reason_code);

/* ── PCIe shim (implemented in c/shim_pci.c) ───────────────────────────── */

int  iwchaos_pci_register(void);
void iwchaos_pci_unregister(void);
// Probe and remove are now implemented purely in C.

/* ── Rate control shim (implemented in c/shim_rate_control.c) ──────────── */

/* Chaos-informed rate adaptation — called by the TX path */
u8   iwchaos_rate_select(const struct iwchaos_chaos_params *cp,
                         u8 n_rates, const u8 *rate_table_mcs);
void iwchaos_rate_feedback(int tx_success, int snr_db);

/* ── Channel selection shim (implemented in c/shim_channel.c) ──────────── */

int  iwchaos_channel_select(struct wiphy *wiphy,
                             const struct iwchaos_chaos_params *cp,
                             bool prefer_5ghz);

#endif /* IWCHAOS_SHIM_H */
