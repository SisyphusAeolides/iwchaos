! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos Chaos Engine — Duffing Oscillator (Bifurcation-Aware Fading Model)
!
! Compiled freestanding: gfortran -ffreestanding -fno-exceptions -O2 -c
! No libgfortran dependency.
!
! The Duffing oscillator (Duffing 1918, chaotic regime: Ueda 1979):
!
!   dx/dt = y
!   dy/dt = x - x³ - δ·y + γ·cos(ω·t)
!
! In the chaotic regime (δ=0.3, γ=0.5, ω=1.2), this system models a
! nonlinear spring driven by a periodic force — the "soft spring" case.
!
! The trajectory in (x, y) phase space exhibits a strange attractor with
! Hausdorff dimension D_H ≈ 1.4 (between a curve and a plane), making it
! fundamentally different from the Lorenz and Rössler attractors.
!
! Driver usage — oscillatory channel fading model:
!   - Wi-Fi signal strength in motion exhibits near-periodic oscillations
!     (multipath interference) superimposed on slow drift.
!   - The Duffing oscillator captures exactly this behaviour: a forced
!     nonlinear oscillator with chaotic sensitivity to initial conditions.
!   - x ∈ (-1.5, 1.5)  →  fine-grained SNR delta in dB (−6 to +6 dB)
!   - y ∈ (-1.5, 1.5)  →  rate of SNR change (rising / falling signal)
!   - Combined with the Mandelbrot power state: Duffing provides the
!     short-timescale SNR fluctuation and Mandelbrot the coarse power level.
!
! Integration: 4th-order Runge-Kutta with explicit time variable for the
! forcing term γ·cos(ω·t).

module duffing_mod
    implicit none
    private

    public :: duffing_step
    public :: duffing_snr_delta_db
    public :: duffing_hausdorff_dim

contains

    ! ── Single RK4 step of the Duffing oscillator ─────────────────────────────
    !
    ! x, y  — current state (updated in place)
    ! t     — current time (updated by dt)
    ! delta — damping coefficient (canonical: 0.3)
    ! gamma — forcing amplitude (canonical: 0.5)
    ! omega — forcing frequency (canonical: 1.2)
    ! dt    — integration timestep (canonical: 0.01)
    ! Returns x_out — the updated position
    !
    ! Called from Rust via C FFI.
    function duffing_step(x, y, t, delta, gamma, omega, dt) result(x_out) &
            bind(C, name="duffing_step")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(inout) :: x, y, t
        real(c_double), intent(in)    :: delta, gamma, omega, dt
        real(c_double)                :: x_out

        ! Local copies for intermediate stages
        real(c_double) :: kx1, ky1, kx2, ky2, kx3, ky3, kx4, ky4
        real(c_double) :: xm, ym, t1, t2

        ! Duffing RHS: dx/dt = y,  dy/dt = x - x³ - δy + γcos(ωt)
        ! k1 at (x, y, t)
        kx1 = y
        ky1 = x - x*x*x - delta*y + gamma*cos(omega*t)

        ! k2 at (x + dt/2*k1, t + dt/2)
        t1 = t + 0.5d0*dt
        xm = x + 0.5d0*dt*kx1
        ym = y + 0.5d0*dt*ky1
        kx2 = ym
        ky2 = xm - xm*xm*xm - delta*ym + gamma*cos(omega*t1)

        ! k3 at (x + dt/2*k2, t + dt/2)
        xm = x + 0.5d0*dt*kx2
        ym = y + 0.5d0*dt*ky2
        kx3 = ym
        ky3 = xm - xm*xm*xm - delta*ym + gamma*cos(omega*t1)

        ! k4 at (x + dt*k3, t + dt)
        t2 = t + dt
        xm = x + dt*kx3
        ym = y + dt*ky3
        kx4 = ym
        ky4 = xm - xm*xm*xm - delta*ym + gamma*cos(omega*t2)

        ! Combine
        x = x + (dt/6.0d0) * (kx1 + 2.0d0*kx2 + 2.0d0*kx3 + kx4)
        y = y + (dt/6.0d0) * (ky1 + 2.0d0*ky2 + 2.0d0*ky3 + ky4)
        t = t2

        x_out = x
    end function duffing_step

    ! ── Map Duffing x ∈ (-1.5, 1.5) → SNR delta in dB ∈ (-6, +6) ────────────
    !
    ! A 1-dB SNR delta corresponds to measurable rate adaptation (802.11ax
    ! AMC thresholds are spaced ~2 dB apart). The Duffing oscillation thus
    ! injects a fine-grained, chaotic, physically-motivated perturbation
    ! around the Mandelbrot coarse power state.
    !
    ! Called from Rust via C FFI.
    function duffing_snr_delta_db(x_duffing) result(delta_db) &
            bind(C, name="duffing_snr_delta_db")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(in) :: x_duffing
        real(c_double)             :: delta_db

        real(c_double) :: clamped

        clamped  = x_duffing
        if (clamped < -1.5d0) clamped = -1.5d0
        if (clamped >  1.5d0) clamped =  1.5d0

        ! Linear map: x ∈ (-1.5, 1.5) → dB ∈ (-6, +6)
        delta_db = clamped * (6.0d0 / 1.5d0)

    end function duffing_snr_delta_db

    ! ── Box-counting approximation of Hausdorff dimension for diagnostics ──────
    !
    ! Returns a floating-point approximation of D_H for the Duffing attractor
    ! using a two-scale box-count over a short orbit segment.
    ! This is for telemetry / diagnostics only — not used in the hot path.
    !
    ! The theoretical value for canonical Duffing parameters is D_H ≈ 1.4.
    !
    ! Method: fixed 32×32 grid (1024 cells) at each of two scales.
    ! Occupied cells are tracked with a 1024-bit occupancy bitmap stored
    ! as 32 × int32 words — no heap allocation, kernel-safe.
    !
    ! Scale 1: eps1 = 0.25  (32 cells across 8 units → covers (-4, 4)×(-4, 4))
    ! Scale 2: eps2 = 0.50  (32 cells across 16 units → covers (-8, 8)×(-8, 8))
    !
    ! Called from Rust via C FFI.
    function duffing_hausdorff_dim(x_traj, y_traj, n) result(d_h) &
            bind(C, name="duffing_hausdorff_dim")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        integer(c_int32_t), intent(in) :: n
        real(c_double),    intent(in)  :: x_traj(n), y_traj(n)
        real(c_double)                 :: d_h

        ! Grid dimensions and scale parameters
        integer(c_int32_t), parameter :: GDIM  = 32_c_int32_t   ! cells per axis
        integer(c_int32_t), parameter :: NWORD = 32_c_int32_t   ! GDIM*GDIM/32

        ! Two bitmap arrays (one per scale)
        integer(c_int32_t) :: bmap1(NWORD), bmap2(NWORD)

        ! Scale 1: each cell = 0.25 units wide, bounding box (-4, 4)
        real(c_double), parameter :: EPS1 = 0.25d0
        real(c_double), parameter :: BOX1 = 4.0d0    ! half-width
        ! Scale 2: each cell = 0.50 units wide, bounding box (-8, 8)
        real(c_double), parameter :: EPS2 = 0.50d0
        real(c_double), parameter :: BOX2 = 8.0d0

        integer(c_int32_t) :: i, ix, iy, cell, word, bit_pos
        integer(c_int32_t) :: n1, n2, ib
        real(c_double)     :: xc, yc

        ! Initialise bitmaps to zero
        do i = 1_c_int32_t, NWORD
            bmap1(i) = 0_c_int32_t
            bmap2(i) = 0_c_int32_t
        end do

        do i = 1_c_int32_t, n
            xc = x_traj(i); yc = y_traj(i)

            ! Scale 1
            ix = int((xc + BOX1) / EPS1)
            iy = int((yc + BOX1) / EPS1)
            if (ix >= 0_c_int32_t .and. ix < GDIM .and. &
                iy >= 0_c_int32_t .and. iy < GDIM) then
                cell    = iy * GDIM + ix              ! [0, 1023]
                word    = cell / 32_c_int32_t + 1_c_int32_t
                bit_pos = mod(cell, 32_c_int32_t)
                bmap1(word) = ior(bmap1(word), ishft(1_c_int32_t, bit_pos))
            end if

            ! Scale 2
            ix = int((xc + BOX2) / EPS2)
            iy = int((yc + BOX2) / EPS2)
            if (ix >= 0_c_int32_t .and. ix < GDIM .and. &
                iy >= 0_c_int32_t .and. iy < GDIM) then
                cell    = iy * GDIM + ix
                word    = cell / 32_c_int32_t + 1_c_int32_t
                bit_pos = mod(cell, 32_c_int32_t)
                bmap2(word) = ior(bmap2(word), ishft(1_c_int32_t, bit_pos))
            end if
        end do

        ! Count set bits in each bitmap (manual popcount — no intrinsic in Fortran)
        n1 = 0_c_int32_t
        n2 = 0_c_int32_t
        do ib = 1_c_int32_t, NWORD
            ! Kernighan's bit-counting trick
            block
                integer(c_int32_t) :: v
                v = bmap1(ib)
                do while (v /= 0_c_int32_t)
                    v = iand(v, v - 1_c_int32_t)
                    n1 = n1 + 1_c_int32_t
                end do
                v = bmap2(ib)
                do while (v /= 0_c_int32_t)
                    v = iand(v, v - 1_c_int32_t)
                    n2 = n2 + 1_c_int32_t
                end do
            end block
        end do

        ! D_H ≈ log(N1/N2) / log(eps2/eps1)
        ! Note: eps2/eps1 = 2 → log(eps2/eps1) = log(2)
        if (n2 > 0_c_int32_t .and. n1 > 0_c_int32_t) then
            d_h = log(real(n1, c_double) / real(n2, c_double)) / log(2.0d0)
        else
            d_h = 1.4d0  ! fallback to theoretical value
        end if

    end function duffing_hausdorff_dim

end module duffing_mod
