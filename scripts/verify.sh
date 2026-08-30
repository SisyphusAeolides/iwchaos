#!/usr/bin/env bash
# Build and statically verify the target-kernel module set.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:-/lib/modules/$(uname -r)/build}"
KERNELRELEASE="${KERNELRELEASE:-$(make -s -C "$KERNEL_SRC" kernelversion)}"
MODE="${IWCHAOS_VERIFY_MODE:-strict}"
LOG="$(mktemp "${TMPDIR:-/tmp}/iwchaos-verify.XXXXXX.log")"
trap 'rm -f "$LOG"' EXIT

die() {
	echo "iwchaos verify: $*" >&2
	echo "See $LOG" >&2
	exit 1
}

cd "$ROOT"
echo "=== iwchaos verify ==="
echo "kernel: $KERNELRELEASE"
echo "source: $KERNEL_SRC"
echo "mode:   $MODE"

if ! make modules KERNEL_SRC="$KERNEL_SRC" KERNELRELEASE="$KERNELRELEASE" \
	IWCHAOS_MODE="$MODE" >"$LOG" 2>&1; then
	cat "$LOG" >&2
	die "target-kernel module build failed"
fi

source_dir="$ROOT/vendor/iwlwifi-$KERNELRELEASE"
for module in iwlwifi iwlmvm iwldvm iwchaos_policy; do
	artifact="$ROOT/$module.ko"
	test -s "$artifact" || die "missing $artifact"
	done

test ! -e "$ROOT/iwchaos.ko" || die "obsolete monolithic iwchaos.ko was produced"
test -s "$source_dir/.iwchaos-source" || die "source selection stamp missing"
test -s "$source_dir/.iwchaos-integration" || die "integration stamp missing"

if [[ "$MODE" == strict ]]; then
	grep -q 'iwchaos_chaos_rate_select' "$source_dir/mvm/rs.c" || \
		die "rate policy hook missing from the target source"
	grep -q '^iwchaos_policy-y := iwchaos_core.o iwchaos_rust.o$' "$source_dir/Makefile" || \
		die "policy objects missing from the helper build"
fi

for symbol in iwchaos_chaos_rate_select iwchaos_chaos_tx_feedback iwchaos_chaos_sta_release; do
	nm -g "$ROOT/iwchaos_policy.ko" | grep -q " $symbol$" || \
		die "symbol $symbol missing from iwchaos_policy.ko"
	done

for script in scripts/*.sh; do
	bash -n "$script" || die "shell syntax error in $script"
	done

make check >>"$LOG" 2>&1 || {
	cat "$LOG" >&2
	die "userspace or ancillary tests failed"
}

echo "PASS: target-kernel modules, integration, symbols, shell syntax, and tests"
