! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos Chaos Engine — Logistic Map / Feigenbaum Cascade
!
! Compiled freestanding: gfortran -ffreestanding -fno-exceptions -O2 -c
! No libgfortran dependency.
!
! The logistic map:
!   x_{n+1} = r · x_n · (1 - x_n),  x_n ∈ (0, 1)
!
! Period-doubling route to chaos (Feigenbaum 1978):
!   r < 3.0       → fixed point
!   3.0 ≤ r < 3.45 → period-2 orbit
!   3.45 ≤ r < 3.54 → period-4
!   …
!   r ≥ 3.5699… → fully chaotic (Feigenbaum constant δ ≈ 4.6692…)
!   r = 4.0      → fully chaotic, ergodic on (0,1)
!
! Driver usage:
!   - The logistic map is used for lightweight per-packet jitter generation.
!     It is an order of magnitude cheaper than RK4 (one multiply, one subtract)
!     making it suitable for the hot TX path.
!   - r is adaptively set near 4.0 (deep chaos) but can be dialled back
!     toward 3.57 (onset of chaos) when minimal jitter is needed.
!   - A Feigenbaum cascade scan sweeps r to find the current bifurcation
!     depth, used to characterise the local RF environment complexity.
!
! The Feigenbaum universal constant δ = 4.66920160910299… appears in the
! ratio of consecutive bifurcation intervals — it is universal across all
! smooth unimodal maps (logistic, sine, quadratic). We embed it as a
! compile-time constant for the cascade scan.

module logistic_mod
    implicit none
    private

    public :: logistic_step
    public :: logistic_jitter_us
    public :: feigenbaum_cascade_depth

    ! Feigenbaum universal constant δ (Feigenbaum 1978, rigorous proof: Lanford 1982)
    real(8), parameter, public :: FEIGENBAUM_DELTA = 4.669201609102990d0

    ! Onset of chaos for the logistic map
    real(8), parameter, public :: LOGISTIC_R_CHAOS = 3.569945672d0

contains

    ! ── Single logistic map step ───────────────────────────────────────────────
    !
    ! x    — current state in (0, 1) (updated in place)
    ! r    — growth rate parameter. Use r=4.0 for full ergodic chaos.
    ! Returns x_{n+1}
    !
    ! Called from Rust via C FFI.
    function logistic_step(x, r) result(x_out) &
            bind(C, name="logistic_step")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(inout) :: x
        real(c_double), intent(in)    :: r
        real(c_double)                :: x_out

        ! Guard: keep x strictly in (0, 1) to avoid fixed-point collapse
        if (x <= 0.0d0) x = 1.0d-6
        if (x >= 1.0d0) x = 1.0d0 - 1.0d-6

        x     = r * x * (1.0d0 - x)
        x_out = x
    end function logistic_step

    ! ── Map logistic output x ∈ (0,1) → per-packet jitter [1, MAX_JITTER] µs ──
    !
    ! max_jitter_us — upper bound on jitter in microseconds
    ! x             — current logistic state (updated in place by one step)
    ! r             — logistic parameter (use 4.0 for full chaos)
    ! Returns: jitter in microseconds, strictly positive
    !
    ! Called from Rust via C FFI.
    function logistic_jitter_us(x, r, max_jitter_us) result(jitter) &
            bind(C, name="logistic_jitter_us")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        real(c_double),    intent(inout) :: x
        real(c_double),    intent(in)    :: r
        integer(c_int32_t), intent(in)   :: max_jitter_us
        integer(c_int32_t)               :: jitter

        real(c_double) :: x_new

        x_new  = logistic_step(x, r)
        jitter = int(x_new * real(max_jitter_us, c_double)) + 1_c_int32_t
        if (jitter < 1_c_int32_t)          jitter = 1_c_int32_t
        if (jitter > max_jitter_us) jitter = max_jitter_us

    end function logistic_jitter_us

    ! ── Feigenbaum cascade depth scan ─────────────────────────────────────────
    !
    ! Starting from r_start, scan upward in steps of FEIGENBAUM_DELTA-scaled
    ! intervals to count the period-doubling cascade depth reached before
    ! full chaos onset (r ≥ LOGISTIC_R_CHAOS).
    !
    ! depth — returns the bifurcation cascade depth [0 = fixed point, …, 6 = chaos]
    ! r_out — the r value at the detected depth
    !
    ! This is used offline / at module init to characterise the desired
    ! chaos intensity. In the driver, depth=6 (r≈4.0) is the default.
    !
    ! Called from Rust via C FFI.
    subroutine feigenbaum_cascade_depth(r_start, depth, r_out) &
            bind(C, name="feigenbaum_cascade_depth")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        real(c_double),    intent(in)  :: r_start
        integer(c_int32_t), intent(out) :: depth
        real(c_double),    intent(out) :: r_out

        ! Approximate bifurcation points of the logistic map
        real(c_double), parameter :: BIFURC(0:6) = [ &
            3.0d0,           & ! period 1 → 2
            3.449490d0,      & ! period 2 → 4
            3.544090d0,      & ! period 4 → 8
            3.564407d0,      & ! period 8 → 16
            3.568750d0,      & ! period 16 → 32
            3.569692d0,      & ! period 32 → 64
            3.569946d0       & ! onset of chaos ≈ LOGISTIC_R_CHAOS
        ]

        integer(c_int32_t) :: i

        depth = 0_c_int32_t
        r_out = r_start

        do i = 0_c_int32_t, 6_c_int32_t
            if (r_start >= BIFURC(i)) then
                depth = i + 1_c_int32_t
                r_out = BIFURC(i)
            end if
        end do

        ! Cap at depth 7 (full chaos)
        if (depth > 7_c_int32_t) depth = 7_c_int32_t

    end subroutine feigenbaum_cascade_depth

end module logistic_mod
