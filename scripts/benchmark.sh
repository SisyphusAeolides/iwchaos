#!/usr/bin/env bash
# Smoke benchmarks for iwchaos: scan latency, BSS count, tick_gen delta.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IFACE="${IWCHAOS_IFACE:-wlan0}"
RUNS="${IWCHAOS_BENCH_RUNS:-3}"
SUDO="env -u SUDO_ASKPASS /usr/bin/sudo"
SUDO_PW="${SUDO_PASSWORD:-}"

sudo_cmd() {
	if $SUDO -n true 2>/dev/null; then
		$SUDO "$@"
	elif [[ -n "$SUDO_PW" ]]; then
		printf '%s\n' "$SUDO_PW" | $SUDO -S "$@"
	else
		echo "benchmark: sudo required (set SUDO_PASSWORD or configure passwordless sudo)" >&2
		exit 1
	fi
}

usage() {
	cat <<'EOF'
Usage: scripts/benchmark.sh [--stock]

  --stock   restore iwlwifi, benchmark, then swap back to iwchaos (if installed)

Env:
  IWCHAOS_IFACE      interface (default: wlan0)
  IWCHAOS_BENCH_RUNS scan iterations (default: 3)
  SUDO_PASSWORD      passed to sudo -S when needed
EOF
}

driver_name() {
	if lsmod | awk '$1=="iwchaos"{found=1} END{exit !found}'; then
		echo "iwchaos"
	elif lsmod | awk '$1=="iwlwifi"{found=1} END{exit !found}'; then
		echo "iwlwifi"
	else
		echo "none"
	fi
}

tick_gen() {
	local path="/sys/module/iwchaos/parameters/tick_gen"
	if [[ -r "$path" ]]; then
		tr -dc '0-9' <"$path"
	else
		echo 0
	fi
}

scan_once() {
	local start end elapsed n
	start=$(date +%s%N)
	sudo_cmd ip link set "$IFACE" up 2>/dev/null || true
	sudo_cmd iw dev "$IFACE" scan trigger
	sleep 3
	end=$(date +%s%N)
	elapsed=$(( (end - start) / 1000000 ))
	n=$(iw dev "$IFACE" scan dump 2>/dev/null | grep -c '^BSS' || true)
	echo "$elapsed $n"
}

maybe_sudo() {
	sudo_cmd true
}

STOCK=0
if [[ "${1:-}" == "--stock" ]]; then
	STOCK=1
elif [[ -n "${1:-}" ]]; then
	usage
	exit 1
fi

maybe_sudo

RESTORE_IWCHAOS=0
if [[ "$STOCK" -eq 1 ]]; then
	if [[ -x /usr/bin/iwchaos-restore ]]; then
		echo "=== benchmarking stock iwlwifi ==="
		/usr/bin/iwchaos-restore
		RESTORE_IWCHAOS=1
	elif [[ -x "$ROOT/scripts/restore-iwlwifi.sh" ]]; then
		echo "=== benchmarking stock iwlwifi ==="
		"$ROOT/scripts/restore-iwlwifi.sh"
		RESTORE_IWCHAOS=1
	else
		echo "benchmark: --stock requires iwchaos-restore" >&2
		exit 1
	fi
	sleep 2
fi

DRV=$(driver_name)
echo "=== iwchaos benchmark (driver: $DRV, iface: $IFACE, runs: $RUNS) ==="

if ! ip link show "$IFACE" >/dev/null 2>&1; then
	echo "benchmark: $IFACE not found" >&2
	exit 1
fi

TG0=$(tick_gen)
TOTAL_MS=0
TOTAL_BSS=0
for i in $(seq 1 "$RUNS"); do
	read -r ms bss < <(scan_once)
	echo "  run $i: ${ms}ms, ${bss} BSS"
	TOTAL_MS=$((TOTAL_MS + ms))
	TOTAL_BSS=$((TOTAL_BSS + bss))
done
TG1=$(tick_gen)

AVG_MS=$((TOTAL_MS / RUNS))
AVG_BSS=$((TOTAL_BSS / RUNS))
echo ""
echo "average scan: ${AVG_MS}ms, ${AVG_BSS} BSS"
if [[ "$TG0" =~ ^[0-9]+$ && "$TG1" =~ ^[0-9]+$ && "$TG0" != "$TG1" ]]; then
	echo "tick_gen: $TG0 -> $TG1 (delta $((TG1 - TG0)))"
fi

if [[ "$RESTORE_IWCHAOS" -eq 1 ]]; then
	echo ""
	echo "=== restoring iwchaos ==="
	if [[ -x /usr/bin/iwchaos-swap ]]; then
		/usr/bin/iwchaos-swap
	elif [[ -x "$ROOT/scripts/swap-iwchaos.sh" ]]; then
		"$ROOT/scripts/swap-iwchaos.sh"
	fi
fi
