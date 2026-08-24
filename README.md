# iwchaos

A memory-safe, formally verified, chaos-driven rewrite of the Linux Intel Wi-Fi driver.

Replaces the legacy `iwlwifi` module with a Ring 0 kernel module (`iwchaos.ko`) built from a five-language stack targeting the Lenovo ThinkPad P53 on CIQ RLC Pro (6.12 kernel).

## Architecture

| Component | Language | Role |
|---|---|---|
| Core driver | Rust (RFL) | PCIe init, DMA ring buffers, Netlink, module lifecycle |
| ABI bridge | C | mac80211 / cfg80211 / rate control / channel shims |
| Firmware FSM | Idris 2 | QTT linear types — provably safe DMA and chaos modes |
| Invariant proofs | Agda | Offline verification of bounds and protocol invariants |
| Chaos Engine | Fortran | 6-system chaos theory suite (freestanding numerical core) |

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

Standard Wi-Fi drivers use linear algorithms for backoff, rate control, and channel selection. `iwchaos` replaces these with deterministic chaotic dynamics mapped continuously to the driver state:

- **Lorenz attractor (RK4)**: Maps to MAC CSMA/CA backoff delay. Sensitive to initial conditions, eliminating repeated collision patterns in dense RF environments.
- **Mandelbrot escape time**: Maps complex SNR readings to coarse TX power bands.
- **Duffing oscillator (RK4)**: Maps to fine-grained SNR delta (±6 dB) for the MCS rate selection.
- **Rössler attractor (RK4)**: Maps (x,y) phase space to pseudo-aperiodic 2.4 GHz and 5 GHz channel hopping.
- **Logistic map**: Generates Feigenbaum-cascade guided per-packet transmission jitter (1–100 µs).
- **Lyapunov exponent estimator**: Co-integrates perturbation vectors to track the chaotic intensity (λ₁). Used to adapt the integration timestep (`dt`) dynamically and gate aggressive MCS and channel hops.

## License

GPL-2.0-only
