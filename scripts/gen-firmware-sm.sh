#!/usr/bin/env bash
# Emit kernel-safe firmware FSM C from idris/src/FirmwareSM.idr semantics.
set -euo pipefail
OUT="${1:?output .c path}"
mkdir -p "$(dirname "$OUT")"
cat >"$OUT" <<'EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/* Generated from idris/src/FirmwareSM.idr (RTS-free, kernel safe). */
#include <linux/types.h>

enum firmware_sm_state {
	FW_SM_POWER_OFF = 0,
	FW_SM_PCI_READY = 1,
	FW_SM_FW_LOADED = 2,
	FW_SM_MAC_ACTIVE = 3,
	FW_SM_ERROR = 4,
};

enum firmware_sm_event {
	FW_EVT_CLAIM_PCI = 1,
	FW_EVT_LOAD_FW = 2,
	FW_EVT_START_MAC = 3,
	FW_EVT_RESET = 4,
};

static int fw_state;

int firmware_sm_init(void *base)
{
	(void)base;
	fw_state = FW_SM_POWER_OFF;
	return 0;
}

int firmware_sm_state(void)
{
	return fw_state;
}

int firmware_sm_reset(void)
{
	switch (fw_state) {
	case FW_SM_POWER_OFF:
		return FW_SM_POWER_OFF;
	default:
		fw_state = FW_SM_POWER_OFF;
		return FW_SM_POWER_OFF;
	}
}

int firmware_sm_step(unsigned int event)
{
	switch (fw_state) {
	case FW_SM_POWER_OFF:
		if (event == FW_EVT_CLAIM_PCI) {
			fw_state = FW_SM_PCI_READY;
			return FW_SM_PCI_READY;
		}
		fw_state = FW_SM_ERROR;
		return -1;
	case FW_SM_PCI_READY:
		if (event == FW_EVT_LOAD_FW) {
			fw_state = FW_SM_FW_LOADED;
			return FW_SM_FW_LOADED;
		}
		if (event == FW_EVT_RESET)
			return firmware_sm_reset();
		fw_state = FW_SM_ERROR;
		return -1;
	case FW_SM_FW_LOADED:
		if (event == FW_EVT_START_MAC) {
			fw_state = FW_SM_MAC_ACTIVE;
			return FW_SM_MAC_ACTIVE;
		}
		if (event == FW_EVT_RESET)
			return firmware_sm_reset();
		fw_state = FW_SM_ERROR;
		return -1;
	case FW_SM_MAC_ACTIVE:
		if (event == FW_EVT_RESET)
			return firmware_sm_reset();
		return FW_SM_MAC_ACTIVE;
	case FW_SM_ERROR:
		return firmware_sm_reset();
	default:
		fw_state = FW_SM_ERROR;
		return -1;
	}
}
EOF
