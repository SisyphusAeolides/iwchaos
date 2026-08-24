# SPDX-License-Identifier: GPL-2.0-only
#
# iwchaos top-level Makefile
# Four-phase build: Idris2 → Fortran → Rust/bindgen → Kbuild final link
#

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
MODULE_DIR  := $(shell pwd)

# ── Toolchain ──────────────────────────────────────────────────────────────────
IDRIS2    := idris2
GFORTRAN  := gfortran
CARGO     := cargo

# ── Phase 1: Idris 2 → verified C ─────────────────────────────────────────────
IDRIS_SRCS := idris/src/FirmwareSM.idr idris/src/DmaLinear.idr
IDRIS_OUT  := idris/generated

.PHONY: idris-gen
idris-gen: $(IDRIS_OUT)/firmware_sm.c $(IDRIS_OUT)/dma_linear.c

$(IDRIS_OUT)/firmware_sm.c: idris/src/FirmwareSM.idr | $(IDRIS_OUT)
	$(IDRIS2) --codegen C --output-dir $(IDRIS_OUT) $<
	mv $(IDRIS_OUT)/FirmwareSM.c $@

$(IDRIS_OUT)/dma_linear.c: idris/src/DmaLinear.idr | $(IDRIS_OUT)
	$(IDRIS2) --codegen C --output-dir $(IDRIS_OUT) $<
	mv $(IDRIS_OUT)/DmaLinear.c $@

$(IDRIS_OUT):
	mkdir -p $@

# ── Phase 2: Fortran Chaos Engine → freestanding .o ───────────────────────────
FORTRAN_FLAGS := -ffreestanding -fno-exceptions -O2 -Wall -c

.PHONY: fortran-build
fortran-build: fortran/lorenz.o fortran/mandelbrot.o

fortran/lorenz.o: fortran/src/lorenz.f90
	$(GFORTRAN) $(FORTRAN_FLAGS) -o $@ $<

fortran/mandelbrot.o: fortran/src/mandelbrot.f90
	$(GFORTRAN) $(FORTRAN_FLAGS) -o $@ $<

# ── Phase 3: Rust core → prebuilt .o via Cargo (RFL mode) ────────────────────
.PHONY: rust-build
rust-build:
	$(CARGO) build --release --manifest-path rust/Cargo.toml \
		-Z build-std=core,alloc \
		--target x86_64-unknown-none
	cp rust/target/x86_64-unknown-none/release/libiwchaos_rust.a \
		rust/iwchaos_rust.o

# ── Phase 4: Kbuild final link ────────────────────────────────────────────────
.PHONY: modules
modules: idris-gen fortran-build rust-build
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) modules

.PHONY: modules_install
modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) modules_install

.PHONY: clean
clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) clean
	rm -f fortran/lorenz.o fortran/mandelbrot.o
	rm -rf idris/generated
	$(CARGO) clean --manifest-path rust/Cargo.toml
