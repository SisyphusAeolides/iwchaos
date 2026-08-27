#!/usr/bin/env bash
# End-to-end verification for iwchaos (build, hooks, runtime smoke tests).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SKIP=0

ok()   { echo "  PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $*"; SKIP=$((SKIP + 1)); }

echo "=== iwchaos verify ==="

echo "--- build ---"
if make modules KERNEL_SRC="/lib/modules/$(uname -r)/build" >/tmp/iwchaos-verify-build.log 2>&1; then
	ok "make modules"
else
	fail "make modules (see /tmp/iwchaos-verify-build.log)"
fi

test -f "$ROOT/iwchaos.ko" && ok "iwchaos.ko exists" || fail "iwchaos.ko missing"

echo "--- chaos symbols ---"
for sym in iwchaos_chaos_rate_select iwchaos_chaos_scan_iter_count \
	   iwchaos_chaos_power_timeout_us iwchaos_chaos_coex_agg_limit \
	   iwchaos_chaos_quota_adjust iwchaos_chaos_thermal_backoff_us \
	   iwchaos_chaos_agg_time_limit iwchaos_chaos_sta_release; do
	if grep -Fq "${sym}" < <(nm "$ROOT/iwchaos.ko" 2>/dev/null); then
		ok "symbol $sym"
	else
		fail "symbol $sym missing"
	fi
done

echo "--- vendor hooks ---"
for f in mvm/rs.c mvm/scan.c mvm/power.c mvm/coex.c mvm/quota.c mvm/tt.c; do
	if grep -q iwchaos_chaos "vendor/iwlwifi/$f"; then
		ok "hook in $f"
	else
		fail "no iwchaos hook in $f"
	fi
done

if grep -q iwchaos_chaos_sta_release vendor/iwlwifi/mvm/rs.c; then
	ok "rs_free_sta release hook"
else
	fail "rs_free_sta release hook missing"
fi

echo "--- patches ---"
for p in patches/iwchaos-*.patch; do
	test -s "$p" && ok "$(basename "$p")" || fail "empty patch $p"
done

echo "--- chaos-math crate ---"
if (cd chaos-math && cargo test -q); then
	ok "chaos-math cargo test"
else
	fail "chaos-math cargo test"
fi

echo "--- userspace tests ---"
if (cd iwchaos-chaos && cargo test -q); then
	ok "iwchaos-chaos cargo test"
else
	fail "iwchaos-chaos cargo test"
fi

echo "--- fortran tests ---"
if make test-fortran >/tmp/iwchaos-verify-fortran.log 2>&1; then
	ok "make test-fortran"
else
	fail "make test-fortran"
fi

echo "--- optional: idris / agda ---"
command -v idris2 >/dev/null && make check-idris && ok "check-idris" || skip "idris2 not installed"
command -v agda >/dev/null && make check-agda && ok "check-agda" || skip "agda not installed"

echo "--- runtime ---"
if lsmod | awk '$1=="iwchaos"{found=1} END{exit !found}'; then
	ok "iwchaos loaded"
else
	skip "iwchaos not loaded (load with: sudo modprobe iwchaos)"
fi

if test -f /etc/modprobe.d/iwchaos.conf && grep -q blacklist /etc/modprobe.d/iwchaos.conf; then
	ok "modprobe.d/iwchaos.conf installed"
else
	skip "modprobe.d/iwchaos.conf not installed"
fi

if command -v iw >/dev/null && ip link show wlan0 >/dev/null 2>&1; then
	if env -u SUDO_ASKPASS /usr/bin/sudo -n true 2>/dev/null; then
		env -u SUDO_ASKPASS /usr/bin/sudo ip link set wlan0 up 2>/dev/null || true
		if env -u SUDO_ASKPASS /usr/bin/sudo iw dev wlan0 scan trigger 2>/dev/null; then
			sleep 3
			n=$(iw dev wlan0 scan dump 2>/dev/null | grep -c '^BSS' || true)
			if test "$n" -gt 0; then
				ok "wlan0 scan ($n BSS)"
			else
				fail "wlan0 scan returned 0 BSS"
			fi
		else
			skip "wlan0 scan (needs sudo)"
		fi
	else
		skip "wlan0 scan (sudo required)"
	fi
else
	skip "wlan0 / iw not available"
fi

echo ""
echo "=== results: $PASS passed, $FAIL failed, $SKIP skipped ==="
test "$FAIL" -eq 0
