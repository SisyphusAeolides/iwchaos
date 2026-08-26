#!/usr/bin/env bash
# Remove in-tree iwlwifi/iwlmvm and load iwchaos (console session recommended).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

echo "Building iwchaos..."
make -C "$ROOT" modules 2>&1 | tail -5
make -C "$ROOT" modules_install
install -D -m 0644 "$ROOT/modprobe.d/iwchaos.conf" /etc/modprobe.d/iwchaos.conf
depmod -a

echo "Taking WiFi down..."
nmcli radio wifi off 2>/dev/null || true
for dev in /sys/class/net/wl*; do
	[[ -e "$dev" ]] && ip link set "$(basename "$dev")" down 2>/dev/null || true
done
sleep 2

echo "Removing in-tree stack..."
modprobe -r iwlmvm 2>/dev/null || true
modprobe -r iwlwifi 2>/dev/null || true
modprobe -r iwchaos 2>/dev/null || true
sleep 1

if lsmod | grep -qE '^(iwlwifi|iwlmvm) '; then
	echo "ERROR: iwlwifi/iwlmvm still loaded" >&2
	exit 1
fi

echo "Loading iwchaos..."
if ! modprobe iwchaos; then
	echo "ERROR: iwchaos failed — restoring iwlwifi" >&2
	rm -f /etc/modprobe.d/iwchaos.conf
	depmod -a
	modprobe iwlwifi || true
	exit 1
fi

sleep 6
if ! grep -q '^iwchaos ' /proc/modules; then
	echo "ERROR: iwchaos not in lsmod" >&2
	dmesg | tail -15
	exit 1
fi
if grep -qE '^(iwlwifi|iwlmvm) ' /proc/modules; then
	echo "ERROR: in-tree modules crept back in" >&2
	exit 1
fi

nmcli radio wifi on 2>/dev/null || true
sleep 2

echo ""
echo "=== Driver status ==="
lsmod | grep -E 'iwchaos|iwlwifi|iwlmvm|mac80211|cfg80211'
echo ""
echo "=== dmesg (iwchaos) ==="
dmesg | grep -iE 'iwchaos|iwlmvm opmode|PCI transport|AX200|firmware version' | tail -10
echo ""
echo "=== Interface ==="
ip link show 2>/dev/null | grep -E 'wl|state' || true
echo ""
echo "=== WiFi LED (if present) ==="
ls -d /sys/class/leds/*wlp* /sys/class/leds/*phy* 2>/dev/null | head -5 || echo "(no LED sysfs yet — appears after association)"
