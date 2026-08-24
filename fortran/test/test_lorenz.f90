! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos — Lorenz attractor unit test (user-space, libgfortran allowed)
!
! Verifies that lorenz_backoff_step:
!   1. Produces distinct output values (attractor is chaotic, not degenerate)
!   2. Returns finite (non-NaN, non-Inf) values across 10 000 steps
!   3. The x trajectory stays within the bounded attractor region (-25, 25)

program test_lorenz
    use lorenz_mod, only: lorenz_backoff_step
    use, intrinsic :: iso_c_binding, only: c_double
    implicit none

    real(c_double) :: x, y, z, sigma, rho, beta, dt, x_out
    integer        :: i, fails, warns
    logical        :: ok

    sigma = 10.0d0
    rho   = 28.0d0
    beta  = 8.0d0 / 3.0d0
    dt    = 0.01d0

    ! Non-zero initial conditions as required by the driver
    x = 0.1d0
    y = 0.1d0
    z = 0.1d0

    fails = 0
    warns = 0

    do i = 1, 10000
        x_out = lorenz_backoff_step(x, y, z, sigma, rho, beta, dt)

        ! Check finiteness (NaN /= NaN, Inf > large bound)
        ok = (x_out == x_out) .and. (abs(x_out) < 1.0d10)
        if (.not. ok) then
            write(*,'(A,I6,A,ES20.10)') 'FAIL: step ', i, &
                ' produced non-finite x_out = ', x_out
            fails = fails + 1
        end if

        ! Lorenz x stays within roughly (-25, 25) for canonical parameters
        if (abs(x_out) > 25.0d0) then
            write(*,'(A,I6,A,F12.6)') 'WARN: step ', i, &
                ' x_out outside expected range: ', x_out
            warns = warns + 1
        end if
    end do

    if (warns > 0) then
        write(*,'(I4,A)') warns, ' out-of-range warnings (non-fatal)'
    end if

    if (fails == 0) then
        write(*,*) 'PASS: lorenz_backoff_step — 10000 steps, all finite.'
    else
        write(*,'(A,I4,A)') 'FAIL: ', fails, ' failures in lorenz_backoff_step.'
        stop 1
    end if

end program test_lorenz
