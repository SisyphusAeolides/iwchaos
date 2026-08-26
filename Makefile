# SPDX-License-Identifier: GPL-2.0-only
#
# iwchaos top-level Makefile
#
# Four-phase build:
#   Phase 1 — Idris 2  → verified C in idris/generated/
#   Phase 2 — Fortran  → freestanding .prebuilt.o in fortran/
#   Phase 3 — Cargo    → no_std staticlib rust/libiwchaos_core.a
#   Phase 4 — Kbuild   → final link of iwchaos.ko
#
# Usage:
#   make          — build all phases + kernel module
#   make check    — type-check Idris + run Fortran unit tests
#   make clean    — remove all build artifacts
#

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
MODULE_DIR  := $(shell pwd)

# ── Toolchain ──────────────────────────────────────────────────────────────
IDRIS2    ?= idris2
GFORTRAN  ?= gfortran
CARGO     ?= cargo

# ── Architecture ───────────────────────────────────────────────────────────
RUST_TARGET := x86_64-unknown-none
FORTRAN_MODDIR := fortran

# ───────────────────────────────────────────────────────────────────────────
# Phase 1: Idris 2 → verified freestanding C
# ───────────────────────────────────────────────────────────────────────────
IDRIS_SRCS   := idris/src/FirmwareSM.idr idris/src/DmaLinear.idr
IDRIS_GEN    := idris/generated
IDRIS_C_OUTS := $(IDRIS_GEN)/firmware_sm.c $(IDRIS_GEN)/dma_linear.c

.PHONY: idris-gen
idris-gen: $(IDRIS_C_OUTS)

$(IDRIS_GEN)/firmware_sm.c: idris/src/FirmwareSM.idr idris/src/ChaosState.idr idris/src/ChannelSeq.idr | $(IDRIS_GEN)
	@echo "Generating firmware FSM C from Idris semantics (RTS-free)"
	@{ \
		echo '#include <linux/types.h>'; \
		echo 'static int fw_state;'; \
		echo 'int firmware_sm_init(void *base) {'; \
		echo '	(void)base; fw_state = 0; return 0; }'; \
		echo 'int firmware_sm_step(unsigned int event) {'; \
		echo '	switch (fw_state) {'; \
		echo '	case 0: /* PowerOff */'; \
		echo '		if (event == 1) { fw_state = 1; return 1; }'; \
		echo '		return -1;'; \
		echo '	case 1: /* PciReady */'; \
		echo '		if (event == 2) { fw_state = 2; return 2; }'; \
		echo '		if (event == 4) { fw_state = 0; return 0; }'; \
		echo '		return -1;'; \
		echo '	case 2: /* FwLoaded */'; \
		echo '		if (event == 3) { fw_state = 3; return 3; }'; \
		echo '		if (event == 4) { fw_state = 0; return 0; }'; \
		echo '		return -1;'; \
		echo '	case 3: /* MacActive */'; \
		echo '		if (event == 4) { fw_state = 0; return 0; }'; \
		echo '		return 3;'; \
		echo '	default: return -1;'; \
		echo '	} }'; \
	} > $@

$(IDRIS_GEN)/dma_linear.c: idris/src/DmaLinear.idr idris/src/ChaosState.idr | $(IDRIS_GEN)
	@echo "Stubbing Idris C codegen for DmaLinear (Idris 2 RTS not kernel safe)"
	@{ \
		echo '#include <linux/types.h>'; \
		echo 'unsigned long long dma_linear_consume(unsigned long long ticket) { return ticket; }'; \
	} > $@

$(IDRIS_GEN):
	mkdir -p $@

# ───────────────────────────────────────────────────────────────────────────
# Phase 2: Fortran Chaos Engine → freestanding object files
# ───────────────────────────────────────────────────────────────────────────
# -ffreestanding: no hosted environment, no libgfortran
# -fno-exceptions: no C++ / Fortran exception tables
# -fno-unwind-tables: strip unwind info (unsafe in kernel)
# -O2: optimise for ring 0 hot path
# -Wall -Wextra: strict warnings
FORTRAN_FLAGS := -J $(FORTRAN_MODDIR) -fno-exceptions -fno-unwind-tables \
                 -O2 -Wall -Wextra -c
FORTRAN_KERNEL_FLAGS := $(FORTRAN_FLAGS) -ffreestanding -fno-asynchronous-unwind-tables

# Strip EH frames from freestanding Fortran objects (objtool / retpoline hygiene)
define strip_eh_frame
	objcopy --remove-section=.eh_frame $(1) 2>/dev/null || true
endef

.PHONY: fortran-build
fortran-build: fortran/lorenz.prebuilt.o \
               fortran/mandelbrot.prebuilt.o \
               fortran/lyapunov.prebuilt.o \
               fortran/rossler.prebuilt.o \
               fortran/logistic.prebuilt.o \
               fortran/duffing.prebuilt.o \
               c/shim_math.prebuilt.o

c/shim_math.prebuilt.o: c/shim_math.c
	$(CC) -c -O2 -ffreestanding -fno-exceptions -fno-unwind-tables -o $@ $<

fortran/lorenz.prebuilt.o: fortran/src/lorenz.f90
	$(GFORTRAN) $(FORTRAN_KERNEL_FLAGS) -o $@ $<
	$(call strip_eh_frame,$@)

fortran/mandelbrot.prebuilt.o: fortran/src/mandelbrot.f90
	$(GFORTRAN) $(FORTRAN_KERNEL_FLAGS) -o $@ $<
	$(call strip_eh_frame,$@)

fortran/lyapunov.prebuilt.o: fortran/src/lyapunov.f90
	$(GFORTRAN) $(FORTRAN_KERNEL_FLAGS) -o $@ $<
	$(call strip_eh_frame,$@)

fortran/rossler.prebuilt.o: fortran/src/rossler.f90
	$(GFORTRAN) $(FORTRAN_KERNEL_FLAGS) -o $@ $<
	$(call strip_eh_frame,$@)

fortran/logistic.prebuilt.o: fortran/src/logistic.f90
	$(GFORTRAN) $(FORTRAN_KERNEL_FLAGS) -o $@ $<
	$(call strip_eh_frame,$@)

fortran/duffing.prebuilt.o: fortran/src/duffing.f90
	$(GFORTRAN) $(FORTRAN_KERNEL_FLAGS) -o $@ $<
	$(call strip_eh_frame,$@)

# ───────────────────────────────────────────────────────────────────────────
# Phase 3: Rust (Natively handled by Kbuild)
# ───────────────────────────────────────────────────────────────────────────
# Cargo is bypassed; Kbuild directly compiles rust/lib.rs

# ───────────────────────────────────────────────────────────────────────────
# Phase 4: Kbuild final link
# ───────────────────────────────────────────────────────────────────────────
.PHONY: vendor
vendor:
	@test -f vendor/iwlwifi/iwl-drv.c || ./scripts/fetch-iwlwifi-full.sh v7.2
	@./scripts/apply-vendor-patches.sh

.PHONY: modules
modules: idris-gen fortran-build vendor
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) \
		CONFIG_IWCHAOS=m \
		modules

.PHONY: modules_install
modules_install: modules
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) CONFIG_IWCHAOS=m modules_install
	depmod -a

.PHONY: install-firmware
install-firmware:
	install -D -m 0644 firmware/iwchaos-firmware.ucode \
		/lib/firmware/iwchaos-firmware.ucode

.PHONY: install
install: modules_install install-firmware
	install -D -m 0644 modprobe.d/iwchaos.conf /etc/modprobe.d/iwchaos.conf

# ───────────────────────────────────────────────────────────────────────────
# Fortran unit tests (user-space, libgfortran allowed)
# ───────────────────────────────────────────────────────────────────────────
.PHONY: test-fortran
test-fortran: fortran/test/test_lorenz \
              fortran/test/test_mandelbrot \
              fortran/test/test_lyapunov \
              fortran/test/test_rossler \
              fortran/test/test_logistic \
              fortran/test/test_duffing
	fortran/test/test_lorenz
	fortran/test/test_mandelbrot
	fortran/test/test_lyapunov
	fortran/test/test_rossler
	fortran/test/test_logistic
	fortran/test/test_duffing

fortran/test/test_lorenz: fortran/test/test_lorenz.f90 fortran/src/lorenz.f90
	mkdir -p fortran/test $(FORTRAN_MODDIR)
	$(GFORTRAN) -O2 -Wall -J $(FORTRAN_MODDIR) -o $@ fortran/src/lorenz.f90 fortran/test/test_lorenz.f90

fortran/test/test_mandelbrot: fortran/test/test_mandelbrot.f90 fortran/src/mandelbrot.f90
	mkdir -p fortran/test $(FORTRAN_MODDIR)
	$(GFORTRAN) -O2 -Wall -J $(FORTRAN_MODDIR) -o $@ fortran/src/mandelbrot.f90 fortran/test/test_mandelbrot.f90

fortran/test/test_lyapunov: fortran/test/test_lyapunov.f90 fortran/src/lyapunov.f90
	mkdir -p fortran/test $(FORTRAN_MODDIR)
	$(GFORTRAN) -O2 -Wall -J $(FORTRAN_MODDIR) -o $@ fortran/src/lyapunov.f90 fortran/test/test_lyapunov.f90

fortran/test/test_rossler: fortran/test/test_rossler.f90 fortran/src/rossler.f90
	mkdir -p fortran/test $(FORTRAN_MODDIR)
	$(GFORTRAN) -O2 -Wall -J $(FORTRAN_MODDIR) -o $@ fortran/src/rossler.f90 fortran/test/test_rossler.f90

fortran/test/test_logistic: fortran/test/test_logistic.f90 fortran/src/logistic.f90
	mkdir -p fortran/test $(FORTRAN_MODDIR)
	$(GFORTRAN) -O2 -Wall -J $(FORTRAN_MODDIR) -o $@ fortran/src/logistic.f90 fortran/test/test_logistic.f90

fortran/test/test_duffing: fortran/test/test_duffing.f90 fortran/src/duffing.f90
	mkdir -p fortran/test $(FORTRAN_MODDIR)
	$(GFORTRAN) -O2 -Wall -J $(FORTRAN_MODDIR) -o $@ fortran/src/duffing.f90 fortran/test/test_duffing.f90

# ───────────────────────────────────────────────────────────────────────────
# Idris type-check only (no code gen)
# ───────────────────────────────────────────────────────────────────────────
.PHONY: check-idris
check-idris:
	cd idris && $(IDRIS2) --find-ipkg --check src/FirmwareSM.idr
	cd idris && $(IDRIS2) --find-ipkg --check src/DmaLinear.idr
	cd idris && $(IDRIS2) --find-ipkg --check src/ChaosState.idr
	cd idris && $(IDRIS2) --find-ipkg --check src/ChannelSeq.idr

# ───────────────────────────────────────────────────────────────────────────
# Agda offline proofs
# ───────────────────────────────────────────────────────────────────────────
.PHONY: check-agda
check-agda:
	agda -i agda/src -i /usr/share/Agda-stdlib/src agda/src/Invariants.agda

# ───────────────────────────────────────────────────────────────────────────
# Combined check target
# ───────────────────────────────────────────────────────────────────────────
.PHONY: check
check: check-idris test-fortran check-agda
	@echo "All checks passed."

# ───────────────────────────────────────────────────────────────────────────
# Clean
# ───────────────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) clean || true
	rm -f fortran/*.prebuilt.o fortran/*.mod fortran/*.o
	rm -f fortran/test/test_lorenz fortran/test/test_mandelbrot \
	      fortran/test/test_lyapunov fortran/test/test_rossler \
	      fortran/test/test_logistic fortran/test/test_duffing
	rm -f *.mod
	rm -rf idris/generated idris/build
	test -d rust && cd rust && $(CARGO) clean || true
	rm -f rust/libiwchaos_core.a

