#!/usr/bin/env bash
# Add the small, bounded policy hook to the target kernel's MVM rate scaler.
set -Eeuo pipefail

ROOT="${IWCHAOS_ROOT:?IWCHAOS_ROOT is required}"
SOURCE_DIR="${IWCHAOS_SOURCE_DIR:?IWCHAOS_SOURCE_DIR is required}"
MODE="${IWCHAOS_MODE:-auto}"
RS_FILE="${SOURCE_DIR}/mvm/rs.c"
MVM_MAKEFILE="${SOURCE_DIR}/mvm/Makefile"
SOURCE_MAKEFILE="${SOURCE_DIR}/Makefile"
STAMP="${SOURCE_DIR}/.iwchaos-integration"

die() {
	echo "iwchaos: $*" >&2
	exit 1
}

[[ -f "${MVM_MAKEFILE}" ]] || die "target source is missing mvm/Makefile"
[[ -f "${SOURCE_MAKEFILE}" ]] || die "target source is missing its top-level Makefile"
case "${MODE}" in
	auto|strict|stock) ;;
	*) die "IWCHAOS_MODE must be auto, strict, or stock" ;;
esac

HEADER="${ROOT}/include/iwchaos_chaos.h"
SHIM="${ROOT}/c/shim_chaos.c"
RUST_OBJECT="${ROOT}/rust/libiwchaos_core.prebuilt.o"

ensure_policy_module() {
	[[ -f "${HEADER}" ]] || die "missing ${HEADER}"
	[[ -f "${SHIM}" ]] || die "missing ${SHIM}"
	[[ -f "${RUST_OBJECT}" ]] || die "missing ${RUST_OBJECT}; run make rust-build first"

	install -m 0644 "${HEADER}" "${SOURCE_DIR}/iwchaos_chaos.h"
	install -m 0644 "${SHIM}" "${SOURCE_DIR}/iwchaos_core.c"
	install -m 0644 "${RUST_OBJECT}" "${SOURCE_DIR}/iwchaos_rust.o"

	# Remove entries produced by older revisions before adding the helper once.
	sed -i \
		-e '/^# iwchaos policy object; generated for this target kernel$/d' \
		-e '/^iwlmvm-y += iwchaos_core.o iwchaos_rust.o$/d' \
		-e '/^OBJECT_FILES_NON_STANDARD_iwchaos_rust.o := y$/d' \
		"${MVM_MAKEFILE}"
	if ! grep -q '^obj-m += iwchaos_policy.o$' "${SOURCE_MAKEFILE}"; then
		printf '%s\n' \
			'' \
			'# iwchaos policy helper; generated for this target kernel.' \
			'obj-m += iwchaos_policy.o' \
			'iwchaos_policy-y := iwchaos_core.o iwchaos_rust.o' \
			'OBJECT_FILES_NON_STANDARD_iwchaos_policy.o := y' >> "${SOURCE_MAKEFILE}"
	fi
	printf 'cmd_iwchaos_rust.o := true\nsavedcmd_iwchaos_rust.o := true\n' > \
		"${SOURCE_DIR}/.iwchaos_rust.o.cmd"
}

if [[ ! -f "${RS_FILE}" ]]; then
	if [[ "${MODE}" == strict ]]; then
		die "target source is missing mvm/rs.c"
	fi
	ensure_policy_module
	echo "iwchaos: no MVM rate source found; using stock MVM policy"
	printf 'mode=%s\nhooks=0\n' "${MODE}" > "${STAMP}"
	exit 0
fi

if [[ "${MODE}" == stock ]]; then
	ensure_policy_module
	echo "iwchaos: building the stock target-kernel iwlwifi modules"
	printf 'mode=stock\nhooks=0\n' > "${STAMP}"
	exit 0
fi

has_hook_point=1
grep -q 'static void rs_rate_scale_perform' "${RS_FILE}" || has_hook_point=0
grep -q '^lq_update:$' "${RS_FILE}" || has_hook_point=0
grep -q 'lq_sta->lq.sta_id' "${RS_FILE}" || has_hook_point=0

if [[ "${has_hook_point}" -eq 0 ]]; then
	if [[ "${MODE}" == strict ]]; then
		die "this kernel's MVM rate-scaler layout is unsupported; set IWCHAOS_IWLWIFI_SOURCE to matching source or use IWCHAOS_MODE=stock"
	fi
	ensure_policy_module
	echo "iwchaos: no compatible rate hook found; using stock MVM policy"
	printf 'mode=auto\nhooks=0\n' > "${STAMP}"
	exit 0
fi

if ! grep -q 'iwchaos_chaos.h' "${RS_FILE}"; then
	if grep -q '^#include "debugfs.h"' "${RS_FILE}"; then
		sed -i '/^#include "debugfs.h"/a #include "iwchaos_chaos.h"' "${RS_FILE}"
	elif grep -q '^#include "mvm.h"' "${RS_FILE}"; then
		sed -i '/^#include "mvm.h"/a #include "iwchaos_chaos.h"' "${RS_FILE}"
	elif [[ "${MODE}" == strict ]]; then
		die "the target MVM source has no safe include anchor"
	else
		ensure_policy_module
		echo "iwchaos: no safe MVM include anchor; using stock MVM policy"
		printf 'mode=auto\nhooks=0\n' > "${STAMP}"
		exit 0
	fi
fi

ensure_policy_module

if ! grep -q 'iwchaos: bounded rate hint' "${RS_FILE}"; then
	[[ "$(grep -c '^lq_update:$' "${RS_FILE}" || true)" -eq 1 ]] || \
		die "expected exactly one lq_update marker"
	perl -0pi -e 's/\nlq_update:\n/\n\t\/\* iwchaos: bounded rate hint; the stock rate scaler remains authoritative. \*\/\n\tif (update_lq)\n\t\tindex = iwchaos_chaos_rate_select(lq_sta->lq.sta_id,\n\t\t\t\t\t\t  index, low, high);\n\nlq_update:\n/' "${RS_FILE}"
fi

if grep -q 'mvmsta->deflink.sta_id' "${RS_FILE}" && \
	grep -q 'iwl_mvm_rs_tx_status(mvm, sta, rs_get_tid(hdr), info,' "${RS_FILE}" && \
	! grep -q 'iwchaos: tx feedback' "${RS_FILE}"; then
	perl -0pi -e 's/\n\tiwl_mvm_rs_tx_status\(mvm, sta, rs_get_tid\(hdr\), info,\n/\n\t\/\* iwchaos: tx feedback is advisory and never bypasses stock accounting. \*\/\n\tiwchaos_chaos_tx_feedback(mvmsta->deflink.sta_id,\n\t\t\t\t  !!(info->flags \& IEEE80211_TX_STAT_ACK),\n\t\t\t\t  mvmsta->deflink.lq_sta.rs_drv.pers.last_rssi);\n\n\tiwl_mvm_rs_tx_status(mvm, sta, rs_get_tid(hdr), info,\n/' "${RS_FILE}"
fi

if grep -q 'static void rs_free_sta' "${RS_FILE}" && \
	! grep -q 'iwchaos: release the per-station' "${RS_FILE}"; then
	grep -q 'IWL_DEBUG_RATE(mvm, "leave\\n");' "${RS_FILE}" || \
		die "rate-station cleanup marker not found"
	perl -0pi -e 's/\n\tIWL_DEBUG_RATE\(mvm, "leave\\n"\);\n/\n\t\/\* iwchaos: release the per-station policy state with the driver state. \*\/\n\tiwchaos_chaos_sta_release(\n\t\tiwl_mvm_sta_from_mac80211(sta)->deflink.sta_id);\n\n\tIWL_DEBUG_RATE(mvm, "leave\\n");\n/' "${RS_FILE}"
fi

printf 'mode=%s\nhooks=1\n' "${MODE}" > "${STAMP}"
echo "iwchaos: bounded rate hook enabled for ${SOURCE_DIR}"
