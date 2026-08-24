// SPDX-License-Identifier: GPL-2.0-only
//
// iwchaos — Rust core entry point
//
// Responsibilities:
//   - PCIe bus enumeration and device claiming
//   - DMA ring buffer allocation and memory mapping
//   - Netlink interface toward rustd-udevd / rustd-resolved
//   - Dispatch to C shims (mac80211 / cfg80211 ABI)
//   - Chaos Engine: Lorenz MAC backoff, Mandelbrot power state,
//                   Rössler channel selection, Logistic jitter,
//                   Duffing SNR delta, Lyapunov adaptive dt
//   - Firmware state machine: delegates to Idris-generated C via FFI
//
// Chaos integration overview:
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │              iwchaos Chaos Engine (Ring 0)                   │
//   │                                                              │
//   │  Lorenz (RK4)    → MAC CSMA/CA backoff delay [10–1000 µs]   │
//   │  Mandelbrot      → Coarse TX power state [0–4]              │
//   │  Duffing (RK4)   → Fine SNR delta [−6, +6] dB              │
//   │  Rössler (RK4)   → Channel selection (2.4 / 5 GHz)         │
//   │  Logistic map    → Per-packet jitter [1–100 µs]             │
//   │  Lyapunov (RK4)  → Adaptive integration dt                  │
//   │                                                              │
//   │  All six feed into a unified ChaosParams struct that         │
//   │  the C shims consume via FFI-exported functions.             │
//   └──────────────────────────────────────────────────────────────┘


// ── Kernel crate bindings (injected by Kbuild at compile time) ─────────────

use kernel::prelude::*;
use kernel::pci;

// ── FFI: Kernel Network Stack ────────────────────────────────────────────────
extern "C" {
    fn iwchaos_dev_kfree_skb_any(skb: *mut core::ffi::c_void);
}

// ── FFI: Lorenz Chaos Engine (lorenz.f90) ─────────────────────────────────
extern "C" {
    /// Single RK4 step of the Lorenz system.
    /// Updates (x, y, z) in place; returns the new x value mapped to µs backoff.
    ///
    /// # Safety
    /// Caller must initialise state to non-zero values before first call.
    fn lorenz_backoff_step(
        x: *mut f64,
        y: *mut f64,
        z: *mut f64,
        sigma: f64,
        rho: f64,
        beta: f64,
        dt: f64,
    ) -> f64;
}

// ── FFI: Mandelbrot Chaos Engine (mandelbrot.f90) ─────────────────────────
extern "C" {
    /// Mandelbrot escape-time SNR mapper.
    /// Returns iteration count (escape time) for the given complex c = (cr, ci).
    fn mandelbrot_escape(cr: f64, ci: f64, max_iter: u32) -> u32;
}

// ── FFI: Lyapunov Exponent Estimator (lyapunov.f90) ──────────────────────
extern "C" {
    /// Advance both the Lorenz trajectory and the perturbation vector one RK4
    /// step. Returns the log-growth factor for this step (Benettin 1980).
    ///
    /// # Safety
    /// State and perturbation must be non-zero. Perturbation is re-normalised
    /// automatically after each call.
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

    /// Compute an adaptive dt from the current Lyapunov estimate.
    /// Returns dt ∈ [DT_MIN, DT_MAX] = [0.001, 0.05].
    fn lyapunov_adaptive_dt(lyapunov_est: f64) -> f64;
}

// ── FFI: Rössler Attractor (rossler.f90) ─────────────────────────────────
extern "C" {
    /// Single RK4 step of the Rössler system. Returns updated x.
    ///
    /// # Safety
    /// State must be non-zero. Parameters: a=0.2, b=0.2, c=5.7 (canonical).
    fn rossler_step(
        x: *mut f64,
        y: *mut f64,
        z: *mut f64,
        a: f64,
        b: f64,
        c: f64,
        dt: f64,
    ) -> f64;

    /// Map Rössler x ∈ (-12, 12) to 2.4 GHz channel [1, 14].
    fn rossler_channel_24ghz(x_rossler: f64) -> u32;

    /// Map Rössler y ∈ (-12, 12) to 5 GHz channel index [0, 24].
    /// Actual channel = index * 4 + 36.
    fn rossler_channel_5ghz(y_rossler: f64) -> u32;

    /// Map Rössler z ∈ (0, 25) to TX power in milliwatts [0, 100].
    fn rossler_tx_power_mw(z_rossler: f64) -> u32;
}

// ── FFI: Logistic Map / Feigenbaum (logistic.f90) ────────────────────────
extern "C" {
    /// One step of the logistic map: x → r·x·(1-x).
    /// x is updated in place; returns new x.
    ///
    /// # Safety
    /// x must be in (0, 1); the function guards this internally.
    fn logistic_step(x: *mut f64, r: f64) -> f64;

    /// One logistic step → per-packet jitter in µs ∈ [1, max_jitter_us].
    fn logistic_jitter_us(x: *mut f64, r: f64, max_jitter_us: u32) -> u32;
}

// ── FFI: Duffing Oscillator (duffing.f90) ────────────────────────────────
extern "C" {
    fn duffing_step(x: *mut f64, y: *mut f64, t: *mut f64, delta: f64, gamma: f64, omega: f64, dt: f64);
    fn duffing_snr_delta_db(x: f64) -> f64;
}

// Idris-generated C firmware state machine
extern "C" {
    /// Initialise the Intel firmware state machine.
    /// Returns 0 on success, negative errno on failure.
    fn firmware_sm_init(base: *mut core::ffi::c_void) -> core::ffi::c_int;

    /// Transition the firmware state machine.
    fn firmware_sm_step(event: u32) -> core::ffi::c_int;

    /// Consume exactly one DMA buffer ticket (linear type, multiplicity 1).
    /// Returns the buffer physical address. Must be called exactly once per allocation.
    fn dma_linear_consume(ticket: u64) -> u64;
}

// ── Module metadata ────────────────────────────────────────────────────────
module! {
    type: IwChaosModule,
    name: "iwchaos",
    authors: ["Kenny Glowner"],
    description: "Memory-safe, formally verified, chaos-driven Intel Wi-Fi driver",
    license: "GPL v2",
}

// ── PCI device table ───────────────────────────────────────────────────────
// Intel Wi-Fi chipsets found on ThinkPad P53.
// AX201 (subsystem varies), AX200 baseline.

// ── Shared C-visible types ─────────────────────────────────────────────────

/// Lorenz attractor integrator state. Exposed to C shims.
#[repr(C)]
pub struct LorenzState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

/// Rössler attractor integrator state.
#[repr(C)]
pub struct RosslerState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

/// Lyapunov estimator state — co-integrates the perturbation vector alongside
/// the Lorenz trajectory to measure divergence rate.
#[repr(C)]
pub struct LyapunovState {
    /// Lorenz trajectory state.
    pub traj: LorenzState,
    /// Perturbation vector (unit-normalised after each step).
    pub dx: f64,
    pub dy: f64,
    pub dz: f64,
    /// Running Lyapunov sum (log-growth accumulator).
    pub sum: f64,
    /// Number of steps accumulated in sum.
    pub steps: u64,
}

/// Duffing oscillator state.
#[repr(C)]
pub struct DuffingState {
    /// Position coordinate (maps to SNR delta).
    pub x: f64,
    /// Velocity coordinate (rate of SNR change).
    pub y: f64,
    /// Continuous time variable (for the periodic forcing term).
    pub t: f64,
}

/// Logistic map state.
#[repr(C)]
pub struct LogisticState {
    /// Current orbit value x ∈ (0, 1).
    pub x: f64,
    /// Growth rate r (canonical: 4.0 for full chaos).
    pub r: f64,
}

/// Unified chaos engine parameters — all six attractor states plus derived
/// driver quantities. This struct is the single source of truth for the
/// chaos engine output that the C shims read via FFI.
#[repr(C)]
pub struct ChaosParams {
    /// Lorenz MAC backoff delay in microseconds [10, 1000].
    pub backoff_us: u64,
    /// Mandelbrot coarse TX power state [0, 4].
    pub power_state: u32,
    /// Duffing fine SNR delta in 0.01 dB units (i.e. -600 to +600 = -6 to +6 dB).
    pub snr_delta_centidecibels: i32,
    /// Rössler 2.4 GHz channel [1, 14].
    pub channel_24ghz: u32,
    /// Rössler 5 GHz channel number (ch_idx * 4 + 36).
    pub channel_5ghz: u32,
    /// Rössler TX power in milliwatts [0, 100].
    pub tx_power_mw: u32,
    /// Logistic per-packet jitter in microseconds [1, 100].
    pub jitter_us: u32,
    /// Current adaptive integration timestep (from Lyapunov estimate).
    pub adaptive_dt: f64,
    /// Current Lyapunov exponent estimate (running average).
    pub lyapunov_est: f64,
}

// ── FFI: PCIe and mac80211 Shim ────────────────────────────────────────────
extern "C" {
    fn iwchaos_pci_register() -> core::ffi::c_int;
    fn iwchaos_pci_unregister();
}

// ── Lifecycle Callbacks ────────────────────────────────────────────────────

#[no_mangle]
pub unsafe extern "C" fn iwchaos_core_alloc(
    _hw: *mut core::ffi::c_void,
    _mmio_base: *mut core::ffi::c_void,
) -> *mut core::ffi::c_void {
    pr_info!("iwchaos: Allocating per-device chaos engine\n");

    let device = kernel::alloc::KBox::new(IwChaosDevice {
        lorenz: LorenzState {
            x: 0.1, y: 0.1, z: 0.1,
        },
        rossler: RosslerState {
            x: 0.1, y: 0.0, z: 0.0,
        },
        lyapunov: LyapunovState {
            traj: LorenzState { x: 0.1, y: 0.1, z: 0.1 },
            dx: 1.0, dy: 0.0, dz: 0.0,
            sum: 0.0,
            steps: 0,
        },
        duffing: DuffingState {
            x: 1.0, y: 0.0, t: 0.0,
        },
        logistic: LogisticState {
            x: 0.3,
            r: 4.0,
        },
        tx_ring: TxRing { head: 0, tail: 0 },
        rx_ring: RxRing { head: 0, tail: 0 },
    }, kernel::alloc::flags::GFP_KERNEL);

    match device {
        Ok(dev) => kernel::alloc::KBox::into_raw(dev) as *mut core::ffi::c_void,
        Err(_) => core::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_core_free(rust_ctx: *mut core::ffi::c_void) {
    if !rust_ctx.is_null() {
        pr_info!("iwchaos: Freeing per-device chaos engine\n");
        let _ = unsafe { kernel::alloc::KBox::from_raw(rust_ctx as *mut IwChaosDevice) };
    }
}

// ── DMA Ring Structures ────────────────────────────────────────────────────
pub struct TxRing {
    pub head: u32,
    pub tail: u32,
}

pub struct RxRing {
    pub head: u32,
    pub tail: u32,
}

// ── Driver state ───────────────────────────────────────────────────────────
pub struct IwChaosDevice {
    lorenz:   LorenzState,
    rossler:  RosslerState,
    lyapunov: LyapunovState,
    duffing:  DuffingState,
    logistic: LogisticState,
    tx_ring:  TxRing,
    rx_ring:  RxRing,
}

struct IwChaosModule;

// ── Module init / exit ─────────────────────────────────────────────────────
impl kernel::Module for IwChaosModule {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        pr_info!("iwchaos: initialising chaos engine\n");
        pr_info!("iwchaos: attractors: Lorenz, Mandelbrot, Rössler, Duffing, Logistic, Lyapunov\n");

        unsafe {
            // Register with the PCIe subsystem (delegates to shim_pci.c)
            let err = iwchaos_pci_register();
            if err < 0 {
                return Err(Error::from_errno(err));
            }
        }

        Ok(IwChaosModule)
    }
}

impl Drop for IwChaosModule {
    fn drop(&mut self) {
        pr_info!("iwchaos: unloading module\n");
        unsafe {
            iwchaos_pci_unregister();
        }
    }
}

// ── Chaos Engine public API (called from C shims) ──────────────────────────

#[no_mangle]
pub unsafe extern "C" fn iwchaos_lorenz_backoff(state: *mut LorenzState) -> u64 {
    const SIGMA: f64 = 10.0;
    const RHO:   f64 = 28.0;
    const BETA:  f64 = 8.0 / 3.0;
    const DT:    f64 = 0.01;

    unsafe {
        let s = &mut *state;
        let x_out = lorenz_backoff_step(
            &mut s.x, &mut s.y, &mut s.z,
            SIGMA, RHO, BETA, DT,
        );

        let clamped = x_out.clamp(-20.0, 20.0);
        let normalised = (clamped + 20.0) / 40.0;   // [0, 1]
        (10.0 + normalised * 990.0) as u64
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_mandelbrot_power_state(
    snr_real: f64,
    snr_imag: f64,
) -> u32 {
    const MAX_ITER: u32 = 256;
    unsafe {
        let escape = mandelbrot_escape(snr_real, snr_imag, MAX_ITER);
        (escape * 5 / MAX_ITER).min(4)
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_rossler_channels(
    state:       *mut RosslerState,
    ch24_out:    *mut u32,
    ch5_out:     *mut u32,
    pwr_mw_out:  *mut u32,
) {
    const A:  f64 = 0.2;
    const B:  f64 = 0.2;
    const C:  f64 = 5.7;
    const DT: f64 = 0.05;

    unsafe {
        let s = &mut *state;
        rossler_step(&mut s.x, &mut s.y, &mut s.z, A, B, C, DT);

        *ch24_out   = rossler_channel_24ghz(s.x);
        *ch5_out    = rossler_channel_5ghz(s.y).saturating_mul(4).saturating_add(36);
        *pwr_mw_out = rossler_tx_power_mw(s.z);
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_logistic_jitter(state: *mut LogisticState) -> u32 {
    const MAX_JITTER_US: u32 = 100;
    unsafe {
        let s = &mut *state;
        logistic_jitter_us(&mut s.x, s.r, MAX_JITTER_US)
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_lyapunov_tick(state: *mut LyapunovState) -> f64 {
    const SIGMA: f64 = 10.0;
    const RHO:   f64 = 28.0;
    const BETA:  f64 = 8.0 / 3.0;
    const DT:    f64 = 0.01;

    unsafe {
        let s = &mut *state;
        let log_growth = lyapunov_step(
            &mut s.traj.x, &mut s.traj.y, &mut s.traj.z,
            &mut s.dx, &mut s.dy, &mut s.dz,
            SIGMA, RHO, BETA, DT,
        );

        s.sum   += log_growth;
        s.steps += 1;

        let est = if s.steps > 0 {
            s.sum / (s.steps as f64 * DT)
        } else {
            0.906
        };

        lyapunov_adaptive_dt(est)
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_lyapunov_estimate(state: *const LyapunovState) -> f64 {
    const DT: f64 = 0.01;
    unsafe {
        let s = &*state;
        if s.steps > 0 {
            s.sum / (s.steps as f64 * DT)
        } else {
            0.906
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn iwchaos_duffing_snr_delta(state: *mut DuffingState) -> i32 {
    const DELTA: f64 = 0.3;
    const GAMMA: f64 = 0.5;
    const OMEGA: f64 = 1.2;
    const DT:    f64 = 0.01;

    unsafe {
        let s = &mut *state;
        duffing_step(&mut s.x, &mut s.y, &mut s.t, DELTA, GAMMA, OMEGA, DT);

        let db = duffing_snr_delta_db(s.x);
        let val = db * 100.0;
        (val + if val < 0.0 { -0.5 } else { 0.5 }) as i32
    }
}

/// derived driver quantities. This is the primary interface for the C shims.
///
/// # Safety
/// Must be called with the chaos engine lock held (process context).
#[no_mangle]
pub unsafe extern "C" fn iwchaos_update_all(
    lorenz:   *mut LorenzState,
    rossler:  *mut RosslerState,
    lyapunov: *mut LyapunovState,
    duffing:  *mut DuffingState,
    logistic: *mut LogisticState,
    snr_real: f64,
    snr_imag: f64,
    out:      *mut ChaosParams,
) {
    unsafe {
        let p = &mut *out;

        p.adaptive_dt   = iwchaos_lyapunov_tick(lyapunov);
        p.lyapunov_est  = iwchaos_lyapunov_estimate(lyapunov);
        p.backoff_us    = iwchaos_lorenz_backoff(lorenz);
        p.power_state   = iwchaos_mandelbrot_power_state(snr_real, snr_imag);
        p.snr_delta_centidecibels = iwchaos_duffing_snr_delta(duffing);

        let mut ch24: u32 = 0;
        let mut ch5:  u32 = 0;
        let mut pwr:  u32 = 0;
        iwchaos_rossler_channels(rossler, &mut ch24, &mut ch5, &mut pwr);
        p.channel_24ghz = ch24;
        p.channel_5ghz  = ch5;
        p.tx_power_mw   = pwr;

        p.jitter_us = iwchaos_logistic_jitter(logistic);
    }
}

/// Transmit an SKB using the verified DMA ring and chaos math parameters.
/// 
/// This is called from the mac80211 shim when the kernel wants to send a packet.
#[no_mangle]
pub unsafe extern "C" fn iwchaos_mac_tx_rust(rust_ctx: *mut core::ffi::c_void, skb: *mut core::ffi::c_void) {
    if rust_ctx.is_null() {
        if !skb.is_null() {
            unsafe { iwchaos_dev_kfree_skb_any(skb); }
        }
        return;
    }

    unsafe {
        let dev = &mut *(rust_ctx as *mut IwChaosDevice);

        // 1. Extract per-packet jitter via logistic map
        let jitter = iwchaos_logistic_jitter(&mut dev.logistic);

        // 2. Extract MAC CSMA/CA backoff via Lorenz
        let backoff = iwchaos_lorenz_backoff(&mut dev.lorenz);

        // 3. Acquire Idris verified linear DMA ticket (simulated ticket generation)
        // The ticket ensures that the physical DMA buffer is linearly bound.
        let ticket = dev.tx_ring.tail as u64;
        let dma_addr = dma_linear_consume(ticket);

        // Advance the TX ring
        dev.tx_ring.tail = dev.tx_ring.tail.wrapping_add(1);

        // Log the transmission with chaos parameters (using pr_info macro for debug visibility)
        pr_info!("iwchaos: TX skb mapped to DMA {:#x} (Idris ticket {}) | Chaos parameters: Jitter {}us, Backoff {}us\n",
                 dma_addr, ticket, jitter, backoff);

        // We free the SKB here because we don't have the real Intel Wi-Fi hardware 
        // to map the memory to via PCIe MMIO doorbells.
        if !skb.is_null() {
            iwchaos_dev_kfree_skb_any(skb);
        }
    }
}

/// Poll the RX ring using chaos math parameters (scaffolding).
#[no_mangle]
pub unsafe extern "C" fn iwchaos_mac_rx_rust(rust_ctx: *mut core::ffi::c_void) {
    if rust_ctx.is_null() {
        return;
    }

    unsafe {
        let dev = &mut *(rust_ctx as *mut IwChaosDevice);

        // Just touch the structures to ensure they are used (RX scaffolding)
        let _ = iwchaos_lyapunov_estimate(&dev.lyapunov);
        let _ = iwchaos_duffing_snr_delta(&mut dev.duffing);
        
        let mut ch24: u32 = 0;
        let mut ch5:  u32 = 0;
        let mut pwr:  u32 = 0;
        iwchaos_rossler_channels(&mut dev.rossler, &mut ch24, &mut ch5, &mut pwr);

        // Advance RX ring head as a mock consume
        dev.rx_ring.head = dev.rx_ring.head.wrapping_add(1);
    }
}

/// Set the Wi-Fi LED brightness using Chaos Theory (Duffing Oscillator modulation).
///
/// This is called when the mac80211 led subsystem or userspace triggers the LED.
#[no_mangle]
pub unsafe extern "C" fn iwchaos_led_set_rust(rust_ctx: *mut core::ffi::c_void, requested_brightness: u32) {
    if rust_ctx.is_null() {
        return;
    }

    unsafe {
        let dev = &mut *(rust_ctx as *mut IwChaosDevice);

        // Advance the Duffing oscillator one step
        let snr_delta = iwchaos_duffing_snr_delta(&mut dev.duffing);

        // Base brightness is the requested brightness (e.g. 255 for ON)
        let mut final_brightness = requested_brightness as i32;

        if final_brightness > 0 {
            // Modulate the brightness using the Duffing SNR delta [-600, +600] centidB.
            // We scale the delta to apply a chaos-driven jitter to the LED brightness,
            // producing a visual representation of the channel's non-linear behavior!
            let chaos_modifier = snr_delta / 10; // [-60, +60]
            final_brightness = final_brightness + chaos_modifier;
            
            // Clamp to valid 8-bit LED brightness bounds [1, 255]
            if final_brightness < 1 {
                final_brightness = 1;
            } else if final_brightness > 255 {
                final_brightness = 255;
            }
        }

        pr_info!("iwchaos: LED brightness modulated by Duffing chaos: req={} final={}\n",
                 requested_brightness, final_brightness);

        // In a full hardware driver, we would issue an Intel host command here:
        // iwl_mvm_led_enable(mvm, final_brightness);
    }
}
