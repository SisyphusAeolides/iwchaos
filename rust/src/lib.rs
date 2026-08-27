// SPDX-License-Identifier: GPL-2.0-only
//! Per-station chaos rate control for iwchaos (freestanding staticlib).

#![no_std]
#![allow(clippy::missing_safety_doc)]

use chaos_math::{
    duffing_snr_delta_cd, logistic_jitter_us, lorenz_backoff_us, lyapunov_adaptive_dt,
    lyapunov_est, lyapunov_step, mandelbrot_power, rossler_channels, ChaosParams, DuffingState,
    LogisticState, LorenzState, LyapunovState, RosslerState,
};
use core::ffi::c_int;
use core::sync::atomic::{AtomicU32, Ordering};

pub use chaos_math::{
    ChaosParams as IwChaosParams, DuffingState as IwDuffingState,
    LogisticState as IwLogisticState, LorenzState as IwLorenzState,
    LyapunovState as IwLyapunovState, RosslerState as IwRosslerState,
};

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

pub const IWCHAOS_STA_MAX: usize = 32;
const TICK_CADENCE: u32 = 8;

struct IwChaosSta {
    active: bool,
    lorenz: LorenzState,
    rossler: RosslerState,
    lyapunov: LyapunovState,
    duffing: DuffingState,
    logistic: LogisticState,
    params: ChaosParams,
    snr_real: f64,
    snr_imag: f64,
    tick_budget: u32,
}

struct StaTable {
    slots: [IwChaosSta; IWCHAOS_STA_MAX],
}

unsafe impl Sync for StaTable {}

static mut STA_TABLE: StaTable = StaTable {
    slots: [const { IwChaosSta::empty() }; IWCHAOS_STA_MAX],
};
static TICK_GEN: AtomicU32 = AtomicU32::new(0);

impl IwChaosSta {
    const fn empty() -> Self {
        Self {
            active: false,
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
            lyapunov: LyapunovState {
                traj: LorenzState {
                    x: 0.1,
                    y: 0.1,
                    z: 0.1,
                },
                dx: 1.0,
                dy: 0.0,
                dz: 0.0,
                sum: 0.0,
                steps: 0,
            },
            duffing: DuffingState {
                x: 1.0,
                y: 0.0,
                t: 0.0,
            },
            logistic: LogisticState { x: 0.3, r: 4.0 },
            params: ChaosParams {
                backoff_us: 10,
                power_state: 2,
                snr_delta_centidecibels: 0,
                channel_24ghz: 1,
                channel_5ghz: 36,
                tx_power_mw: 50,
                jitter_us: 1,
                adaptive_dt: 0.01,
                lyapunov_est: 0.906,
            },
            snr_real: 0.0,
            snr_imag: 0.0,
            tick_budget: 0,
        }
    }

    fn ensure_active(&mut self) {
        if !self.active {
            *self = Self::empty();
            self.active = true;
        }
    }

    fn tick_full(&mut self) {
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
        TICK_GEN.fetch_add(1, Ordering::Relaxed);
    }

    fn tick_hot(&mut self) {
        if self.tick_budget == 0 {
            self.tick_full();
            self.tick_budget = TICK_CADENCE;
        } else {
            self.tick_budget -= 1;
            self.params.jitter_us = logistic_jitter_us(&mut self.logistic, 100);
        }
    }

    fn feedback(&mut self, tx_success: i32, snr_db: i32) {
        self.snr_real = (snr_db as f64) / 40.0;
        self.snr_imag = if tx_success != 0 { 0.0 } else { 0.5 };
        if tx_success == 0 {
            self.tick_budget = 0;
        }
    }

    fn scan_iter_count(&mut self, channel: u16, band_2ghz: bool) -> u16 {
        self.tick_hot();
        let preferred = if band_2ghz {
            self.params.channel_24ghz
        } else {
            self.params.channel_5ghz
        };
        let ch = channel as u32;
        let pref = preferred;
        if ch == pref {
            3
        } else if ch.abs_diff(pref) <= 4 {
            2
        } else {
            1
        }
    }

    fn scan_dwell_tu(&mut self, base: u16) -> u16 {
        self.tick_hot();
        let bias = (self.params.tx_power_mw as u32 * base as u32 / 200) as u16;
        base.saturating_add(bias.min(30))
    }

    fn power_timeout_us(&mut self, base: u32) -> u32 {
        self.tick_hot();
        base.saturating_add(self.params.backoff_us as u32)
    }

    fn thermal_backoff_us(&mut self, intel: u32) -> u32 {
        self.tick_hot();
        intel
            .saturating_add(self.params.backoff_us as u32)
            .min(20_000)
    }

    fn coex_agg_limit(&mut self, intel: u16) -> u16 {
        self.tick_hot();
        let jitter = self.params.jitter_us as u32;
        let scaled = intel as u32 * (80 + jitter * 40 / 100) / 100;
        scaled.clamp(200, 8000) as u16
    }

    fn agg_time_limit(&mut self, coex_limit: u16) -> u16 {
        self.tick_hot();
        let lorenz = self.params.backoff_us as u32;
        let scaled = coex_limit as u32 * (700 + lorenz) / 1000;
        scaled.clamp(200, 8000) as u16
    }

    fn quota_adjust(&mut self, intel: u32) -> u32 {
        self.tick_hot();
        let jitter = self.params.jitter_us as i32;
        let delta = jitter * 5 / 100 - 2;
        (intel as i32 + delta).clamp(1, 100) as u32
    }

    fn rate_select(&mut self, hint: u8, low: i32, high: i32) -> u8 {
        self.tick_hot();
        let cp = &self.params;

        if low < 0 || high < 0 || low > high {
            return hint;
        }

        let low = low as u8;
        let high = high as u8;
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

        if rel < 0 {
            rel = 0;
        }
        if rel >= span as i32 {
            rel = span as i32 - 1;
        }

        let chaos_idx = low.saturating_add(rel as u8);
        if hint >= low && hint <= high {
            let blended = ((chaos_idx as u16 * 3 + hint as u16) / 4) as u8;
            blended.clamp(low, high)
        } else {
            chaos_idx
        }
    }
}

fn sta_index(sta_id: u8) -> usize {
    (sta_id as usize) % IWCHAOS_STA_MAX
}

fn with_sta<R>(sta_id: u8, f: impl FnOnce(&mut IwChaosSta) -> R) -> R {
    let idx = sta_index(sta_id);
    unsafe {
        let slot = &mut STA_TABLE.slots[idx];
        slot.ensure_active();
        f(slot)
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_tick_rust(sta_id: u8) {
    with_sta(sta_id, |sta| sta.tick_hot());
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_rate_select_rust(
    sta_id: u8,
    hint: u8,
    low: c_int,
    high: c_int,
) -> u8 {
    with_sta(sta_id, |sta| sta.rate_select(hint, low as i32, high as i32))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_tx_feedback_rust(
    sta_id: u8,
    tx_success: c_int,
    snr_db: c_int,
) {
    with_sta(sta_id, |sta| sta.feedback(tx_success, snr_db));
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_update_all(
    lorenz: *mut LorenzState,
    rossler: *mut RosslerState,
    lyapunov: *mut LyapunovState,
    duffing: *mut DuffingState,
    logistic: *mut LogisticState,
    snr_real: f64,
    snr_imag: f64,
    out: *mut ChaosParams,
) {
    unsafe {
        with_sta(0, |sta| {
            if !lorenz.is_null() {
                sta.lorenz = *lorenz;
            }
            if !rossler.is_null() {
                sta.rossler = *rossler;
            }
            if !lyapunov.is_null() {
                sta.lyapunov = *lyapunov;
            }
            if !duffing.is_null() {
                sta.duffing = *duffing;
            }
            if !logistic.is_null() {
                sta.logistic = *logistic;
            }
            sta.snr_real = snr_real;
            sta.snr_imag = snr_imag;
            sta.tick_full();
            if !out.is_null() {
                *out = sta.params;
                if !lorenz.is_null() {
                    *lorenz = sta.lorenz;
                }
                if !rossler.is_null() {
                    *rossler = sta.rossler;
                }
                if !lyapunov.is_null() {
                    *lyapunov = sta.lyapunov;
                }
                if !duffing.is_null() {
                    *duffing = sta.duffing;
                }
                if !logistic.is_null() {
                    *logistic = sta.logistic;
                }
            }
        });
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_rust_tick_gen() -> u32 {
    TICK_GEN.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_scan_iter_count_rust(
    ctx: u8,
    channel: u16,
    band_2ghz: u8,
) -> u16 {
    with_sta(ctx, |sta| sta.scan_iter_count(channel, band_2ghz != 0))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_scan_dwell_tu_rust(ctx: u8, base: u16) -> u16 {
    with_sta(ctx, |sta| sta.scan_dwell_tu(base))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_power_timeout_us_rust(ctx: u8, base: u32) -> u32 {
    with_sta(ctx, |sta| sta.power_timeout_us(base))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_thermal_backoff_us_rust(ctx: u8, base: u32) -> u32 {
    with_sta(ctx, |sta| sta.thermal_backoff_us(base))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_coex_agg_limit_rust(sta_id: u8, intel: u16) -> u16 {
    with_sta(sta_id, |sta| sta.coex_agg_limit(intel))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_agg_time_limit_rust(sta_id: u8, coex_limit: u16) -> u16 {
    with_sta(sta_id, |sta| sta.agg_time_limit(coex_limit))
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_quota_adjust_rust(binding: u8, intel: u32) -> u32 {
    with_sta(binding, |sta| sta.quota_adjust(intel))
}
