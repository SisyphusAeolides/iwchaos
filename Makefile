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

# ───────────────────────────────────────────────────────────────────────────
# Phase 1: Idris 2 → verified freestanding C
# ───────────────────────────────────────────────────────────────────────────
IDRIS_SRCS   := idris/src/FirmwareSM.idr idris/src/DmaLinear.idr
IDRIS_GEN    := idris/generated
IDRIS_C_OUTS := $(IDRIS_GEN)/firmware_sm.c $(IDRIS_GEN)/dma_linear.c

.PHONY: idris-gen
idris-gen: $(IDRIS_C_OUTS)

$(IDRIS_GEN)/firmware_sm.c: idris/src/FirmwareSM.idr idris/src/DmaLinear.idr | $(IDRIS_GEN)
	cd idris && $(IDRIS2) --codegen C --output-dir generated src/FirmwareSM.idr
	test -f $@ || mv $(IDRIS_GEN)/FirmwareSM.c $@ 2>/dev/null || true

$(IDRIS_GEN)/dma_linear.c: idris/src/FirmwareSM.idr idris/src/DmaLinear.idr | $(IDRIS_GEN)
	cd idris && $(IDRIS2) --codegen C --output-dir generated src/DmaLinear.idr
	test -f $@ || mv $(IDRIS_GEN)/DmaLinear.c $@ 2>/dev/null || true

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
FORTRAN_FLAGS := -ffreestanding -fno-exceptions -fno-unwind-tables \
                 -O2 -Wall -Wextra -c

.PHONY: fortran-build
fortran-build: fortran/lorenz.prebuilt.o fortran/mandelbrot.prebuilt.o

fortran/lorenz.prebuilt.o: fortran/src/lorenz.f90
	$(GFORTRAN) $(FORTRAN_FLAGS) -o $@ $<

fortran/mandelbrot.prebuilt.o: fortran/src/mandelbrot.f90
	$(GFORTRAN) $(FORTRAN_FLAGS) -o $@ $<

# ───────────────────────────────────────────────────────────────────────────
# Phase 3: Rust no_std staticlib via Cargo
# ───────────────────────────────────────────────────────────────────────────
RUST_OUT := rust/target/$(RUST_TARGET)/release/libiwchaos_core.a
RUST_DEST := rust/libiwchaos_core.a

.PHONY: rust-build
rust-build: $(RUST_DEST)

$(RUST_DEST): rust/src/lib.rs rust/Cargo.toml
	cd rust && \
	RUSTFLAGS="-C panic=abort" \
	$(CARGO) +nightly build --release \
		--target $(RUST_TARGET) \
		-Z build-std=core \
		-Z build-std-features=
	cp $(RUST_OUT) $(RUST_DEST)

# ───────────────────────────────────────────────────────────────────────────
# Phase 4: Kbuild final link
# ───────────────────────────────────────────────────────────────────────────
.PHONY: modules
modules: idris-gen fortran-build rust-build
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) \
		KBUILD_EXTRA_SYMBOLS=$(MODULE_DIR)/Module.symvers \
		modules

.PHONY: modules_install
modules_install: modules
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) modules_install
	depmod -a

# ───────────────────────────────────────────────────────────────────────────
# Fortran unit tests (user-space, libgfortran allowed)
# ───────────────────────────────────────────────────────────────────────────
.PHONY: test-fortran
test-fortran: fortran/test/test_lorenz fortran/test/test_mandelbrot
	fortran/test/test_lorenz
	fortran/test/test_mandelbrot

fortran/test/test_lorenz: fortran/test/test_lorenz.f90 fortran/src/lorenz.f90
	mkdir -p fortran/test
	$(GFORTRAN) -O2 -Wall -o $@ $^

fortran/test/test_mandelbrot: fortran/test/test_mandelbrot.f90 fortran/src/mandelbrot.f90
	mkdir -p fortran/test
	$(GFORTRAN) -O2 -Wall -o $@ $^

# ───────────────────────────────────────────────────────────────────────────
# Idris type-check only (no code gen)
# ───────────────────────────────────────────────────────────────────────────
.PHONY: check-idris
check-idris:
	cd idris && $(IDRIS2) --check src/FirmwareSM.idr
	cd idris && $(IDRIS2) --check src/DmaLinear.idr

# ───────────────────────────────────────────────────────────────────────────
# Agda offline proofs
# ───────────────────────────────────────────────────────────────────────────
.PHONY: check-agda
check-agda:
	agda agda/src/Invariants.agda

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
	rm -f fortran/*.prebuilt.o
	rm -f fortran/test/test_lorenz fortran/test/test_mandelbrot
	rm -rf idris/generated idris/build
	cd rust && $(CARGO) clean || true
	rm -f rust/libiwchaos_core.a
