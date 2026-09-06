! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos Chaos Engine — Lyapunov Exponent Estimator
!
! Compiled freestanding: gfortran -ffreestanding -fno-exceptions -O2 -c
! No libgfortran dependency. Pure arithmetic only.
!
! The largest Lyapunov exponent λ₁ of the Lorenz system measures the rate
! of divergence between nearby trajectories in phase space:
!
!   λ₁ = lim_{T→∞} (1/T) · ln(‖δ(T)‖ / ‖δ(0)‖)
!
! For the canonical Lorenz system (σ=10, ρ=28, β=8/3), λ₁ ≈ +0.906.
! A positive exponent confirms deterministic chaos (sensitivity to ICs).
!
! Driver usage:
!   - λ₁ is re-estimated every N steps using the finite-time approximation.
!   - When λ₁ falls toward zero (approaching a periodic orbit or fixed point),
!     the chaos engine adapts dt upward to recover full chaotic behaviour.
!   - When λ₁ is large, dt is reduced for finer-grained backoff resolution.
!
! Algorithm: Benettin et al. (1980) — periodic re-orthonormalisation of a
! single perturbation vector, no full QR decomposition needed for λ₁ only.

module lyapunov_mod
    implicit none
    private

    public :: lyapunov_step
    public :: lyapunov_adaptive_dt

contains

    ! ── Lorenz Jacobian applied to perturbation vector ────────────────────────
    !
    ! The Lorenz Jacobian at (x, y, z) is:
    !   J = [ -σ     σ    0  ]
    !       [ ρ-z   -1   -x  ]
    !       [  y     x   -β  ]
    !
    ! This computes J · [dx, dy, dz] (linearised flow around the attractor).
    subroutine lorenz_jacobian_apply(x, y, z, sigma, rho, beta, &
                                     dx, dy, dz, jdx, jdy, jdz)
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(in)  :: x, y, z, sigma, rho, beta
        real(c_double), intent(in)  :: dx, dy, dz
        real(c_double), intent(out) :: jdx, jdy, jdz

        jdx = -sigma * dx + sigma * dy
        jdy = (rho - z) * dx - dy - x * dz
        jdz = y * dx + x * dy - beta * dz
    end subroutine lorenz_jacobian_apply

    ! ── Single Lyapunov step ──────────────────────────────────────────────────
    !
    ! Advances the perturbation vector one RK4 step alongside the trajectory,
    ! returns the log-growth factor for this step.
    !
    ! x, y, z         — current Lorenz state (updated in place)
    ! dx, dy, dz      — perturbation vector (updated and re-normalised)
    ! sigma, rho, beta, dt — Lorenz and integration parameters
    ! Returns: log(|δ_new| / |δ_old|) — contribution to the Lyapunov sum
    !
    ! Called from Rust via C FFI.
    function lyapunov_step(x, y, z, dx, dy, dz, &
                           sigma, rho, beta, dt) result(log_growth) &
            bind(C, name="lyapunov_step")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(inout) :: x, y, z
        real(c_double), intent(inout) :: dx, dy, dz
        real(c_double), intent(in)    :: sigma, rho, beta, dt
        real(c_double)                :: log_growth

        ! Trajectory RK4 intermediates
        real(c_double) :: kx1, ky1, kz1, kx2, ky2, kz2
        real(c_double) :: kx3, ky3, kz3, kx4, ky4, kz4
        real(c_double) :: xm, ym, zm

        ! Perturbation RK4 intermediates (linearised flow)
        real(c_double) :: kdx1, kdy1, kdz1, kdx2, kdy2, kdz2
        real(c_double) :: kdx3, kdy3, kdz3, kdx4, kdy4, kdz4
        real(c_double) :: dxm, dym, dzm

        real(c_double) :: norm_before, norm_after, inv_norm

        ! Norm before step
        norm_before = sqrt(dx*dx + dy*dy + dz*dz)
        if (norm_before < 1.0d-300) then
            ! Degenerate: re-seed perturbation along x-axis
            dx = 1.0d0; dy = 0.0d0; dz = 0.0d0
            norm_before = 1.0d0
        end if

        ! k1 — trajectory
        kx1 = sigma * (y - x)
        ky1 = x * (rho - z) - y
        kz1 = x * y - beta * z
        ! k1 — perturbation (Jacobian at current point)
        call lorenz_jacobian_apply(x, y, z, sigma, rho, beta, &
                                   dx, dy, dz, kdx1, kdy1, kdz1)

        ! k2 — midpoint
        xm = x + 0.5d0 * dt * kx1
        ym = y + 0.5d0 * dt * ky1
        zm = z + 0.5d0 * dt * kz1
        dxm = dx + 0.5d0 * dt * kdx1
        dym = dy + 0.5d0 * dt * kdy1
        dzm = dz + 0.5d0 * dt * kdz1

        kx2 = sigma * (ym - xm)
        ky2 = xm * (rho - zm) - ym
        kz2 = xm * ym - beta * zm
        call lorenz_jacobian_apply(xm, ym, zm, sigma, rho, beta, &
                                   dxm, dym, dzm, kdx2, kdy2, kdz2)

        ! k3 — second midpoint
        xm = x + 0.5d0 * dt * kx2
        ym = y + 0.5d0 * dt * ky2
        zm = z + 0.5d0 * dt * kz2
        dxm = dx + 0.5d0 * dt * kdx2
        dym = dy + 0.5d0 * dt * kdy2
        dzm = dz + 0.5d0 * dt * kdz2

        kx3 = sigma * (ym - xm)
        ky3 = xm * (rho - zm) - ym
        kz3 = xm * ym - beta * zm
        call lorenz_jacobian_apply(xm, ym, zm, sigma, rho, beta, &
                                   dxm, dym, dzm, kdx3, kdy3, kdz3)

        ! k4 — endpoint
        xm = x + dt * kx3
        ym = y + dt * ky3
        zm = z + dt * kz3
        dxm = dx + dt * kdx3
        dym = dy + dt * kdy3
        dzm = dz + dt * kdz3

        kx4 = sigma * (ym - xm)
        ky4 = xm * (rho - zm) - ym
        kz4 = xm * ym - beta * zm
        call lorenz_jacobian_apply(xm, ym, zm, sigma, rho, beta, &
                                   dxm, dym, dzm, kdx4, kdy4, kdz4)

        ! Combine — trajectory
        x = x + (dt / 6.0d0) * (kx1 + 2.0d0*kx2 + 2.0d0*kx3 + kx4)
        y = y + (dt / 6.0d0) * (ky1 + 2.0d0*ky2 + 2.0d0*ky3 + ky4)
        z = z + (dt / 6.0d0) * (kz1 + 2.0d0*kz2 + 2.0d0*kz3 + kz4)

        ! Combine — perturbation
        dx = dx + (dt / 6.0d0) * (kdx1 + 2.0d0*kdx2 + 2.0d0*kdx3 + kdx4)
        dy = dy + (dt / 6.0d0) * (kdy1 + 2.0d0*kdy2 + 2.0d0*kdy3 + kdy4)
        dz = dz + (dt / 6.0d0) * (kdz1 + 2.0d0*kdz2 + 2.0d0*kdz3 + kdz4)

        ! Norm after step and log-growth
        norm_after = sqrt(dx*dx + dy*dy + dz*dz)
        if (norm_after < 1.0d-300) norm_after = 1.0d-300
        log_growth = log(norm_after / norm_before)

        ! Re-normalise perturbation to prevent overflow
        inv_norm = 1.0d0 / norm_after
        dx = dx * inv_norm
        dy = dy * inv_norm
        dz = dz * inv_norm

    end function lyapunov_step

    ! ── Adaptive dt from current Lyapunov estimate ────────────────────────────
    !
    ! Given a running estimate of λ₁ (lyapunov_est), returns a dt that keeps
    ! the local chaos intensity within a usable range for the driver.
    !
    ! Target: λ₁ · dt ≈ 0.01  (one percent divergence per step)
    ! dt is clamped to [DT_MIN, DT_MAX] to stay numerically stable.
    !
    ! Called from Rust via C FFI.
    function lyapunov_adaptive_dt(lyapunov_est) result(dt_out) &
            bind(C, name="lyapunov_adaptive_dt")
        use, intrinsic :: iso_c_binding, only: c_double
        implicit none

        real(c_double), intent(in) :: lyapunov_est
        real(c_double)             :: dt_out

        real(c_double), parameter :: DT_MIN    = 0.001d0
        real(c_double), parameter :: DT_MAX    = 0.05d0
        real(c_double), parameter :: TARGET    = 0.01d0   ! λ₁ · dt target
        real(c_double), parameter :: LAMBDA_FLOOR = 0.01d0 ! avoid division by near-zero

        real(c_double) :: lam

        lam = abs(lyapunov_est)
        if (lam < LAMBDA_FLOOR) lam = LAMBDA_FLOOR

        dt_out = TARGET / lam
        if (dt_out < DT_MIN) dt_out = DT_MIN
        if (dt_out > DT_MAX) dt_out = DT_MAX

    end function lyapunov_adaptive_dt

end module lyapunov_mod
