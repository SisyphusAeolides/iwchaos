# SPDX-License-Identifier: GPL-2.0-only
#
# Target-kernel build for iwchaos.
#
# The Intel driver is built as the normal iwlwifi/iwlmvm/iwldvm modules.  The
# source is selected for the kernel being built, so one DKMS registration can
# be rebuilt for multiple kernels without carrying a stale vendor tree.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
KERNELRELEASE ?= $(shell make -s -C "$(KERNEL_SRC)" kernelversion 2>/dev/null)
IWCHAOS_SOURCE_DIR := $(ROOT)/vendor/iwlwifi-$(KERNELRELEASE)

export RUSTUP_TOOLCHAIN ?= stable
CARGO ?= cargo
AR ?= ar
LD ?= ld
RUST_DIR := $(ROOT)/rust
RUST_ARCHIVE := $(RUST_DIR)/target/release/libiwchaos_core.a
RUST_PREBUILT := $(RUST_DIR)/libiwchaos_core.prebuilt.o

.PHONY: all prepare-source rust-build integrate modules modules_install \
	install-firmware install check test-fortran verify clean

all: modules

prepare-source:
	KERNEL_SRC="$(KERNEL_SRC)" \
	KERNELRELEASE="$(KERNELRELEASE)" \
	IWCHAOS_SOURCE_DIR="$(IWCHAOS_SOURCE_DIR)" \
	IWCHAOS_LINUX_REF="$(IWCHAOS_LINUX_REF)" \
	IWCHAOS_IWLWIFI_SOURCE="$(IWCHAOS_IWLWIFI_SOURCE)" \
	IWCHAOS_MODE="$(IWCHAOS_MODE)" \
	./scripts/prepare-source.sh

$(RUST_ARCHIVE): $(RUST_DIR)/src/lib.rs $(RUST_DIR)/Cargo.toml
	cd "$(RUST_DIR)" && \
	RUSTC_WRAPPER= \
	RUSTFLAGS='-C panic=abort -C code-model=kernel -C relocation-model=static -C debuginfo=0 -C force-frame-pointers=yes -C no-redzone=yes' \
	$(CARGO) build --locked --release

$(RUST_PREBUILT): $(RUST_ARCHIVE)
	rm -rf "$(RUST_DIR)/.ar-extract"
	mkdir -p "$(RUST_DIR)/.ar-extract"
	cd "$(RUST_DIR)/.ar-extract" && "$(AR)" x "$(RUST_ARCHIVE)"
	"$(LD)" -r -o "$@" "$(RUST_DIR)"/.ar-extract/iwchaos_core*.rcgu.o
	objcopy --remove-section=.eh_frame "$@" 2>/dev/null || true
	objcopy --remove-section=.comment --remove-section=.note \
		--remove-section=.llvmbc --remove-section=.llvmcmd \
		--strip-debug "$@" 2>/dev/null || true
	rm -rf "$(RUST_DIR)/.ar-extract"

rust-build: $(RUST_PREBUILT)

integrate: prepare-source rust-build
	KERNEL_SRC="$(KERNEL_SRC)" \
	KERNELRELEASE="$(KERNELRELEASE)" \
	IWCHAOS_SOURCE_DIR="$(IWCHAOS_SOURCE_DIR)" \
	IWCHAOS_ROOT="$(ROOT)" \
	IWCHAOS_MODE="$(IWCHAOS_MODE)" \
	./scripts/integrate-chaos.sh

modules: integrate
	$(MAKE) -C "$(KERNEL_SRC)" M="$(IWCHAOS_SOURCE_DIR)" \
		CONFIG_IWLWIFI=m \
		CONFIG_IWLMVM=m \
		CONFIG_IWLDVM=m \
		CONFIG_IWLWIFI_KUNIT_TESTS=n \
		CONFIG_DEBUG_INFO_BTF_MODULES=n \
		modules
	@test -f "$(IWCHAOS_SOURCE_DIR)/iwlwifi.ko"
	@test -f "$(IWCHAOS_SOURCE_DIR)/mvm/iwlmvm.ko"
	install -m 0644 "$(IWCHAOS_SOURCE_DIR)/iwlwifi.ko" "$(ROOT)/iwlwifi.ko"
	install -m 0644 "$(IWCHAOS_SOURCE_DIR)/mvm/iwlmvm.ko" "$(ROOT)/iwlmvm.ko"
	@test -f "$(IWCHAOS_SOURCE_DIR)/dvm/iwldvm.ko"
	install -m 0644 "$(IWCHAOS_SOURCE_DIR)/dvm/iwldvm.ko" "$(ROOT)/iwldvm.ko"
	@test -f "$(IWCHAOS_SOURCE_DIR)/iwchaos_policy.ko"
	install -m 0644 "$(IWCHAOS_SOURCE_DIR)/iwchaos_policy.ko" "$(ROOT)/iwchaos_policy.ko"

modules_install: modules
	$(MAKE) -C "$(KERNEL_SRC)" M="$(IWCHAOS_SOURCE_DIR)" \
		INSTALL_MOD_DIR=updates/iwchaos modules_install
	depmod -a "$(KERNELRELEASE)"

install-firmware:
	@echo "iwchaos uses the distribution Intel firmware package; no replacement firmware is installed."

install: modules_install install-firmware

check:
	cd chaos-math && RUSTC_WRAPPER= $(CARGO) test --locked
	cd iwchaos-chaos && RUSTC_WRAPPER= $(CARGO) test --locked
	@if command -v gfortran >/dev/null 2>&1; then $(MAKE) test-fortran; else echo "SKIP: gfortran not installed"; fi

test-fortran:
	@set -e; \
	for name in lorenz mandelbrot lyapunov rossler logistic duffing; do \
		$(MAKE) "fortran/test/test_$${name}"; \
		"fortran/test/test_$${name}"; \
		done

GFORTRAN ?= gfortran

fortran/test/test_%: fortran/test/test_%.f90 fortran/src/%.f90
	mkdir -p fortran/test fortran
	$(GFORTRAN) -O2 -Wall -J fortran -o "$@" "fortran/src/$*.f90" "$<"

verify:
	./scripts/verify.sh

clean:
	@if test -d "$(IWCHAOS_SOURCE_DIR)"; then \
		$(MAKE) -C "$(KERNEL_SRC)" M="$(IWCHAOS_SOURCE_DIR)" clean || true; \
	fi
	rm -f iwlwifi.ko iwlmvm.ko iwldvm.ko iwchaos_policy.ko
	rm -f "$(RUST_PREBUILT)"
	rm -rf "$(RUST_DIR)/target" "$(RUST_DIR)/.ar-extract"
	case "$(IWCHAOS_SOURCE_DIR)" in \
		"$(ROOT)"/vendor/iwlwifi-*) rm -rf -- "$(IWCHAOS_SOURCE_DIR)" ;; \
	esac
