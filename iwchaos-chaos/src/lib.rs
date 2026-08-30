// SPDX-License-Identifier: GPL-2.0-or-later
//! Chaos-theory link dynamics for iwchaos (userspace simulation / tests).

pub use chaos_math::{
    duffing_snr_delta_cd, logistic_jitter_us, lorenz_backoff_us, lyapunov_adaptive_dt,
    lyapunov_est, lyapunov_step, mandelbrot_power, rossler_channels, ChaosParams, DuffingState,
    LogisticState, LorenzState, LyapunovState, RosslerState,
};

#[derive(Debug, Clone)]
pub struct ChaosEngine {
    pub lorenz: LorenzState,
    pub rossler: RosslerState,
    pub lyapunov: LyapunovState,
    pub duffing: DuffingState,
    pub logistic: LogisticState,
    pub params: ChaosParams,
    pub snr_real: f64,
    pub snr_imag: f64,
}

impl Default for ChaosEngine {
    fn default() -> Self {
        Self {
            lorenz: LorenzState {
                x: 0.1,
                y: 0.1,
                z: 0.1,
            },
            rossler: RosslerState {
                x: 0.1,
                y: 0.0,
                z: 0.0,
            },
            lyapunov: LyapunovState::default(),
            duffing: DuffingState {
                x: 1.0,
                y: 0.0,
                t: 0.0,
            },
            logistic: LogisticState::default(),
            params: ChaosParams {
                backoff_us: 10,
                power_state: 2,
                ..Default::default()
            },
            snr_real: 0.0,
            snr_imag: 0.0,
        }
    }
}

impl ChaosEngine {
    pub fn tick(&mut self) {
        let log_growth = lyapunov_step(&mut self.lyapunov, 10.0, 28.0, 8.0 / 3.0, 0.01);
        self.lyapunov.sum += log_growth;
        self.lyapunov.steps += 1;
        self.params.lyapunov_est = lyapunov_est(&self.lyapunov);
        self.params.adaptive_dt = lyapunov_adaptive_dt(self.params.lyapunov_est);
        self.params.backoff_us = lorenz_backoff_us(&mut self.lorenz);
        self.params.power_state = mandelbrot_power(self.snr_real, self.snr_imag);
        self.params.snr_delta_centidecibels = duffing_snr_delta_cd(&mut self.duffing);
        let (ch24, ch5, pwr) = rossler_channels(&mut self.rossler);
        self.params.channel_24ghz = ch24;
        self.params.channel_5ghz = ch5;
        self.params.tx_power_mw = pwr;
        self.params.jitter_us = logistic_jitter_us(&mut self.logistic, 100);
    }

    pub fn rate_select(&mut self, hint: u8, low: u8, high: u8) -> u8 {
        self.tick();
        if low > high {
            return hint;
        }
        let cp = &self.params;
        let span = (high - low) as u32 + 1;
        if span == 0 {
            return hint;
        }

        let mut rel = (cp.power_state as u32 * (span - 1) / 4) as i32;
        let snr = cp.snr_delta_centidecibels;
        rel += if snr >= 0 {
            (snr + 100) / 200
        } else {
            -(((-snr) + 100) / 200)
        };

        if cp.lyapunov_est < 1.2 && cp.jitter_us > 0 {
            if cp.jitter_us < 34 {
                rel -= 1;
            } else if cp.jitter_us > 66 {
                rel += 1;
            }
        }

        rel = rel.clamp(0, span as i32 - 1);
        let chaos_idx = low.saturating_add(rel as u8);
        if (low..=high).contains(&hint) {
            ((chaos_idx as u16 * 3 + hint as u16) / 4) as u8
        } else {
            chaos_idx
        }
    }

    pub fn feedback(&mut self, tx_success: i32, snr_db: i32) {
        self.snr_real = (snr_db as f64) / 40.0;
        self.snr_imag = if tx_success != 0 { 0.0 } else { 0.5 };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tick_produces_finite_params() {
        let mut e = ChaosEngine::default();
        e.tick();
        assert!(e.params.backoff_us >= 10);
        assert!(e.params.lyapunov_est.is_finite());
    }

    #[test]
    fn rate_select_stays_in_bounds() {
        let mut e = ChaosEngine::default();
        let idx = e.rate_select(5, 2, 8);
        assert!((2..=8).contains(&idx));
    }

    #[test]
    fn invalid_rate_bounds_preserve_hint() {
        let mut e = ChaosEngine::default();
        assert_eq!(e.rate_select(7, 8, 2), 7);
    }
}
