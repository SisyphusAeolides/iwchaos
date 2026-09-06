! SPDX-License-Identifier: GPL-2.0-only
!
! iwchaos Chaos Engine — Mandelbrot SNR / Power State Mapper
!
! Compiled freestanding: gfortran -ffreestanding -fno-exceptions -O2 -c
! No libgfortran dependency.
!
! The Mandelbrot equation: z_{n+1} = z_n² + c
!
! SNR and interference are decomposed onto the complex plane and the
! escape time of the sequence is used to derive a discrete power state.
! Rapid escape → high chaotic interference → aggressive power change or
! channel hop. Slow escape (bounded) → stable signal → hold current state.

module mandelbrot_mod
    implicit none
    private

    public :: mandelbrot_escape

contains

    ! Compute the Mandelbrot escape-time iteration count for complex c = (cr, ci).
    ! Returns the iteration count at which |z| > 2, or max_iter if bounded.
    !
    ! Called from Rust via C FFI.
    function mandelbrot_escape(cr, ci, max_iter) result(iters) &
            bind(C, name="mandelbrot_escape")
        use, intrinsic :: iso_c_binding, only: c_double, c_int32_t
        implicit none

        real(c_double),    intent(in) :: cr, ci
        integer(c_int32_t), intent(in) :: max_iter
        integer(c_int32_t)             :: iters

        real(c_double) :: zr, zi, zr_new, zi_new, magnitude_sq
        integer(c_int32_t) :: i

        zr = 0.0d0
        zi = 0.0d0
        iters = max_iter

        do i = 1, max_iter
            magnitude_sq = zr * zr + zi * zi
            if (magnitude_sq > 4.0d0) then
                iters = i
                return
            end if
            ! z_{n+1} = z_n² + c
            zr_new = zr * zr - zi * zi + cr
            zi_new = 2.0d0 * zr * zi + ci
            zr = zr_new
            zi = zi_new
        end do
    end function mandelbrot_escape

end module mandelbrot_mod
