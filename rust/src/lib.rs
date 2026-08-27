// SPDX-License-Identifier: GPL-2.0-only
//! Freestanding chaos core for iwchaos (no RFL — links into .ko via Cargo staticlib).
//!
//! Hot-path rate bias caches attractor state and only advances dynamics on a
//! cadence so the TX completion path stays cheaper than a full multi-attractor
//! tick every frame.

#![no_std]
#![allow(clippy::missing_safety_doc)]

use core::ffi::c_int;
use core::sync::atomic::{AtomicU32, Ordering};

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

// ── Fortran chaos engine (freestanding objects linked at build time) ────────

unsafe extern "C" {
    fn lorenz_backoff_step(
        x: *mut f64,
        y: *mut f64,
        z: *mut f64,
        sigma: f64,
        rho: f64,
        beta: f64,
        dt: f64,
    ) -> f64;
    fn mandelbrot_escape(cr: f64, ci: f64, max_iter: u32) -> u32;
    fn lyapunov_step(
        x: *mut f64,
        y: *mut f64,
        z: *mut f64,
        dx: *mut f64,
        dy: *mut f64,
        dz: *mut f64,
        sigma: f64,
        rho: f64,
        beta: f64,
        dt: f64,
    ) -> f64;
    fn lyapunov_adaptive_dt(lyapunov_est: f64) -> f64;
    fn rossler_step(
        x: *mut f64,
        y: *mut f64,
        z: *mut f64,
        a: f64,
        b: f64,
        c: f64,
        dt: f64,
    ) -> f64;
    fn rossler_channel_24ghz(x_rossler: f64) -> u32;
    fn rossler_channel_5ghz(y_rossler: f64) -> u32;
    fn rossler_tx_power_mw(z_rossler: f64) -> u32;
    fn logistic_jitter_us(x: *mut f64, r: f64, max_jitter_us: u32) -> u32;
    fn duffing_step(
        x: *mut f64,
        y: *mut f64,
        t: *mut f64,
        delta: f64,
        gamma: f64,
        omega: f64,
        dt: f64,
    );
    fn duffing_snr_delta_db(x: f64) -> f64;
}

/// Advance attractors at most once per this many hot-path calls.
const TICK_CADENCE: u32 = 8;

#[repr(C)]
#[derive(Copy, Clone)]
pub struct LorenzState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct RosslerState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct LyapunovState {
    pub traj: LorenzState,
    pub dx: f64,
    pub dy: f64,
    pub dz: f64,
    pub sum: f64,
    pub steps: u64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct DuffingState {
    pub x: f64,
    pub y: f64,
    pub t: f64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct LogisticState {
    pub x: f64,
    pub r: f64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct ChaosParams {
    pub backoff_us: u64,
    pub power_state: u32,
    pub snr_delta_centidecibels: i32,
    pub channel_24ghz: u32,
    pub channel_5ghz: u32,
    pub tx_power_mw: u32,
    pub jitter_us: u32,
    pub adaptive_dt: f64,
    pub lyapunov_est: f64,
}

struct IwChaosDevice {
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

struct GlobalChaos {
    dev: IwChaosDevice,
}

// Rate-control hooks run under mac80211; single global is sufficient here.
unsafe impl Sync for GlobalChaos {}

static mut GLOBAL_CHAOS: Option<GlobalChaos> = None;
static TICK_GEN: AtomicU32 = AtomicU32::new(0);

fn default_device() -> IwChaosDevice {
    IwChaosDevice {
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

fn with_global<R>(f: impl FnOnce(&mut IwChaosDevice) -> R) -> R {
    unsafe {
        if GLOBAL_CHAOS.is_none() {
            GLOBAL_CHAOS = Some(GlobalChaos {
                dev: default_device(),
            });
        }
        f(&mut GLOBAL_CHAOS.as_mut().unwrap_unchecked().dev)
    }
}

impl IwChaosDevice {
    fn lorenz_backoff(&mut self) -> u64 {
        const SIGMA: f64 = 10.0;
        const RHO: f64 = 28.0;
        const BETA: f64 = 8.0 / 3.0;
        const DT: f64 = 0.01;

        let s = &mut self.lorenz;
        let x_out =
            unsafe { lorenz_backoff_step(&mut s.x, &mut s.y, &mut s.z, SIGMA, RHO, BETA, DT) };
        let clamped = if x_out < -20.0 {
            -20.0
        } else if x_out > 20.0 {
            20.0
        } else {
            x_out
        };
        let norm = (clamped + 20.0) / 40.0;
        (10.0 + norm * 990.0) as u64
    }

    fn mandelbrot_power(&mut self) -> u32 {
        const MAX_ITER: u32 = 128;
        let escape = unsafe { mandelbrot_escape(self.snr_real, self.snr_imag, MAX_ITER) };
        (escape * 5 / MAX_ITER).min(4)
    }

    fn rossler_channels(&mut self) -> (u32, u32, u32) {
        const A: f64 = 0.2;
        const B: f64 = 0.2;
        const C: f64 = 5.7;
        const DT: f64 = 0.05;

        let s = &mut self.rossler;
        unsafe {
            rossler_step(&mut s.x, &mut s.y, &mut s.z, A, B, C, DT);
        }
        let ch24 = unsafe { rossler_channel_24ghz(s.x) };
        let ch5 = unsafe { rossler_channel_5ghz(s.y) * 4 + 36 };
        let pwr = unsafe { rossler_tx_power_mw(s.z) };
        (ch24, ch5, pwr)
    }

    fn logistic_jitter(&mut self) -> u32 {
        let s = &mut self.logistic;
        unsafe { logistic_jitter_us(&mut s.x, s.r, 100) }
    }

    fn lyapunov_tick(&mut self) -> f64 {
        const SIGMA: f64 = 10.0;
        const RHO: f64 = 28.0;
        const BETA: f64 = 8.0 / 3.0;
        const DT: f64 = 0.01;

        let s = &mut self.lyapunov;
        let log_growth = unsafe {
            lyapunov_step(
                &mut s.traj.x,
                &mut s.traj.y,
                &mut s.traj.z,
                &mut s.dx,
                &mut s.dy,
                &mut s.dz,
                SIGMA,
                RHO,
                BETA,
                DT,
            )
        };
        s.sum += log_growth;
        s.steps += 1;
        let est = if s.steps > 0 {
            s.sum / (s.steps as f64 * DT)
        } else {
            0.906
        };
        unsafe { lyapunov_adaptive_dt(est) }
    }

    fn lyapunov_est(&self) -> f64 {
        const DT: f64 = 0.01;
        let s = &self.lyapunov;
        if s.steps > 0 {
            s.sum / (s.steps as f64 * DT)
        } else {
            0.906
        }
    }

    fn duffing_snr_delta(&mut self) -> i32 {
        const DELTA: f64 = 0.3;
        const GAMMA: f64 = 0.5;
        const OMEGA: f64 = 1.2;
        const DT: f64 = 0.01;

        let s = &mut self.duffing;
        unsafe {
            duffing_step(&mut s.x, &mut s.y, &mut s.t, DELTA, GAMMA, OMEGA, DT);
            let db = duffing_snr_delta_db(s.x);
            let val = db * 100.0;
            (val + if val < 0.0 { -0.5 } else { 0.5 }) as i32
        }
    }

    fn tick_chaos_full(&mut self) {
        self.params.adaptive_dt = self.lyapunov_tick();
        self.params.lyapunov_est = self.lyapunov_est();
        self.params.backoff_us = self.lorenz_backoff();
        self.params.power_state = self.mandelbrot_power();
        self.params.snr_delta_centidecibels = self.duffing_snr_delta();
        let (ch24, ch5, pwr) = self.rossler_channels();
        self.params.channel_24ghz = ch24;
        self.params.channel_5ghz = ch5;
        self.params.tx_power_mw = pwr;
        self.params.jitter_us = self.logistic_jitter();
        TICK_GEN.fetch_add(1, Ordering::Relaxed);
    }

    /// Cheap tick for the TX/rate hot path: full dynamics every TICK_CADENCE calls.
    fn tick_chaos_hot(&mut self) {
        if self.tick_budget == 0 {
            self.tick_chaos_full();
            self.tick_budget = TICK_CADENCE;
        } else {
            self.tick_budget -= 1;
            // Always advance the logistic map — one multiply, drives rate jitter.
            self.params.jitter_us = self.logistic_jitter();
        }
    }

    fn feedback(&mut self, tx_success: i32, snr_db: i32) {
        self.snr_real = (snr_db as f64) / 40.0;
        self.snr_imag = if tx_success != 0 { 0.0 } else { 0.5 };
        // Force a full refresh after lossy TX so power/rate adapt quickly.
        if tx_success == 0 {
            self.tick_budget = 0;
        }
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_tick_rust() {
    with_global(|dev| dev.tick_chaos_hot());
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_rate_bias_rust(index: u8, low: u8, high: u8) -> u8 {
    with_global(|dev| {
        dev.tick_chaos_hot();
        let cp = &dev.params;
        let mut jitter = 0i32;
        if cp.lyapunov_est < 1.2 && cp.jitter_us > 0 {
            if cp.jitter_us < 34 {
                jitter = -1;
            } else if cp.jitter_us > 66 {
                jitter = 1;
            }
        }
        let mut idx = index as i32 + jitter;
        // Prefer higher MCS when Mandelbrot power state is strong and SNR delta positive.
        if cp.power_state >= 3 && cp.snr_delta_centidecibels > 50 {
            idx += 1;
        } else if cp.power_state <= 1 && cp.snr_delta_centidecibels < -50 {
            idx -= 1;
        }
        const INVALID: u8 = 0xff;
        if low != INVALID {
            idx = idx.max(low as i32);
        }
        if high != INVALID {
            idx = idx.min(high as i32);
        }
        idx.max(0) as u8
    })
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_tx_feedback_rust(tx_success: c_int, snr_db: c_int) {
    with_global(|dev| dev.feedback(tx_success, snr_db));
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
        let mut dev = default_device();
        if !lorenz.is_null() {
            dev.lorenz = *lorenz;
        }
        if !rossler.is_null() {
            dev.rossler = *rossler;
        }
        if !lyapunov.is_null() {
            dev.lyapunov = *lyapunov;
        }
        if !duffing.is_null() {
            dev.duffing = *duffing;
        }
        if !logistic.is_null() {
            dev.logistic = *logistic;
        }
        dev.snr_real = snr_real;
        dev.snr_imag = snr_imag;
        dev.tick_chaos_full();
        if !out.is_null() {
            *out = dev.params;
            if !lorenz.is_null() {
                *lorenz = dev.lorenz;
            }
            if !rossler.is_null() {
                *rossler = dev.rossler;
            }
            if !lyapunov.is_null() {
                *lyapunov = dev.lyapunov;
            }
            if !duffing.is_null() {
                *duffing = dev.duffing;
            }
            if !logistic.is_null() {
                *logistic = dev.logistic;
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_rust_tick_gen() -> u32 {
    TICK_GEN.load(Ordering::Relaxed)
}
