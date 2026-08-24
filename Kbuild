# SPDX-License-Identifier: GPL-2.0-only
#
# iwchaos Kbuild — multi-language Ring 0 Intel Wi-Fi driver
#
# Build order:
#   1. Idris 2  → verified C (idris/generated/)
#   2. Fortran  → freestanding .o (fortran/*.o)
#   3. Cargo    → no_std staticlib (rust/libiwchaos_core.a)
#   4. Kbuild   → final link to iwchaos.ko
#

obj-$(CONFIG_IWCHAOS) += iwchaos.o

# ── C shim objects (mac80211, cfg80211, PCIe, rate control, channel) ─────
iwchaos-objs := c/shim_mac80211.o \
                c/shim_cfg80211.o \
                c/shim_pci.o \
                c/shim_rate_control.o \
                c/shim_channel.o \
                c/shim_math.prebuilt.o

# ── Idris 2 generated C (verified firmware state machine + DMA allocator) ─
iwchaos-objs += idris/generated/firmware_sm.o \
                idris/generated/dma_linear.o

# ── Rust core (PCIe, DMA ring buffers, chaos API, Netlink) ──────
# Compiled natively by Kbuild RFL integration
iwchaos-objs += iwchaos_rust.o

# ── Fortran Chaos Engine (freestanding, no libgfortran) ───────────────────
# Fortran .o files are prebuilt before Kbuild and named with .prebuilt.o
# to prevent Kbuild from trying to compile them as C.
iwchaos-objs += fortran/lorenz.prebuilt.o \
                fortran/mandelbrot.prebuilt.o \
                fortran/lyapunov.prebuilt.o \
                fortran/rossler.prebuilt.o \
                fortran/logistic.prebuilt.o \
                fortran/duffing.prebuilt.o

# ── Include paths ─────────────────────────────────────────────────────────
ccflags-y := -I$(src)/include
