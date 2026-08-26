# iwchaos

Complete drop-in replacement for the Linux `iwlwifi` + `iwlmvm` stack on Intel AX200/AX201 (ThinkPad P53 class), with a chaos-theory rate-control layer.

## Stack

| Layer | Language | Role |
|---|---|---|
| Intel transport + MVM | C (vendored v7.2 + patches) | PCIe, firmware, mac80211, LEDs |
| Chaos policy | Rust (RFL) | Rate bias, TX feedback, Lyapunov/Lorenz/etc. |
| Chaos numerics (kernel) | Fortran | Freestanding RK4 / iterators linked into `.ko` |
| Chaos numerics (userspace) | Rust crate [`iwchaos-chaos`](iwchaos-chaos/) | Same dynamics for simulation/tests |
| Firmware FSM | Idris 2 | Type-checked state machine (stub C codegen for ring 0) |
| Invariants | Agda | Offline proofs |

## Build

```sh
make modules KERNEL_SRC=/lib/modules/$(uname -r)/build
```

Vendor iwlwifi sources are fetched automatically from Linux v7.2 and patched in-place.

## Install and swap

```sh
sudo make modules_install install
sudo ./scripts/swap-iwchaos.sh
```

Restore stock iwlwifi:

```sh
sudo ./scripts/restore-iwlwifi.sh
```

`modprobe.d/iwchaos.conf` blacklists `iwlwifi` and `iwlmvm` and redirects them to `iwchaos`.

## Verify

```sh
lsmod | grep -E 'iwchaos|iwlwifi'
dmesg | grep iwchaos | tail
ls /sys/class/leds/phy*-led   # ThinkPad WiFi LED
```

## Checks

```sh
make check
```

## Crate

Publish or depend on the userspace library:

```sh
cd iwchaos-chaos && cargo test
```
