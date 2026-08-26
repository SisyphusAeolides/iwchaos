#!/usr/bin/env bash
# Restore Fedora in-tree iwlwifi + iwlmvm.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

nmcli radio wifi off 2>/dev/null || true
for dev in /sys/class/net/wl*; do
	[[ -e "$dev" ]] && ip link set "$(basename "$dev")" down 2>/dev/null || true
done
sleep 1

modprobe -r iwchaos 2>/dev/null || true
rm -f /etc/modprobe.d/iwchaos.conf
depmod -a
sleep 1

modprobe iwlwifi
sleep 2
modprobe iwlmvm 2>/dev/null || true

nmcli radio wifi on 2>/dev/null || true
echo "Restored in-tree iwlwifi:"
lsmod | grep -E 'iwl|mac80211|cfg80211'
