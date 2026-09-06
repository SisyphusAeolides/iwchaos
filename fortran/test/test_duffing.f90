! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos — Duffing oscillator unit test

program test_duffing
    use duffing_mod, only: duffing_step, duffing_snr_delta_db, &
                            duffing_hausdorff_dim
    use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
    implicit none

    real(c_double) :: x, y, t_duff, delta_param, gamma_param, omega_param
    real(c_double) :: dt, x_out, snr_db, d_h
    real(c_double) :: x_traj(2000), y_traj(2000)
    integer(c_int32_t) :: n_traj, fails
    integer :: i

    delta_param = 0.3d0
    gamma_param = 0.5d0
    omega_param = 1.2d0
    dt          = 0.01d0
    fails       = 0_c_int32_t

    ! Non-zero initial conditions
    x = 1.0d0; y = 0.0d0; t_duff = 0.0d0

    ! --- Test 1: 20000 steps, all finite ---
    do i = 1, 20000
        x_out = duffing_step(x, y, t_duff, delta_param, gamma_param, omega_param, dt)
        if (x_out /= x_out .or. abs(x_out) > 1.0d6) then
            write(*,'(A,I6,A,ES12.4)') 'FAIL T1: step ', i, &
                ' non-finite x_out=', x_out
            fails = fails + 1_c_int32_t
            exit
        end if
    end do
    if (fails == 0_c_int32_t) write(*,*) 'PASS T1: Duffing 20000 steps all finite'

    ! --- Test 2: SNR delta mapping within (-6, +6) dB ---
    snr_db = duffing_snr_delta_db(x)
    write(*,'(A,F8.4,A,F8.4)') 'SNR delta: x=', x, ' → dB=', snr_db
    if (snr_db < -6.0d0 .or. snr_db > 6.0d0) then
        write(*,'(A,F8.4)') 'FAIL T2: snr_delta_db out of (-6,+6): ', snr_db
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T2: snr_delta_db in (-6, +6) dB'
    end if

    ! --- Test 3: SNR mapping for extreme inputs clamps ---
    snr_db = duffing_snr_delta_db(100.0d0)
    if (abs(snr_db - 6.0d0) > 1.0d-10) then
        write(*,'(A,F8.4)') 'FAIL T3a: x=100 should map to +6 dB: ', snr_db
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T3a: x=100 clamped to +6 dB'
    end if
    snr_db = duffing_snr_delta_db(-100.0d0)
    if (abs(snr_db + 6.0d0) > 1.0d-10) then
        write(*,'(A,F8.4)') 'FAIL T3b: x=-100 should map to -6 dB: ', snr_db
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T3b: x=-100 clamped to -6 dB'
    end if

    ! --- Test 4: Hausdorff dimension estimate near 1.4 ---
    ! Collect 2000 trajectory points after burn-in
    x = 1.0d0; y = 0.0d0; t_duff = 0.0d0
    do i = 1, 5000  ! burn-in
        x_out = duffing_step(x, y, t_duff, delta_param, gamma_param, omega_param, dt)
    end do
    n_traj = 2000_c_int32_t
    do i = 1, 2000
        x_out = duffing_step(x, y, t_duff, delta_param, gamma_param, omega_param, dt)
        x_traj(i) = x
        y_traj(i) = y
    end do

    d_h = duffing_hausdorff_dim(x_traj, y_traj, n_traj)
    write(*,'(A,F6.3,A)') 'Hausdorff dimension estimate D_H ≈ ', d_h, &
        '  (expected ≈ 1.4 for canonical Duffing)'

    if (d_h < 1.0d0 .or. d_h > 2.0d0) then
        write(*,'(A,F6.3)') 'FAIL T4: D_H estimate out of (1,2): ', d_h
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T4: D_H ∈ (1, 2) — fractional dimension confirmed'
    end if

    if (fails == 0_c_int32_t) then
        write(*,*) 'PASS: duffing — all tests.'
    else
        write(*,'(A,I4,A)') 'FAIL: ', fails, ' failures in duffing.'
        stop 1
    end if

end program test_duffing
