// SPDX-License-Identifier: GPL-2.0-only
//
// iwchaos — Rust driver core
//
// Chaos theory and all driver decisions live here. C shims exist only for
// mac80211 / cfg80211 / PCI / MMIO ABI boundaries the RFL bindings do not cover.

use kernel::prelude::*;

// ── Firmware FSM events (mirror Idris FirmwareSM.idr) ───────────────────────

const FW_EV_CLAIM_PCI: u32 = 1;
const FW_EV_LOAD_FW: u32 = 2;
const FW_EV_START_MAC: u32 = 3;
const FW_EV_RESET: u32 = 4;

const FW_ST_PCI_READY: u32 = 1;
const FW_ST_MAC_ACTIVE: u32 = 3;

// ── Fortran chaos engine (freestanding, linked at build time) ───────────────

extern "C" {
    fn lorenz_backoff_step(x: *mut f64, y: *mut f64, z: *mut f64,
                           sigma: f64, rho: f64, beta: f64, dt: f64) -> f64;
    fn mandelbrot_escape(cr: f64, ci: f64, max_iter: u32) -> u32;
    fn lyapunov_step(x: *mut f64, y: *mut f64, z: *mut f64,
                     dx: *mut f64, dy: *mut f64, dz: *mut f64,
                     sigma: f64, rho: f64, beta: f64, dt: f64) -> f64;
    fn lyapunov_adaptive_dt(lyapunov_est: f64) -> f64;
    fn rossler_step(x: *mut f64, y: *mut f64, z: *mut f64,
                    a: f64, b: f64, c: f64, dt: f64) -> f64;
    fn rossler_channel_24ghz(x_rossler: f64) -> u32;
    fn rossler_channel_5ghz(y_rossler: f64) -> u32;
    fn rossler_tx_power_mw(z_rossler: f64) -> u32;
    fn logistic_jitter_us(x: *mut f64, r: f64, max_jitter_us: u32) -> u32;
    fn duffing_step(x: *mut f64, y: *mut f64, t: *mut f64,
                    delta: f64, gamma: f64, omega: f64, dt: f64);
    fn duffing_snr_delta_db(x: f64) -> f64;
}

// ── Idris-generated firmware / DMA linear types ─────────────────────────────

extern "C" {
    fn firmware_sm_init(base: *mut core::ffi::c_void) -> core::ffi::c_int;
    fn firmware_sm_step(event: u32) -> core::ffi::c_int;
    fn dma_linear_consume(ticket: u64) -> u64;
}

// ── C ABI: network stack + hardware plumbing ────────────────────────────────

extern "C" {
    fn iwchaos_mvm_init() -> core::ffi::c_int;
    fn iwchaos_mvm_exit();
    fn iwchaos_iwlwifi_init() -> core::ffi::c_int;
    fn iwchaos_iwlwifi_exit();
}

module! {
    type: IwChaosModule,
    name: "iwchaos",
    authors: ["Kenny Glowner"],
    description: "Chaos-driven Intel Wi-Fi driver (Rust core)",
    license: "GPL v2",
}

// ── repr(C) types shared with thin C shims ──────────────────────────────────

#[repr(C)]
#[derive(Copy, Clone)]
pub struct LorenzState { pub x: f64, pub y: f64, pub z: f64 }

#[repr(C)]
#[derive(Copy, Clone)]
pub struct RosslerState { pub x: f64, pub y: f64, pub z: f64 }

#[repr(C)]
#[derive(Copy, Clone)]
pub struct LyapunovState {
    pub traj: LorenzState,
    pub dx: f64, pub dy: f64, pub dz: f64,
    pub sum: f64,
    pub steps: u64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct DuffingState { pub x: f64, pub y: f64, pub t: f64 }

#[repr(C)]
#[derive(Copy, Clone)]
pub struct LogisticState { pub x: f64, pub r: f64 }

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

struct TxRing { head: u32, tail: u32 }
struct RxRing { head: u32, tail: u32 }

/// Per-device state — single owner of chaos dynamics and link context.
struct IwChaosDevice {
    mmio: *mut core::ffi::c_void,
    dma_dev: *mut core::ffi::c_void,
    hw: *mut core::ffi::c_void,
    lorenz: LorenzState,
    rossler: RosslerState,
    lyapunov: LyapunovState,
    duffing: DuffingState,
    logistic: LogisticState,
    params: ChaosParams,
    snr_real: f64,
    snr_imag: f64,
    fw_state: u32,
    tx_ring: TxRing,
    rx_ring: RxRing,
    mac_up: bool,
    scanning: bool,
    associated: bool,
}

struct IwChaosModule;

struct GlobalChaos {
    dev: IwChaosDevice,
}

// Rate-control hooks run under mac80211; single global is sufficient here.
unsafe impl Sync for GlobalChaos {}

static mut GLOBAL_CHAOS: Option<GlobalChaos> = None;

fn with_global<R>(f: impl FnOnce(&mut IwChaosDevice) -> R) -> R {
    unsafe {
        if GLOBAL_CHAOS.is_none() {
            GLOBAL_CHAOS = Some(GlobalChaos {
                dev: default_device(
                    core::ptr::null_mut(),
                    core::ptr::null_mut(),
                    core::ptr::null_mut(),
                ),
            });
        }
        f(&mut GLOBAL_CHAOS.as_mut().unwrap().dev)
    }
}

impl IwChaosDevice {
    fn lorenz_backoff(&mut self) -> u64 {
        const SIGMA: f64 = 10.0;
        const RHO: f64 = 28.0;
        const BETA: f64 = 8.0 / 3.0;
        const DT: f64 = 0.01;

        let s = &mut self.lorenz;
        let x_out = unsafe {
            lorenz_backoff_step(&mut s.x, &mut s.y, &mut s.z, SIGMA, RHO, BETA, DT)
        };
        let clamped = x_out.clamp(-20.0, 20.0);
        let norm = (clamped + 20.0) / 40.0;
        (10.0 + norm * 990.0) as u64
    }

    fn mandelbrot_power(&mut self) -> u32 {
        const MAX_ITER: u32 = 256;
        let escape = unsafe {
            mandelbrot_escape(self.snr_real, self.snr_imag, MAX_ITER)
        };
        (escape * 5 / MAX_ITER).min(4)
    }

    fn rossler_channels(&mut self) -> (u32, u32, u32) {
        const A: f64 = 0.2;
        const B: f64 = 0.2;
        const C: f64 = 5.7;
        const DT: f64 = 0.05;

        let s = &mut self.rossler;
        unsafe { rossler_step(&mut s.x, &mut s.y, &mut s.z, A, B, C, DT) };
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
                &mut s.traj.x, &mut s.traj.y, &mut s.traj.z,
                &mut s.dx, &mut s.dy, &mut s.dz,
                SIGMA, RHO, BETA, DT,
            )
        };
        s.sum += log_growth;
        s.steps += 1;
        let est = if s.steps > 0 { s.sum / (s.steps as f64 * DT) } else { 0.906 };
        unsafe { lyapunov_adaptive_dt(est) }
    }

    fn lyapunov_est(&self) -> f64 {
        const DT: f64 = 0.01;
        let s = &self.lyapunov;
        if s.steps > 0 { s.sum / (s.steps as f64 * DT) } else { 0.906 }
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

    fn tick_chaos(&mut self) {
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
    }

    fn rate_select(&mut self, n_rates: u8, _table: *const u8) -> u8 {
        self.tick_chaos();
        let cp = &self.params;
        if n_rates == 0 {
            return 0;
        }

        let base = (cp.power_state as i32 * (n_rates as i32 - 1) / 4) as i32;
        let snr = cp.snr_delta_centidecibels;
        let delta = if snr >= 0 { (snr + 100) / 200 } else { -(((-snr) + 100) / 200) };

        let mut jitter = 0i32;
        if cp.lyapunov_est < 1.2 && cp.jitter_us > 0 {
            if cp.jitter_us < 34 {
                jitter = -1;
            } else if cp.jitter_us > 66 {
                jitter = 1;
            }
        }

        let mut idx = base + delta + jitter;
        if idx < 0 {
            idx = 0;
        }
        if idx >= n_rates as i32 {
            idx = n_rates as i32 - 1;
        }
        idx as u8
    }

    fn channel_freq_mhz(&mut self, prefer_5ghz: bool) -> u32 {
        self.tick_chaos();
        let cp = &self.params;

        if cp.lyapunov_est < 0.5 && cp.lyapunov_est > 0.0 {
            return 0;
        }

        if prefer_5ghz {
            5000 + cp.channel_5ghz * 5
        } else if cp.channel_24ghz == 14 {
            2484
        } else {
            2407 + cp.channel_24ghz * 5
        }
    }

    fn feedback(&mut self, tx_success: i32, snr_db: i32) {
        self.snr_real = (snr_db as f64) / 40.0;
        self.snr_imag = if tx_success != 0 { 0.0 } else { 0.5 };
    }

    fn fw_step(&mut self, event: u32) {
        let next = unsafe { firmware_sm_step(event) };
        if next >= 0 {
            self.fw_state = next as u32;
        }
    }
}

fn default_device(mmio: *mut core::ffi::c_void,
                  dma_dev: *mut core::ffi::c_void,
                  hw: *mut core::ffi::c_void) -> IwChaosDevice {
    IwChaosDevice {
        mmio,
        dma_dev,
        hw,
        lorenz: LorenzState { x: 0.1, y: 0.1, z: 0.1 },
        rossler: RosslerState { x: 0.1, y: 0.0, z: 0.0 },
        lyapunov: LyapunovState {
            traj: LorenzState { x: 0.1, y: 0.1, z: 0.1 },
            dx: 1.0, dy: 0.0, dz: 0.0,
            sum: 0.0, steps: 0,
        },
        duffing: DuffingState { x: 1.0, y: 0.0, t: 0.0 },
        logistic: LogisticState { x: 0.3, r: 4.0 },
        params: ChaosParams {
            backoff_us: 10,
            power_state: 0,
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
        fw_state: 0,
        tx_ring: TxRing { head: 0, tail: 0 },
        rx_ring: RxRing { head: 0, tail: 0 },
        mac_up: false,
        scanning: false,
        associated: false,
    }
}

fn dev_ref<'a>(ptr: *mut core::ffi::c_void) -> Option<&'a mut IwChaosDevice> {
    if ptr.is_null() {
        None
    } else {
        Some(unsafe { &mut *(ptr as *mut IwChaosDevice) })
    }
}

impl kernel::Module for IwChaosModule {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        pr_info!("iwchaos: complete iwlwifi replacement (chaos-enhanced MVM + PCIe)\n");
        unsafe {
            let err = iwchaos_iwlwifi_init();
            if err < 0 {
                return Err(Error::from_errno(err));
            }
            let err = iwchaos_mvm_init();
            if err < 0 {
                iwchaos_iwlwifi_exit();
                return Err(Error::from_errno(err));
            }
        }
        Ok(IwChaosModule)
    }
}

impl Drop for IwChaosModule {
    fn drop(&mut self) {
        unsafe {
            iwchaos_mvm_exit();
            iwchaos_iwlwifi_exit();
        }
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_tick_rust() {
    with_global(|dev| dev.tick_chaos());
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_rate_bias_rust(index: u8, low: u8, high: u8) -> u8 {
    with_global(|dev| {
        dev.tick_chaos();
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
pub extern "C" fn iwchaos_chaos_tx_feedback_rust(tx_success: core::ffi::c_int, snr_db: core::ffi::c_int) {
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
        let mut dev = default_device(core::ptr::null_mut(), core::ptr::null_mut(), core::ptr::null_mut());
        if !lorenz.is_null() { dev.lorenz = *lorenz; }
        if !rossler.is_null() { dev.rossler = *rossler; }
        if !lyapunov.is_null() { dev.lyapunov = *lyapunov; }
        if !duffing.is_null() { dev.duffing = *duffing; }
        if !logistic.is_null() { dev.logistic = *logistic; }
        dev.snr_real = snr_real;
        dev.snr_imag = snr_imag;
        dev.tick_chaos();
        if !out.is_null() {
            *out = dev.params;
            if !lorenz.is_null() { *lorenz = dev.lorenz; }
            if !rossler.is_null() { *rossler = dev.rossler; }
            if !lyapunov.is_null() { *lyapunov = dev.lyapunov; }
            if !duffing.is_null() { *duffing = dev.duffing; }
            if !logistic.is_null() { *logistic = dev.logistic; }
        }
    }
}
