# iwchaos

`iwchaos` builds target-kernel-compatible Intel Wi-Fi modules and adds a small,
bounded fixed-point rate-policy advisory to the upstream MVM rate scaler. The
transport, firmware protocol, mac80211 integration, power management, and
recovery paths remain the Linux `iwlwifi` implementation.

The resulting driver modules keep their upstream names: `iwlwifi.ko`,
`iwlmvm.ko`, and `iwldvm.ko`. A small `iwchaos_policy.ko` helper exports the
policy bridge used by `iwlmvm`. All four are installed below `updates/iwchaos`,
so normal `modprobe` dependency handling and kernel fallback behavior continue
to work. The project does not replace Intel firmware and does not blacklist or
alias the distribution driver.

## Target-kernel build

Install matching kernel development files, then run:

```sh
make modules \
  KERNEL_SRC=/lib/modules/$(uname -r)/build \
  KERNELRELEASE=$(uname -r)
```

Source selection is per target kernel:

1. A complete iwlwifi tree in `KERNEL_SRC`, if available.
2. `IWCHAOS_IWLWIFI_SOURCE`, when supplied.
3. The matching upstream Linux tag (`vX.Y.Z`) from `IWCHAOS_LINUX_REPO`.

For downstream kernels with source changes, provide the matching source tree or
set `IWCHAOS_LINUX_REF` explicitly. `IWCHAOS_MODE=auto` falls back to stock
iwlwifi source when the rate-scaler layout has no safe integration point;
`IWCHAOS_MODE=strict` fails instead, which is useful for CI; `stock` disables
the policy integration.

The kernel policy is a freestanding Rust static library. It uses bounded integer
state only: no allocation, floating point, external runtime, or kernel ABI
assumptions are required from Rust. The C bridge serializes policy access with a
kernel spinlock and leaves the stock rate accounting authoritative.

## DKMS

The DKMS recipe builds separately for every installed kernel and fetches only
the target kernel's iwlwifi source when the kernel-devel package contains no
full source tree:

```sh
sudo dkms add -m iwchaos -v 0.2.0
sudo dkms install -m iwchaos -v 0.2.0 -k "$(uname -r)"
sudo depmod -a "$(uname -r)"
```

After installing a newer kernel, DKMS autoinstall rebuilds the same four
modules for that kernel. To remove this version and return to the distribution
modules:

```sh
sudo dkms remove -m iwchaos -v 0.2.0 --all
sudo depmod -a
```

Do not unload the active Wi-Fi stack over an important connection. Rebooting is
the safest way to activate a newly installed module set.

## Tests and crates

```sh
make check             # chaos-math, iwchaos-chaos, and optional Fortran tests
make verify            # target-kernel module build and static checks
cargo test --manifest-path chaos-math/Cargo.toml --locked
cargo test --manifest-path iwchaos-chaos/Cargo.toml --locked
```

The publishable user-space crates are `chaos-math` and `iwchaos-chaos`. The
`rust/` crate is an internal static library and is intentionally not published.

## Scope

This tree follows the kernel source API available to the selected build. A
downstream kernel can carry changes beyond its base version, so `strict` mode
must be used when a build must prove that the policy hook was applied. If the
layout is incompatible, `auto` produces the ordinary target-kernel iwlwifi
modules rather than applying an unsafe text transformation.
