# iwchaos

Drop-in replacement for Linux `iwlwifi` + `iwlmvm` on Intel AX200/AX201, with a
chaos-theory rate-control layer. C is limited to module entry, FPU-guarded ABI
shims, and the vendored Intel transport.

## Stack

| Layer | Language | Role |
|---|---|---|
| Module entry + FPU guards | C (thin) | `module_init`, `kernel_fpu_*`, chaos ABI |
| Intel transport + MVM | C (vendored) | PCIe, firmware, mac80211, LEDs |
| Chaos policy + numerics | Rust (`rust/` staticlib) | Per-sta rate control, attractors, SNR feedback |
| Chaos numerics (userspace) | Rust crate [`iwchaos-chaos`](iwchaos-chaos/) | Simulation / tests |
| Fortran (offline only) | Fortran | `make test-fortran` unit tests |
| Firmware FSM | Idris 2 | Type-checked state machine (stub C for ring 0) |
| Invariants | Agda | Offline proofs |

## Build

```sh
make modules KERNEL_SRC=/lib/modules/$(uname -r)/build
```

Vendor iwlwifi sources are fetched automatically (Linux v7.2) and patched in-place.
Rust is built as a freestanding `x86_64-unknown-none` staticlib (no `CONFIG_RUST` required).

## DKMS

```sh
sudo dkms remove iwchaos/0.1.0 --all || true
sudo rsync -a --delete --exclude='.git' --exclude='vendor' ./ /usr/src/iwchaos-0.1.0/
# vendor is large; either copy it or let the build fetch:
sudo cp -a vendor /usr/src/iwchaos-0.1.0/ 2>/dev/null || true
sudo dkms add -m iwchaos -v 0.1.0
sudo dkms install -m iwchaos -v 0.1.0 -k $(uname -r)
```

Or from the AUR-style package in Sisyphus-Repo: `sudo pacman -S iwchaos`.

## Install and swap

```sh
sudo make modules_install install
sudo ./scripts/swap-iwchaos.sh
```

Restore stock iwlwifi:

```sh
sudo ./scripts/restore-iwlwifi.sh
```

`modprobe.d/iwchaos.conf` blacklists `iwlwifi` / `iwlmvm` and redirects them to `iwchaos`.

## Verify

```sh
make verify          # build + hooks + tests + runtime smoke (needs sudo for scan)
make check           # userspace + fortran tests (idris/agda if installed)
lsmod | grep -E 'iwchaos|iwlwifi'
dmesg | grep iwchaos | tail
```
