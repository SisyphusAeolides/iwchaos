! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos — Logistic map / Feigenbaum unit test

program test_logistic
    use logistic_mod, only: logistic_step, logistic_jitter_us, &
                             feigenbaum_cascade_depth, FEIGENBAUM_DELTA
    use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
    implicit none

    real(c_double)     :: x, r, x_prev
    integer(c_int32_t) :: jitter, max_jitter, depth, fails
    real(c_double)     :: r_out
    integer            :: i
    logical            :: distinct

    fails     = 0_c_int32_t
    max_jitter = 100_c_int32_t

    ! --- Test 1: Feigenbaum constant embedded correctly ---
    write(*,'(A,F18.15)') 'Feigenbaum δ = ', FEIGENBAUM_DELTA
    if (abs(FEIGENBAUM_DELTA - 4.669201609102990d0) > 1.0d-12) then
        write(*,*) 'FAIL T1: Feigenbaum constant wrong'
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T1: Feigenbaum δ correct to 13 decimal places'
    end if

    ! --- Test 2: logistic_step keeps x in (0, 1) ---
    r = 4.0d0
    x = 0.3d0
    do i = 1, 10000
        x = logistic_step(x, r)
        if (x <= 0.0d0 .or. x >= 1.0d0) then
            write(*,'(A,I6,A,F12.10)') 'FAIL T2: x out of (0,1) at step ', i, ': x=', x
            fails = fails + 1_c_int32_t
            exit
        end if
    end do
    if (fails == 0_c_int32_t) write(*,*) 'PASS T2: logistic x stays in (0,1) for 10000 steps'

    ! --- Test 3: r=4 is chaotic — 1000 consecutive values are not all equal ---
    x = 0.3d0
    x_prev = x
    distinct = .false.
    do i = 1, 1000
        x = logistic_step(x, r)
        if (abs(x - x_prev) > 1.0d-10) distinct = .true.
        x_prev = x
    end do
    if (.not. distinct) then
        write(*,*) 'FAIL T3: logistic at r=4 appears periodic (not chaotic)'
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T3: logistic at r=4 produces distinct values (chaotic)'
    end if

    ! --- Test 4: jitter output in [1, max_jitter] ---
    x = 0.3d0
    do i = 1, 1000
        jitter = logistic_jitter_us(x, r, max_jitter)
        if (jitter < 1_c_int32_t .or. jitter > max_jitter) then
            write(*,'(A,I6,A,I4)') 'FAIL T4: jitter out of range at step ', i, ': ', jitter
            fails = fails + 1_c_int32_t
            exit
        end if
    end do
    if (fails == 0_c_int32_t) write(*,*) 'PASS T4: jitter in [1, max_jitter] for 1000 steps'

    ! --- Test 5: Feigenbaum cascade depth at r=4.0 → depth 7 (full chaos) ---
    call feigenbaum_cascade_depth(4.0d0, depth, r_out)
    write(*,'(A,I2,A,F10.7)') 'Cascade depth at r=4.0: depth=', depth, '  r_out=', r_out
    if (depth < 6_c_int32_t) then
        write(*,'(A,I2)') 'FAIL T5: depth at r=4.0 should be >= 6: ', depth
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T5: cascade depth at r=4.0 >= 6 (deep chaos)'
    end if

    ! --- Test 6: cascade depth at r=3.0 → depth 1 (period-2 orbit) ---
    call feigenbaum_cascade_depth(3.0d0, depth, r_out)
    write(*,'(A,I2,A,F10.7)') 'Cascade depth at r=3.0: depth=', depth, '  r_out=', r_out
    if (depth /= 1_c_int32_t) then
        write(*,'(A,I2)') 'FAIL T6: depth at r=3.0 should be 1: ', depth
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T6: cascade depth at r=3.0 is 1 (first bifurcation)'
    end if

    if (fails == 0_c_int32_t) then
        write(*,*) 'PASS: logistic/feigenbaum — all tests.'
    else
        write(*,'(A,I4,A)') 'FAIL: ', fails, ' failures.'
        stop 1
    end if

end program test_logistic
