/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * iwchaos — thin C ABI for chaos hooks into the Rust staticlib.
 * Legacy pure-Rust driver shims were removed; vendored iwlwifi owns PCI/mac80211.
 */

#ifndef IWCHAOS_SHIM_H
#define IWCHAOS_SHIM_H

#include <linux/types.h>

struct iwchaos_lorenz_state { double x, y, z; };
struct iwchaos_rossler_state { double x, y, z; };
struct iwchaos_lyapunov_state {
	struct iwchaos_lorenz_state traj;
	double dx, dy, dz;
	double sum;
	u64 steps;
};
struct iwchaos_duffing_state { double x, y, t; };
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

void iwchaos_update_all(struct iwchaos_lorenz_state *lorenz,
			struct iwchaos_rossler_state *rossler,
			struct iwchaos_lyapunov_state *lyapunov,
			struct iwchaos_duffing_state *duffing,
			struct iwchaos_logistic_state *logistic,
			double snr_real, double snr_imag,
			struct iwchaos_chaos_params *out);

#endif /* IWCHAOS_SHIM_H */
