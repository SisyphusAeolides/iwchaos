# SPDX-License-Identifier: GPL-2.0-only

obj-$(CONFIG_IWCHAOS) += iwchaos.o

# --- Rust core (compiled via Cargo/RFL, linked as a prebuilt .o) ---
iwchaos-objs := rust/iwchaos_rust.o

# --- C shims: mac80211 / cfg80211 ABI bridge ---
iwchaos-objs += c/shim_mac80211.o \
                c/shim_cfg80211.o \
                c/shim_pci.o

# --- Idris 2 generated C (verified firmware state machine) ---
iwchaos-objs += idris/generated/firmware_sm.o \
                idris/generated/dma_linear.o

# --- Fortran Chaos Engine (freestanding, no libgfortran) ---
iwchaos-objs += fortran/lorenz.o \
                fortran/mandelbrot.o

# Pass Fortran objects through the linker without standard lib injection
KBUILD_EXTRA_SYMBOLS := $(obj)/fortran/Module.symvers

ccflags-y := -I$(src)/include
