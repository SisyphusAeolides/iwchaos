# iwchaos

A memory-safe, formally verified, chaos-driven rewrite of the Linux Intel Wi-Fi driver.

Replaces the legacy `iwlwifi` module with a Ring 0 kernel module (`iwchaos.ko`) built from a five-language stack targeting the Lenovo ThinkPad P53 on CIQ RLC Pro (6.12 kernel).

## Architecture

| Component | Language | Role |
|---|---|---|
| Core driver | Rust (RFL) | PCIe init, DMA ring buffers, Netlink, module lifecycle |
| ABI bridge | C | mac80211 / cfg80211 shims |
| Firmware FSM | Idris 2 | QTT linear types — DMA buffers consumed exactly once |
| Invariant proofs | Agda | Offline: wire bounds and protocol invariants |
| Chaos Engine | Fortran | Lorenz attractor MAC backoff, Mandelbrot SNR/power scaling |

## Build

```
make modules KERNEL_SRC=/lib/modules/$(uname -r)/build
```

Four phases run in order:
1. **Idris 2** — generates verified C from `idris/src/`
2. **Fortran** — compiles freestanding `.o` files from `fortran/src/`
3. **Rust/Cargo** — builds `no_std` staticlib via RFL
4. **Kbuild** — links all components into `iwchaos.ko`

## Chaos Engine

Standard Wi-Fi drivers use linear algorithms for backoff and power management. `iwchaos` replaces these with deterministic chaotic dynamics:

- **Lorenz attractor** (Runge-Kutta RK4): MAC CSMA/CA backoff delay — sensitive to initial conditions, eliminates repeated collision patterns in dense RF environments.
- **Mandelbrot escape time**: SNR and interference mapped to the complex plane. Escape time drives discrete power state selection and channel hop decisions.

## License

GPL-2.0-only
