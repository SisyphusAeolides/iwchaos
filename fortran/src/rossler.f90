! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos Chaos Engine — Rössler Attractor Channel Hopper
!
! Compiled freestanding: gfortran -ffreestanding -fno-exceptions -O2 -c
! No libgfortran dependency.
!
! The Rössler system (Rössler 1976):
!   dx/dt = -(y + z)
!   dy/dt =  x + a·y
!   dz/dt =  b + z·(x - c)
!
! Canonical chaotic parameters: a = 0.2, b = 0.2, c = 5.7
!
! The Rössler attractor has a simpler geometric structure than Lorenz —
! a single-scroll topology that spirals outward then folds back — making
! its x and y coordinates ideal for quasi-random channel selection:
!
!   - x ∈ (-12, 12)  →  mapped to a channel index in the 2.4 GHz band (1–14)
!   - y ∈ (-12, 12)  →  mapped to the 5 GHz subband (36–165, step 4)
!   - z ∈ (0, 25)    →  mapped to a transmission power level (0–100 mW)
!
! The Rössler orbit is slower to repeat than Lorenz, which reduces the
! probability of colliding with another driver's channel pattern in
! dense RF environments (stadiums, conference halls, etc.).
!
! Integration: 4th-order Runge-Kutta (same RK4 as lorenz.f90).

module rossler_mod
    implicit none
    private

    public :: rossler_step
    public :: rossler_channel_24ghz
    public :: rossler_channel_5ghz
    public :: rossler_tx_power_mw

contains

    ! ── Single RK4 step of the Rössler system ─────────────────────────────────
    !
    ! x, y, z — current state (updated in place)
    ! a, b, c  — Rössler parameters (canonical: 0.2, 0.2, 5.7)
    ! dt       — integration timestep
    ! Returns x_out — the updated x value
    !
    ! Called from Rust via C FFI.
    function rossler_step(x, y, z, a, b, c, dt) result(x_out) &
            bind(C, name="rossler_step")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(inout) :: x, y, z
        real(c_double), intent(in)    :: a, b, c, dt
        real(c_double)                :: x_out

        real(c_double) :: kx1, ky1, kz1
        real(c_double) :: kx2, ky2, kz2
        real(c_double) :: kx3, ky3, kz3
        real(c_double) :: kx4, ky4, kz4
        real(c_double) :: xm, ym, zm

        ! k1
        kx1 = -(y + z)
        ky1 = x + a * y
        kz1 = b + z * (x - c)

        ! k2 (midpoint)
        xm = x + 0.5d0 * dt * kx1
        ym = y + 0.5d0 * dt * ky1
        zm = z + 0.5d0 * dt * kz1
        kx2 = -(ym + zm)
        ky2 = xm + a * ym
        kz2 = b + zm * (xm - c)

        ! k3 (second midpoint)
        xm = x + 0.5d0 * dt * kx2
        ym = y + 0.5d0 * dt * ky2
        zm = z + 0.5d0 * dt * kz2
        kx3 = -(ym + zm)
        ky3 = xm + a * ym
        kz3 = b + zm * (xm - c)

        ! k4 (endpoint)
        xm = x + dt * kx3
        ym = y + dt * ky3
        zm = z + dt * kz3
        kx4 = -(ym + zm)
        ky4 = xm + a * ym
        kz4 = b + zm * (xm - c)

        ! Combine
        x = x + (dt / 6.0d0) * (kx1 + 2.0d0*kx2 + 2.0d0*kx3 + kx4)
        y = y + (dt / 6.0d0) * (ky1 + 2.0d0*ky2 + 2.0d0*ky3 + ky4)
        z = z + (dt / 6.0d0) * (kz1 + 2.0d0*kz2 + 2.0d0*kz3 + kz4)

        x_out = x
    end function rossler_step

    ! ── Map Rössler x ∈ (-12, 12) → 2.4 GHz channel [1, 14] ─────────────────
    !
    ! Channels 1–14 are the IEEE 802.11 2.4 GHz channels.
    ! The mapping is linear: channel = round((x + 12) / 24 * 13) + 1
    !
    ! Called from Rust via C FFI.
    function rossler_channel_24ghz(x_rossler) result(channel) &
            bind(C, name="rossler_channel_24ghz")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        real(c_double),    intent(in) :: x_rossler
        integer(c_int32_t)            :: channel

        real(c_double) :: norm, clamped

        ! Clamp to attractor range
        clamped = x_rossler
        if (clamped < -12.0d0) clamped = -12.0d0
        if (clamped >  12.0d0) clamped =  12.0d0

        norm    = (clamped + 12.0d0) / 24.0d0   ! [0, 1]
        channel = int(norm * 13.0d0) + 1_c_int32_t
        if (channel < 1_c_int32_t)  channel = 1_c_int32_t
        if (channel > 14_c_int32_t) channel = 14_c_int32_t

    end function rossler_channel_24ghz

    ! ── Map Rössler y ∈ (-12, 12) → 5 GHz UNII channel index [0, 24] ─────────
    !
    ! Returns an index into the UNII-1/2/3 band (channels 36, 40, …, 165).
    ! The caller multiplies by 4 and adds 36 to get the actual channel number.
    !
    ! Called from Rust via C FFI.
    function rossler_channel_5ghz(y_rossler) result(ch_idx) &
            bind(C, name="rossler_channel_5ghz")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        real(c_double),    intent(in) :: y_rossler
        integer(c_int32_t)            :: ch_idx

        real(c_double) :: norm, clamped
        ! UNII-1/2/3 has 25 non-overlapping 20 MHz channels (36–165, step 4)
        integer(c_int32_t), parameter :: N_CHAN = 25_c_int32_t

        clamped = y_rossler
        if (clamped < -12.0d0) clamped = -12.0d0
        if (clamped >  12.0d0) clamped =  12.0d0

        norm   = (clamped + 12.0d0) / 24.0d0         ! [0, 1]
        ch_idx = int(norm * real(N_CHAN, c_double))
        if (ch_idx < 0_c_int32_t)           ch_idx = 0_c_int32_t
        if (ch_idx >= N_CHAN) ch_idx = N_CHAN - 1_c_int32_t

    end function rossler_channel_5ghz

    ! ── Map Rössler z ∈ (0, 25) → TX power [0, 100] mW ──────────────────────
    !
    ! z is always non-negative in the canonical Rössler orbit after transients.
    ! Maps linearly to milliwatts; the Rust caller converts to dBm for the FW.
    !
    ! Called from Rust via C FFI.
    function rossler_tx_power_mw(z_rossler) result(power_mw) &
            bind(C, name="rossler_tx_power_mw")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        real(c_double),    intent(in) :: z_rossler
        integer(c_int32_t)            :: power_mw

        real(c_double) :: clamped, norm

        clamped = z_rossler
        if (clamped < 0.0d0)  clamped = 0.0d0
        if (clamped > 25.0d0) clamped = 25.0d0

        norm     = clamped / 25.0d0         ! [0, 1]
        power_mw = int(norm * 100.0d0)
        if (power_mw < 0_c_int32_t)   power_mw = 0_c_int32_t
        if (power_mw > 100_c_int32_t) power_mw = 100_c_int32_t

    end function rossler_tx_power_mw

end module rossler_mod
