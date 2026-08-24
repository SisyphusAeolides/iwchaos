/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * iwchaos — C shim: mac80211 / cfg80211 ABI bridge
 *
 * This is the minimalist C translation layer between the mac80211/cfg80211
 * kernel structures and the Rust RFL core. It exists solely because these
 * subsystems pre-date the Rust kernel bindings and expose C-only APIs.
 */

#ifndef IWCHAOS_SHIM_H
#define IWCHAOS_SHIM_H

#include <linux/types.h>

/* ── Opaque handle types ────────────────────────────────────────────────── */

struct iwchaos_dev;   /* defined in Rust, passed as opaque pointer */

/* Lorenz integrator state (mirrors LorenzState in Rust lib.rs) */
struct iwchaos_lorenz_state {
    double x;
    double y;
    double z;
};

/* ── Rust core exports (called from C) ─────────────────────────────────── */

u64  iwchaos_lorenz_backoff(struct iwchaos_lorenz_state *state);
u32  iwchaos_mandelbrot_power_state(double snr_real, double snr_imag);

/* ── mac80211 shim ops (implemented in c/shim_mac80211.c) ─────────────── */

int  iwchaos_mac_start(struct iwchaos_dev *dev);
void iwchaos_mac_stop(struct iwchaos_dev *dev);
int  iwchaos_mac_tx(struct iwchaos_dev *dev, void *skb);

/* ── cfg80211 shim ops (implemented in c/shim_cfg80211.c) ─────────────── */

int  iwchaos_cfg_scan(struct iwchaos_dev *dev);
int  iwchaos_cfg_connect(struct iwchaos_dev *dev, const u8 *bssid, u32 freq);
void iwchaos_cfg_disconnect(struct iwchaos_dev *dev);

/* ── PCIe shim (implemented in c/shim_pci.c) ───────────────────────────── */

int  iwchaos_pci_probe(struct pci_dev *pdev, const struct pci_device_id *id);
void iwchaos_pci_remove(struct pci_dev *pdev);

#endif /* IWCHAOS_SHIM_H */
