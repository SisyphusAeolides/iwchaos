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

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[derive(Copy, Clone)]
struct StationState {
    seed: u32,
    score: i16,
    ready: bool,
}

impl StationState {
    const fn empty() -> Self {
        Self {
            seed: 0,
            score: 0,
            ready: false,
        }
    }

    fn initialize(&mut self, sta_id: u8) {
        if !self.ready {
            self.seed = 0x9e37_79b9u32.wrapping_add((sta_id as u32).wrapping_mul(0x6d2b_79f5));
            if self.seed == 0 {
                self.seed = 1;
            }
            self.score = 0;
            self.ready = true;
        }
    }

    fn next(&mut self) -> u32 {
        let mut value = self.seed;
        value ^= value << 13;
        value ^= value >> 17;
        value ^= value << 5;
        self.seed = if value == 0 { 1 } else { value };
        self.seed
    }

    fn feedback(&mut self, success: bool, snr_db: i32) {
        let snr_score = (snr_db + 70).clamp(-20, 20) as i16;
        let outcome = if success { 4 } else { -8 };
        let sample = (outcome + snr_score / 4).clamp(SCORE_MIN, SCORE_MAX);
        self.score = ((self.score * 3) + sample) / 4;
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

        /*
         * Keep the stock decision exactly at the boundaries and limit the
         * policy to one adjacent rate. The small dither prevents a long-lived
         * tie from settling on one side, while the measured score decides
         * whether a move is useful.
         */
        let step = if self.score <= -4 {
            -1
        } else if self.score >= 8 {
            1
        } else {
            match self.next() & 0x0f {
                0 => -1,
                15 => 1,
                _ => 0,
            }
        };

        match step {
            -1 if current > low => current - 1,
            1 if current < high => current + 1,
            _ => current,
        }
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
}
