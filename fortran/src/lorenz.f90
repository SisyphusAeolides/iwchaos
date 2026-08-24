! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos Chaos Engine — Lorenz Attractor MAC Backoff
!
! Compiled freestanding: gfortran -ffreestanding -fno-exceptions -O2 -c
! No libgfortran dependency. No runtime. Pure arithmetic subroutines only.
!
! The Lorenz system:
!   dx/dt = σ(y - x)
!   dy/dt = x(ρ - z) - y
!   dz/dt = xy - βz
!
! Integration uses a simple 4th-order Runge-Kutta to keep the trajectory
! numerically stable across the strange attractor.

module lorenz_mod
    implicit none
    private

    public :: lorenz_backoff_step

contains

    ! Single RK4 step of the Lorenz system.
    ! Returns the updated x value (mapped to µs backoff by the Rust caller).
    !
    ! This function is called from Rust via C FFI (bind(C)).
    function lorenz_backoff_step(x, y, z, sigma, rho, beta, dt) result(x_out) &
            bind(C, name="lorenz_backoff_step")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(inout) :: x, y, z
        real(c_double), intent(in)    :: sigma, rho, beta, dt
        real(c_double)                :: x_out

        ! RK4 intermediates
        real(c_double) :: kx1, ky1, kz1
        real(c_double) :: kx2, ky2, kz2
        real(c_double) :: kx3, ky3, kz3
        real(c_double) :: kx4, ky4, kz4
        real(c_double) :: xm, ym, zm

        ! k1
        kx1 = sigma * (y - x)
        ky1 = x * (rho - z) - y
        kz1 = x * y - beta * z

        ! k2 (midpoint)
        xm = x + 0.5d0 * dt * kx1
        ym = y + 0.5d0 * dt * ky1
        zm = z + 0.5d0 * dt * kz1

        kx2 = sigma * (ym - xm)
        ky2 = xm * (rho - zm) - ym
        kz2 = xm * ym - beta * zm

        ! k3 (midpoint, second estimate)
        xm = x + 0.5d0 * dt * kx2
        ym = y + 0.5d0 * dt * ky2
        zm = z + 0.5d0 * dt * kz2

        kx3 = sigma * (ym - xm)
        ky3 = xm * (rho - zm) - ym
        kz3 = xm * ym - beta * zm

        ! k4 (endpoint)
        xm = x + dt * kx3
        ym = y + dt * ky3
        zm = z + dt * kz3

        kx4 = sigma * (ym - xm)
        ky4 = xm * (rho - zm) - ym
        kz4 = xm * ym - beta * zm

        ! Combine
        x = x + (dt / 6.0d0) * (kx1 + 2.0d0 * kx2 + 2.0d0 * kx3 + kx4)
        y = y + (dt / 6.0d0) * (ky1 + 2.0d0 * ky2 + 2.0d0 * ky3 + ky4)
        z = z + (dt / 6.0d0) * (kz1 + 2.0d0 * kz2 + 2.0d0 * kz3 + kz4)

        x_out = x
    end function lorenz_backoff_step

end module lorenz_mod
