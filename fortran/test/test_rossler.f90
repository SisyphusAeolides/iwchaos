! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos — Rössler attractor unit test

program test_rossler
    use rossler_mod, only: rossler_step, rossler_channel_24ghz, &
                            rossler_channel_5ghz, rossler_tx_power_mw
    use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
    implicit none

    real(c_double)     :: x, y, z, a, b, c_param, dt, x_out
    integer(c_int32_t) :: ch24, ch5_idx, pwr, fails
    integer            :: i

    a       = 0.2d0
    b       = 0.2d0
    c_param = 5.7d0
    dt      = 0.05d0
    fails   = 0_c_int32_t

    ! Non-zero initial conditions
    x = 0.1d0; y = 0.1d0; z = 0.1d0

    ! Burn-in: 2000 steps to reach attractor
    do i = 1, 2000
        x_out = rossler_step(x, y, z, a, b, c_param, dt)
    end do

    ! --- Test 1: 5000 steps, all outputs within expected bounds ---
    do i = 1, 5000
        x_out = rossler_step(x, y, z, a, b, c_param, dt)

        ! Check finiteness
        if (x_out /= x_out .or. abs(x_out) > 1.0d6) then
            write(*,'(A,I6,A,ES12.4)') 'FAIL T1: step ', i, &
                ' non-finite x_out=', x_out
            fails = fails + 1_c_int32_t
            exit
        end if
    end do
    if (fails == 0_c_int32_t) write(*,*) 'PASS T1: Rössler 5000 steps all finite'

    ! --- Test 2: channel mappings in range ---
    ch24    = rossler_channel_24ghz(x)
    ch5_idx = rossler_channel_5ghz(y)
    pwr     = rossler_tx_power_mw(z)

    write(*,'(A,I3,A,I3,A,I3)') &
        'Rössler output: ch24=', ch24, '  ch5_idx=', ch5_idx, '  pwr_mw=', pwr

    if (ch24 < 1_c_int32_t .or. ch24 > 14_c_int32_t) then
        write(*,'(A,I3)') 'FAIL T2a: ch24 out of [1,14]: ', ch24
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T2a: ch24 in [1,14]'
    end if

    if (ch5_idx < 0_c_int32_t .or. ch5_idx > 24_c_int32_t) then
        write(*,'(A,I3)') 'FAIL T2b: ch5_idx out of [0,24]: ', ch5_idx
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T2b: ch5_idx in [0,24]'
    end if

    if (pwr < 0_c_int32_t .or. pwr > 100_c_int32_t) then
        write(*,'(A,I4)') 'FAIL T2c: tx_power_mw out of [0,100]: ', pwr
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T2c: tx_power_mw in [0,100]'
    end if

    ! --- Test 3: extreme inputs clamp correctly ---
    ch24 = rossler_channel_24ghz(999.0d0)
    if (ch24 /= 14_c_int32_t) then
        write(*,'(A,I3)') 'FAIL T3a: ch24 for x=999 should be 14: ', ch24
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T3a: ch24 clamped to 14 for x=999'
    end if

    ch24 = rossler_channel_24ghz(-999.0d0)
    if (ch24 /= 1_c_int32_t) then
        write(*,'(A,I3)') 'FAIL T3b: ch24 for x=-999 should be 1: ', ch24
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T3b: ch24 clamped to 1 for x=-999'
    end if

    if (fails == 0_c_int32_t) then
        write(*,*) 'PASS: rossler — all tests.'
    else
        write(*,'(A,I4,A)') 'FAIL: ', fails, ' failures in rossler.'
        stop 1
    end if

end program test_rossler
