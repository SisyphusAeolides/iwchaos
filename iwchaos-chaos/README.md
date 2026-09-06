# iwchaos-chaos

User-space library for the six-system chaos engine used for rate-control and
link-dynamics experiments in [iwchaos](https://github.com/SisyphusAeolides/iwchaos).

Systems: Lorenz, Mandelbrot, Lyapunov, Rössler, logistic map, Duffing oscillator.

The kernel DKMS policy is a separate fixed-point library; this crate is not
linked into kernel code.

Licensed under GPL-2.0-or-later.
