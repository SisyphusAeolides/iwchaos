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

# ── C shim objects (mac80211, cfg80211, PCIe ABI bridge) ──────────────────
iwchaos-objs := c/shim_mac80211.o \
                c/shim_cfg80211.o \
                c/shim_pci.o

# ── Idris 2 generated C (verified firmware state machine + DMA allocator) ─
iwchaos-objs += idris/generated/firmware_sm.o \
                idris/generated/dma_linear.o

# ── Rust core staticlib (PCIe, DMA ring buffers, chaos API, Netlink) ──────
# Linked as a prebuilt archive; the Makefile runs Cargo before Kbuild.
IWCHAOS_RUST_LIB := $(src)/rust/libiwchaos_core.a
ldflags-y        += $(IWCHAOS_RUST_LIB)

# ── Fortran Chaos Engine (freestanding, no libgfortran) ───────────────────
# Fortran .o files are prebuilt before Kbuild and named with .prebuilt.o
# to prevent Kbuild from trying to compile them as C.
iwchaos-objs += fortran/lorenz.prebuilt.o \
                fortran/mandelbrot.prebuilt.o

# ── Include paths ─────────────────────────────────────────────────────────
ccflags-y := -I$(src)/include
