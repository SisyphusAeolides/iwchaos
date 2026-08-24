// SPDX-License-Identifier: GPL-2.0-only
//
// iwchaos — Rust core entry point
//
// Responsibilities:
//   - PCIe bus enumeration and device claiming
//   - DMA ring buffer allocation and memory mapping
//   - Netlink interface toward rustd-udevd / rustd-resolved
//   - Dispatch to C shims (mac80211 / cfg80211 ABI)
//   - Chaos Engine hook: calls Fortran lorenz/mandelbrot via FFI
//   - Firmware state machine: delegates to Idris-generated C via FFI

#![no_std]
#![feature(allocator_api)]

// ── Kernel crate bindings (injected by Kbuild at compile time) ─────────────
extern crate kernel;

use kernel::prelude::*;
use kernel::pci;

// ── FFI declarations ───────────────────────────────────────────────────────
// Fortran Chaos Engine (lorenz.f90 / mandelbrot.f90, freestanding)
extern "C" {
    /// Lorenz attractor step. Returns the x coordinate mapped to µs backoff delay.
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

    /// Mandelbrot escape-time SNR mapper.
    /// Returns iteration count (escape time) for the given complex c = (cr, ci).
    fn mandelbrot_escape(cr: f64, ci: f64, max_iter: u32) -> u32;
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
    type: IwChaos,
    name: "iwchaos",
    author: "Kenny Glowner",
    description: "Memory-safe, formally verified, chaos-driven Intel Wi-Fi driver",
    license: "GPL v2",
}

// ── PCI device table ───────────────────────────────────────────────────────
// Intel Wi-Fi chipsets found on ThinkPad P53.
// AX201 (subsystem varies), AX200 baseline.
const IWCHAOS_DEVICES: &[pci::DeviceId] = &[
    pci::DeviceId::new(0x8086, 0x02f0), // Intel Wi-Fi 6 AX201
    pci::DeviceId::new(0x8086, 0x2723), // Intel Wi-Fi 6 AX200
];

// ── Driver state ───────────────────────────────────────────────────────────
struct IwChaos {
    /// Lorenz attractor live state (σ=10, ρ=28, β=8/3 canonical parameters).
    lorenz_x: f64,
    lorenz_y: f64,
    lorenz_z: f64,
}

// ── Module init / exit ─────────────────────────────────────────────────────
impl kernel::Module for IwChaos {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        pr_info!("iwchaos: initialising\n");
        Ok(IwChaos {
            // Canonical Lorenz initial conditions (must be non-zero)
            lorenz_x: 0.1,
            lorenz_y: 0.0,
            lorenz_z: 0.0,
        })
    }
}

impl Drop for IwChaos {
    fn drop(&mut self) {
        pr_info!("iwchaos: unloading\n");
    }
}

// ── Chaos Engine API (called from C shims via re-exported symbols) ─────────

/// Compute the next Lorenz-derived MAC backoff delay in microseconds.
///
/// # Safety
/// Must only be called from process context with the MAC lock held.
#[no_mangle]
pub unsafe extern "C" fn iwchaos_lorenz_backoff(state: *mut LorenzState) -> u64 {
    const SIGMA: f64 = 10.0;
    const RHO:   f64 = 28.0;
    const BETA:  f64 = 8.0 / 3.0;
    const DT:    f64 = 0.01;

    let s = &mut *state;
    let x_out = lorenz_backoff_step(
        &mut s.x, &mut s.y, &mut s.z,
        SIGMA, RHO, BETA, DT,
    );

    // Map x ∈ [-20, 20] → [10 µs, 1000 µs]
    let clamped = x_out.clamp(-20.0, 20.0);
    let normalised = (clamped + 20.0) / 40.0;   // [0, 1]
    (10.0 + normalised * 990.0) as u64
}

/// Map an SNR reading to a tuned-rs power state index via Mandelbrot escape time.
///
/// snr_real and snr_imag are the SNR decomposed onto the complex plane.
/// Returns a power state index in [0, 4].
#[no_mangle]
pub unsafe extern "C" fn iwchaos_mandelbrot_power_state(
    snr_real: f64,
    snr_imag: f64,
) -> u32 {
    const MAX_ITER: u32 = 256;
    let escape = mandelbrot_escape(snr_real, snr_imag, MAX_ITER);
    // Map escape time to 5 discrete power states
    (escape * 5 / MAX_ITER).min(4)
}

// ── Shared C-visible types ─────────────────────────────────────────────────

/// Lorenz attractor integrator state. Exposed to C shims.
#[repr(C)]
pub struct LorenzState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}
