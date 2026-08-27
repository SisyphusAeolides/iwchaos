// SPDX-License-Identifier: GPL-2.0-only
//! Freestanding chaos numerics for ring 0 (no libm / no Fortran).

use super::{DuffingState, LogisticState, LorenzState, LyapunovState, RosslerState};

const M_PI: f64 = core::f64::consts::PI;

#[inline]
fn fabs(x: f64) -> f64 {
    if x < 0.0 { -x } else { x }
}

#[inline]
fn reduce_pi(x: f64) -> f64 {
    let two_pi = 2.0 * M_PI;
    let mut y = x;
    while y > M_PI {
        y -= two_pi;
    }
    while y < -M_PI {
        y += two_pi;
    }
    y
}

#[inline]
pub fn cos(x: f64) -> f64 {
    let x = reduce_pi(x);
    let x2 = x * x;
    let x4 = x2 * x2;
    let x6 = x4 * x2;
    1.0 - 0.5 * x2 + x4 / 24.0 - x6 / 720.0
}

#[inline]
pub fn sqrt(x: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    let mut guess = if x > 1.0 { x * 0.5 } else { x };
    for _ in 0..8 {
        guess = 0.5 * (guess + x / guess);
    }
    guess
}

#[inline]
pub fn ln(x: f64) -> f64 {
    if x <= 0.0 {
        return -1.0 / 0.0;
    }
    if x == 1.0 {
        return 0.0;
    }
    let mut v = x;
    let mut exp2 = 0i32;
    while v >= 2.0 {
        v *= 0.5;
        exp2 += 1;
    }
    while v < 1.0 {
        v *= 2.0;
        exp2 -= 1;
    }
    let y = (v - 1.0) / (v + 1.0);
    0.6931471805599453 * exp2 as f64 + 2.0 * (y + y * y * y / 3.0)
}

#[inline]
fn clamp_f64(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo {
        lo
    } else if v > hi {
        hi
    } else {
        v
    }
}

pub fn lorenz_step(s: &mut LorenzState, sigma: f64, rho: f64, beta: f64, dt: f64) -> f64 {
    let (kx1, ky1, kz1) = (
        sigma * (s.y - s.x),
        s.x * (rho - s.z) - s.y,
        s.x * s.y - beta * s.z,
    );
    let (xm, ym, zm) = (s.x + 0.5 * dt * kx1, s.y + 0.5 * dt * ky1, s.z + 0.5 * dt * kz1);
    let (kx2, ky2, kz2) = (
        sigma * (ym - xm),
        xm * (rho - zm) - ym,
        xm * ym - beta * zm,
    );
    let (xm, ym, zm) = (s.x + 0.5 * dt * kx2, s.y + 0.5 * dt * ky2, s.z + 0.5 * dt * kz2);
    let (kx3, ky3, kz3) = (
        sigma * (ym - xm),
        xm * (rho - zm) - ym,
        xm * ym - beta * zm,
    );
    let (xm, ym, zm) = (s.x + dt * kx3, s.y + dt * ky3, s.z + dt * kz3);
    let (kx4, ky4, kz4) = (
        sigma * (ym - xm),
        xm * (rho - zm) - ym,
        xm * ym - beta * zm,
    );
    s.x += dt * (kx1 + 2.0 * kx2 + 2.0 * kx3 + kx4) / 6.0;
    s.y += dt * (ky1 + 2.0 * ky2 + 2.0 * ky3 + ky4) / 6.0;
    s.z += dt * (kz1 + 2.0 * kz2 + 2.0 * kz3 + kz4) / 6.0;
    s.x
}

pub fn lorenz_backoff_us(s: &mut LorenzState) -> u64 {
    lorenz_step(s, 10.0, 28.0, 8.0 / 3.0, 0.01);
    let clamped = clamp_f64(s.x, -20.0, 20.0);
    let norm = (clamped + 20.0) / 40.0;
    (10.0 + norm * 990.0) as u64
}

pub fn mandelbrot_escape(cr: f64, ci: f64, max_iter: u32) -> u32 {
    let (mut zr, mut zi) = (cr, ci);
    for i in 0..max_iter {
        if zr * zr + zi * zi > 4.0 {
            return i;
        }
        let nr = zr * zr - zi * zi + cr;
        zi = 2.0 * zr * zi + ci;
        zr = nr;
    }
    max_iter
}

pub fn mandelbrot_power(snr_real: f64, snr_imag: f64) -> u32 {
    let escape = mandelbrot_escape(snr_real, snr_imag, 128);
    (escape * 5 / 128).min(4)
}

pub fn lyapunov_step(s: &mut LyapunovState, sigma: f64, rho: f64, beta: f64, dt: f64) -> f64 {
    lorenz_step(&mut s.traj, sigma, rho, beta, dt);
    let (x, y, z) = (s.traj.x, s.traj.y, s.traj.z);
    let (dx, dy, dz) = (
        sigma * (y - x),
        x * (rho - z) - y,
        x * y - beta * z,
    );
    let norm = sqrt(s.dx * s.dx + s.dy * s.dy + s.dz * s.dz).max(1e-12);
    let growth = ln(sqrt(dx * dx + dy * dy + dz * dz) / norm);
    s.dx = dx;
    s.dy = dy;
    s.dz = dz;
    growth
}

pub fn lyapunov_adaptive_dt(est: f64) -> f64 {
    if est > 1.0 {
        0.005
    } else if est > 0.5 {
        0.01
    } else {
        0.02
    }
}

pub fn lyapunov_est(s: &LyapunovState) -> f64 {
    const DT: f64 = 0.01;
    if s.steps > 0 {
        s.sum / (s.steps as f64 * DT)
    } else {
        0.906
    }
}

pub fn rossler_step(s: &mut RosslerState, a: f64, b: f64, c: f64, dt: f64) {
    let dx = -s.y - s.z;
    let dy = s.x + a * s.y;
    let dz = b + s.z * (s.x - c);
    s.x += dx * dt;
    s.y += dy * dt;
    s.z += dz * dt;
}

pub fn rossler_channel_24ghz(x: f64) -> u32 {
    ((fabs(x) * 3.0) as u32 % 11) + 1
}

pub fn rossler_channel_5ghz(y: f64) -> u32 {
    (fabs(y) as u32 % 25) * 4 + 36
}

pub fn rossler_tx_power_mw(z: f64) -> u32 {
    clamp_f64(20.0 + fabs(z) * 10.0, 1.0, 200.0) as u32
}

pub fn rossler_channels(s: &mut RosslerState) -> (u32, u32, u32) {
    rossler_step(s, 0.2, 0.2, 5.7, 0.05);
    (
        rossler_channel_24ghz(s.x),
        rossler_channel_5ghz(s.y),
        rossler_tx_power_mw(s.z),
    )
}

pub fn logistic_jitter_us(s: &mut LogisticState, max_jitter_us: u32) -> u32 {
    s.x = s.r * s.x * (1.0 - s.x);
    (s.x * max_jitter_us as f64) as u32
}

pub fn duffing_step(s: &mut DuffingState, delta: f64, gamma: f64, dt: f64) {
    let dx = s.y;
    let dy = gamma * cos(s.x) - delta * s.y - s.x * s.x * s.x;
    s.t += dt;
    s.x += dx * dt;
    s.y += dy * dt;
}

pub fn duffing_snr_delta_cd(s: &mut DuffingState) -> i32 {
    duffing_step(s, 0.3, 0.5, 0.01);
    let db = clamp_f64(s.x, -2.0, 2.0) * 1.5;
    let val = db * 100.0;
    (val + if val < 0.0 { -0.5 } else { 0.5 }) as i32
}
