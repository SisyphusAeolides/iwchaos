// SPDX-License-Identifier: GPL-2.0-only
//! Small, fixed-point policy state used from the kernel rate-scaling path.
//!
//! The kernel bridge serializes calls with a spinlock. Keeping this crate free
//! of floating point, allocation, and external runtime dependencies makes it
//! safe to call from the driver's atomic paths.

#![no_std]

use core::ffi::c_int;

const STA_COUNT: usize = 256;
const SCORE_MIN: i16 = -12;
const SCORE_MAX: i16 = 12;
const COOLDOWN_TICKS: u8 = 2;
const STATUS_COOLDOWN_MASK: u8 = 0x03;
const STATUS_FAILURE_SHIFT: u8 = 2;
const STATUS_FAILURE_MASK: u8 = 0x0c;

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[derive(Copy, Clone)]
struct StationState {
    chaos: u32,
    score: i16,
    status: u8,
}

impl StationState {
    const fn empty() -> Self {
        Self {
            chaos: 0,
            score: 0,
            status: 0,
        }
    }

    fn initialize(&mut self, sta_id: u8) {
        if self.chaos == 0 {
            self.chaos = 0x9e37_79b9u32.wrapping_add((sta_id as u32).wrapping_mul(0x6d2b_79f5));
            if self.chaos <= 1 {
                self.chaos = 0x6d2b_79f5;
            }
            self.score = 0;
            self.status = 0;
        }
    }

    #[inline]
    fn cooldown(&self) -> u8 {
        self.status & STATUS_COOLDOWN_MASK
    }

    #[inline]
    fn set_cooldown(&mut self, ticks: u8) {
        self.status = (self.status & !STATUS_COOLDOWN_MASK) | ticks.min(STATUS_COOLDOWN_MASK);
    }

    #[inline]
    fn failure_streak(&self) -> u8 {
        (self.status & STATUS_FAILURE_MASK) >> STATUS_FAILURE_SHIFT
    }

    #[inline]
    fn set_failure_streak(&mut self, streak: u8) {
        self.status = (self.status & !STATUS_FAILURE_MASK)
            | (streak.min(STATUS_FAILURE_MASK >> STATUS_FAILURE_SHIFT) << STATUS_FAILURE_SHIFT);
    }

    fn next(&mut self) -> u32 {
        // Logistic map at r=4 in Q32 fixed point.  This keeps exploration
        // deterministic and cheap while remaining independent per station.
        let value = self.chaos;
        let complement = u32::MAX - value;
        let mut next = ((u64::from(value) * u64::from(complement)) >> 30) as u32;
        if next <= 1 {
            let mut mixed = value ^ value.rotate_left(13);
            mixed ^= mixed >> 17;
            next = if mixed <= 1 { 0x6d2b_79f5 } else { mixed };
        }
        self.chaos = next;
        next
    }

    fn feedback(&mut self, success: bool, snr_db: i32) {
        let snr_score = (snr_db + 70).clamp(-30, 30) as i16;
        let outcome = if success { 8 } else { -12 };
        let sample = (outcome + snr_score / 4).clamp(SCORE_MIN, SCORE_MAX);
        self.score = ((self.score * 3) + sample) / 4;
        if success {
            self.set_failure_streak(0);
        } else {
            self.set_failure_streak(self.failure_streak().saturating_add(1));
        }
        // A completed transmission provides fresher evidence than the
        // pre-feedback dwell, so allow the next decision to react to it.
        self.set_cooldown(0);
    }

    fn choose(&mut self, index: u8, low: i32, high: i32) -> u8 {
        if low < 0 || high < low || high > u8::MAX as i32 {
            return index;
        }

        let low = low as u8;
        let high = high as u8;
        let current = if index < low {
            low
        } else if index > high {
            high
        } else {
            index
        };

        // Let the stock scaler settle briefly after each policy move. This
        // keeps the advisory path from chattering when feedback is sparse.
        if self.cooldown() > 0 {
            self.set_cooldown(self.cooldown() - 1);
            return current;
        }

        // Strong evidence gets a deterministic response. Chaos is reserved
        // for the uncertain middle, where it supplies bounded exploration.
        let step: i8 = if self.failure_streak() >= 2 || self.score <= -6 {
            -1
        } else if self.score >= 7 {
            1
        } else {
            let phase = self.next();
            if self.score <= -3 && phase & 0x0f == 0 {
                -1
            } else if self.score >= 4 && phase & 0x0f == 0x0f {
                1
            } else {
                match phase & 0x3f {
                    0 => -1,
                    0x3f => 1,
                    _ => 0,
                }
            }
        };

        let selected = match step {
            -1 if current > low => current - 1,
            1 if current < high => current + 1,
            _ => current,
        };
        if selected != current {
            self.set_cooldown(COOLDOWN_TICKS);
        }
        selected
    }
}

static mut STATES: [StationState; STA_COUNT] = [const { StationState::empty() }; STA_COUNT];

unsafe fn station(sta_id: u8) -> &'static mut StationState {
    &mut *core::ptr::addr_of_mut!(STATES)
        .cast::<StationState>()
        .add(sta_id as usize)
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_rate_select_rust(
    sta_id: u8,
    index: u8,
    low: c_int,
    high: c_int,
) -> u8 {
    unsafe {
        let state = station(sta_id);
        state.initialize(sta_id);
        state.choose(index, low as i32, high as i32)
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_tx_feedback_rust(sta_id: u8, success: c_int, snr_db: c_int) {
    unsafe {
        let state = station(sta_id);
        state.initialize(sta_id);
        state.feedback(success != 0, snr_db as i32);
    }
}

#[no_mangle]
pub extern "C" fn iwchaos_chaos_sta_release_rust(sta_id: u8) {
    unsafe {
        core::ptr::write(station(sta_id), StationState::empty());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selection_stays_in_range() {
        let mut state = StationState::empty();
        state.initialize(7);
        for _ in 0..512 {
            let selected = state.choose(5, 2, 8);
            assert!((2..=8).contains(&selected));
        }
    }

    #[test]
    fn invalid_range_preserves_hint() {
        let mut state = StationState::empty();
        state.initialize(1);
        assert_eq!(state.choose(7, 8, 2), 7);
        assert_eq!(state.choose(7, -1, 2), 7);
    }

    #[test]
    fn failures_move_down_and_success_moves_up() {
        let mut state = StationState::empty();
        state.initialize(1);
        for _ in 0..5 {
            state.feedback(false, -90);
        }
        assert_eq!(state.choose(5, 2, 8), 4);

        for _ in 0..8 {
            state.feedback(true, -30);
        }
        assert!(state.choose(5, 2, 8) >= 5);
    }

    #[test]
    fn logistic_phase_remains_nonzero_and_changes() {
        let mut state = StationState::empty();
        state.initialize(3);
        let first = state.chaos;
        let second = state.next();
        assert_ne!(first, second);
        assert_ne!(second, 0);
        for _ in 0..128 {
            assert_ne!(state.next(), 0);
        }
    }

    #[test]
    fn policy_moves_only_one_adjacent_rate() {
        let mut state = StationState::empty();
        state.initialize(9);
        for _ in 0..6 {
            state.feedback(false, -95);
        }
        assert_eq!(state.choose(5, 2, 8), 4);

        for _ in 0..10 {
            state.feedback(true, -30);
        }
        assert_eq!(state.choose(5, 2, 8), 6);
    }
}
