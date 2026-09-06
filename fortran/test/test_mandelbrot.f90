! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos — Mandelbrot escape-time unit test (user-space, libgfortran allowed)
!
! Verifies that mandelbrot_escape:
!   1. Returns max_iter for a bounded point (inside the Mandelbrot set, c=0+0i)
!   2. Returns a small iteration count for a strongly divergent point (c=2+2i)
!   3. Returns a value in [1, max_iter] for all real-axis sweep inputs

program test_mandelbrot
    use mandelbrot_mod, only: mandelbrot_escape
    use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
    implicit none

    integer(c_int32_t) :: iters, max_iter, fails

    fails    = 0_c_int32_t
    max_iter = 256_c_int32_t

    ! --- Test 1: bounded point (c = 0+0i is inside the Mandelbrot set) ---
    iters = mandelbrot_escape(0.0d0, 0.0d0, max_iter)
    if (iters /= max_iter) then
        write(*,'(A,I4,A,I4)') 'FAIL T1: c=0+0i expected max_iter=', max_iter, &
            ', got ', iters
        fails = fails + 1_c_int32_t
    else
        write(*,*) 'PASS T1: c=0+0i bounded (iters = max_iter)'
    end if

    ! --- Test 2: strongly divergent point (c = 2+2i escapes in 1 iteration) ---
    iters = mandelbrot_escape(2.0d0, 2.0d0, max_iter)
    if (iters >= max_iter) then
        write(*,'(A,I4)') 'FAIL T2: c=2+2i should escape quickly, got iters=', iters
        fails = fails + 1_c_int32_t
    else
        write(*,'(A,I4)') 'PASS T2: c=2+2i escaped at iter ', iters
    end if

    ! --- Test 3: range check on a sweep of real-axis points ---
    block
        real(c_double)     :: cr
        integer(c_int32_t) :: i_loop
        do i_loop = 0_c_int32_t, 40_c_int32_t
            cr = -2.0d0 + real(i_loop, c_double) * (4.0d0 / 40.0d0)
            iters = mandelbrot_escape(cr, 0.0d0, max_iter)
            if (iters < 1_c_int32_t .or. iters > max_iter) then
                write(*,'(A,F6.3,A,I4)') 'FAIL T3: cr=', cr, &
                    ' iters out of range: ', iters
                fails = fails + 1_c_int32_t
            end if
        end do
        if (fails == 0_c_int32_t) &
            write(*,*) 'PASS T3: range [1,max_iter] for all real-axis sweep points'
    end block

    if (fails == 0_c_int32_t) then
        write(*,*) 'PASS: mandelbrot_escape — all tests.'
    else
        write(*,'(A,I4,A)') 'FAIL: ', fails, ' failures in mandelbrot_escape.'
        stop 1
    end if

end program test_mandelbrot
