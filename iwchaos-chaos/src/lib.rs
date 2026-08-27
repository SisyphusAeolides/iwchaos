// SPDX-License-Identifier: GPL-2.0-or-later

//! Chaos-theory link dynamics for iwchaos.

#[derive(Debug, Clone, Copy, Default)]
pub struct LorenzState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct RosslerState {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct LyapunovState {
    pub traj: LorenzState,
    pub dx: f64,
    pub dy: f64,
    pub dz: f64,
    pub sum: f64,
    pub steps: u64,
}

impl Default for LyapunovState {
    fn default() -> Self {
        Self {
            traj: LorenzState { x: 0.1, y: 0.1, z: 0.1 },
            dx: 1.0,
            dy: 0.0,
            dz: 0.0,
            sum: 0.0,
            steps: 0,
        }
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct DuffingState {
    pub x: f64,
    pub y: f64,
    pub t: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct LogisticState {
    pub x: f64,
    pub r: f64,
}

impl Default for LogisticState {
    fn default() -> Self {
        Self { x: 0.3, r: 4.0 }
    }
}

#[derive(Debug, Clone, Copy, Default)]
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
            lorenz: LorenzState { x: 0.1, y: 0.1, z: 0.1 },
            rossler: RosslerState { x: 0.1, y: 0.0, z: 0.0 },
            lyapunov: LyapunovState::default(),
            duffing: DuffingState { x: 1.0, y: 0.0, t: 0.0 },
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

    pub fn rate_bias(&mut self, index: u8, low: u8, high: u8) -> u8 {
        self.tick();
        let cp = &self.params;
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
    }

    pub fn feedback(&mut self, tx_success: i32, snr_db: i32) {
        self.snr_real = (snr_db as f64) / 40.0;
        self.snr_imag = if tx_success != 0 { 0.0 } else { 0.5 };
    }

    fn lorenz_backoff(&mut self) -> u64 {
        lorenz_step(&mut self.lorenz, 10.0, 28.0, 8.0 / 3.0, 0.01);
        let clamped = self.lorenz.x.clamp(-20.0, 20.0);
        let norm = (clamped + 20.0) / 40.0;
        (10.0 + norm * 990.0) as u64
    }

    fn mandelbrot_power(&self) -> u32 {
        let escape = mandelbrot_escape(self.snr_real, self.snr_imag, 256);
        (escape * 5 / 256).min(4)
    }

    fn rossler_channels(&mut self) -> (u32, u32, u32) {
        rossler_step(&mut self.rossler, 0.2, 0.2, 5.7, 0.05);
        let ch24 = rossler_channel_24ghz(self.rossler.x);
        let ch5 = rossler_channel_5ghz(self.rossler.y);
        let pwr = rossler_tx_power_mw(self.rossler.z);
        (ch24, ch5, pwr)
    }

    fn logistic_jitter(&mut self) -> u32 {
        logistic_jitter_us(&mut self.logistic.x, self.logistic.r, 100)
    }

    fn lyapunov_tick(&mut self) -> f64 {
        let log_growth = lyapunov_step(&mut self.lyapunov, 10.0, 28.0, 8.0 / 3.0, 0.01);
        self.lyapunov.sum += log_growth;
        self.lyapunov.steps += 1;
        lyapunov_adaptive_dt(self.lyapunov_est())
    }

    fn lyapunov_est(&self) -> f64 {
        const DT: f64 = 0.01;
        if self.lyapunov.steps > 0 {
            self.lyapunov.sum / (self.lyapunov.steps as f64 * DT)
        } else {
            0.906
        }
    }

    fn duffing_snr_delta(&mut self) -> i32 {
        duffing_step(&mut self.duffing, 0.3, 0.5, 1.2, 0.01);
        let db = duffing_snr_delta_db(self.duffing.x);
        let val = db * 100.0;
        (val + if val < 0.0 { -0.5 } else { 0.5 }) as i32
    }
}

fn lorenz_step(s: &mut LorenzState, sigma: f64, rho: f64, beta: f64, dt: f64) {
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
}

fn mandelbrot_escape(cr: f64, ci: f64, max_iter: u32) -> u32 {
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

fn lyapunov_step(s: &mut LyapunovState, sigma: f64, rho: f64, beta: f64, dt: f64) -> f64 {
    lorenz_step(&mut s.traj, sigma, rho, beta, dt);
    let (x, y, z) = (s.traj.x, s.traj.y, s.traj.z);
    let (dx, dy, dz) = (
        sigma * (y - x),
        x * (rho - z) - y,
        x * y - beta * z,
    );
    let norm = (s.dx * s.dx + s.dy * s.dy + s.dz * s.dz).sqrt().max(1e-12);
    let growth = ((dx * dx + dy * dy + dz * dz).sqrt() / norm).ln();
    s.dx = dx;
    s.dy = dy;
    s.dz = dz;
    growth
}

fn lyapunov_adaptive_dt(est: f64) -> f64 {
    if est > 1.0 {
        0.005
    } else if est > 0.5 {
        0.01
    } else {
        0.02
    }
}

fn rossler_step(s: &mut RosslerState, a: f64, b: f64, c: f64, dt: f64) {
    let dx = -s.y - s.z;
    let dy = s.x + a * s.y;
    let dz = b + s.z * (s.x - c);
    s.x += dx * dt;
    s.y += dy * dt;
    s.z += dz * dt;
}

fn rossler_channel_24ghz(x: f64) -> u32 {
    ((x.abs() * 3.0) as u32 % 11) + 1
}

fn rossler_channel_5ghz(y: f64) -> u32 {
    (y.abs() as u32 % 25) * 4 + 36
}

fn rossler_tx_power_mw(z: f64) -> u32 {
    (20.0 + z.abs() * 10.0).clamp(1.0, 200.0) as u32
}

fn logistic_jitter_us(x: &mut f64, r: f64, max_jitter_us: u32) -> u32 {
    *x = r * *x * (1.0 - *x);
    (*x * max_jitter_us as f64) as u32
}

fn duffing_step(s: &mut DuffingState, delta: f64, gamma: f64, _omega: f64, dt: f64) {
    let dx = s.y;
    let dy = gamma * s.x.cos() - delta * s.y - s.x.powi(3);
    s.t += dt;
    s.x += dx * dt;
    s.y += dy * dt;
}

fn duffing_snr_delta_db(x: f64) -> f64 {
    x.clamp(-2.0, 2.0) * 1.5
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
    fn rate_bias_stays_in_bounds() {
        let mut e = ChaosEngine::default();
        let idx = e.rate_bias(5, 2, 8);
        assert!((2..=8).contains(&idx));
    }
}
