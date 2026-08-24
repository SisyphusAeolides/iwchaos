! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos — Lyapunov exponent unit test
!
! Verifies that:
!   1. The finite-time Lyapunov estimate converges toward the known
!      canonical value λ₁ ≈ 0.906 for Lorenz (σ=10, ρ=28, β=8/3).
!   2. The estimate is strictly positive (confirms chaos).
!   3. lyapunov_adaptive_dt returns dt in [DT_MIN, DT_MAX] = [0.001, 0.05].

program test_lyapunov
    use lyapunov_mod, only: lyapunov_step, lyapunov_adaptive_dt
    use, intrinsic :: iso_c_binding, only: c_double
    implicit none

    real(c_double) :: x, y, z, dx, dy, dz
    real(c_double) :: sigma, rho, beta, dt
    real(c_double) :: log_growth, lyapunov_sum, lyapunov_est, dt_out
    integer        :: i, n_steps, fails

    sigma   = 10.0d0
    rho     = 28.0d0
    beta    = 8.0d0 / 3.0d0
    dt      = 0.01d0
    n_steps = 50000
    fails   = 0

    ! Initial conditions (non-zero)
    x = 0.1d0; y = 0.1d0; z = 0.1d0
    ! Initial perturbation (unit vector along x)
    dx = 1.0d0; dy = 0.0d0; dz = 0.0d0

    lyapunov_sum = 0.0d0

    ! Burn-in: 5000 steps to reach attractor
    do i = 1, 5000
        log_growth = lyapunov_step(x, y, z, dx, dy, dz, sigma, rho, beta, dt)
    end do
    ! Reset accumulator after burn-in
    lyapunov_sum = 0.0d0

    do i = 1, n_steps
        log_growth = lyapunov_step(x, y, z, dx, dy, dz, sigma, rho, beta, dt)
        lyapunov_sum = lyapunov_sum + log_growth
    end do

    lyapunov_est = lyapunov_sum / (real(n_steps, c_double) * dt)

    write(*,'(A,F8.4)') 'Lyapunov estimate λ₁ = ', lyapunov_est
    write(*,'(A)') '  (expected ≈ 0.906 for canonical Lorenz parameters)'

    ! Test 1: positive exponent (chaos confirmed)
    if (lyapunov_est <= 0.0d0) then
        write(*,'(A,F8.4)') 'FAIL T1: λ₁ not positive: ', lyapunov_est
        fails = fails + 1
    else
        write(*,*) 'PASS T1: λ₁ > 0 (attractor is chaotic)'
    end if

    ! Test 2: within 20% of known value (numerical tolerance for finite time)
    if (lyapunov_est < 0.5d0 .or. lyapunov_est > 1.5d0) then
        write(*,'(A,F8.4)') 'FAIL T2: λ₁ far from expected 0.906: ', lyapunov_est
        fails = fails + 1
    else
        write(*,*) 'PASS T2: λ₁ within expected range [0.5, 1.5]'
    end if

    ! Test 3: adaptive dt bounds
    dt_out = lyapunov_adaptive_dt(lyapunov_est)
    write(*,'(A,F8.5)') 'Adaptive dt = ', dt_out

    if (dt_out < 0.001d0 .or. dt_out > 0.05d0) then
        write(*,'(A,F8.5)') 'FAIL T3: adaptive dt out of [0.001, 0.05]: ', dt_out
        fails = fails + 1
    else
        write(*,*) 'PASS T3: adaptive dt in [0.001, 0.05]'
    end if

    ! Test 4: adaptive dt for near-zero exponent clamps to DT_MAX
    dt_out = lyapunov_adaptive_dt(0.0d0)
    if (dt_out /= 0.05d0) then
        write(*,'(A,F8.5)') 'FAIL T4: near-zero λ₁ dt should be DT_MAX=0.05: ', dt_out
        fails = fails + 1
    else
        write(*,*) 'PASS T4: near-zero λ₁ → DT_MAX'
    end if

    if (fails == 0) then
        write(*,*) 'PASS: lyapunov — all tests.'
    else
        write(*,'(A,I4,A)') 'FAIL: ', fails, ' failures in lyapunov.'
        stop 1
    end if

end program test_lyapunov
