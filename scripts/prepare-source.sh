#!/usr/bin/env bash
# Select an iwlwifi source tree for the kernel DKMS is building.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:?KERNEL_SRC is required}"
KERNELRELEASE="${KERNELRELEASE:?KERNELRELEASE is required}"
SOURCE_DIR="${IWCHAOS_SOURCE_DIR:?IWCHAOS_SOURCE_DIR is required}"
MODE="${IWCHAOS_MODE:-auto}"
LINUX_REPO="${IWCHAOS_LINUX_REPO:-https://github.com/gregkh/linux.git}"

die() {
	echo "iwchaos: $*" >&2
	exit 1
}

[[ -d "${KERNEL_SRC}" ]] || die "kernel build directory does not exist: ${KERNEL_SRC}"
[[ -f "${KERNEL_SRC}/Makefile" ]] || die "kernel build directory has no Makefile: ${KERNEL_SRC}"
case "${MODE}" in
	auto|strict|stock) ;;
	*) die "IWCHAOS_MODE must be auto, strict, or stock" ;;
esac

read_kernel_field() {
	awk -F= -v key="$1" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' \
		"${KERNEL_SRC}/Makefile"
}

KERNEL_BASE="$(read_kernel_field VERSION).$(read_kernel_field PATCHLEVEL).$(read_kernel_field SUBLEVEL)"
[[ "${KERNEL_BASE}" != ".." ]] || die "could not determine kernel version from ${KERNEL_SRC}/Makefile"
LINUX_REF="${IWCHAOS_LINUX_REF:-v${KERNEL_BASE}}"

if [[ -f "${SOURCE_DIR}/.iwchaos-source" ]]; then
	# A packaged ArachOS build may carry the exact source tree selected for the
	# bootstrap kernel.  The stamp is authoritative for that pre-staged tree;
	# it may name a stable upstream tag even when the kernel's full release has
	# a distribution suffix.  Requiring the kernel field prevents that source
	# from being reused for a different target kernel.
	if grep -qx "kernel=${KERNELRELEASE}" "${SOURCE_DIR}/.iwchaos-source" && \
	   test -f "${SOURCE_DIR}/iwl-drv.c" && \
	   test -f "${SOURCE_DIR}/mvm/Makefile"; then
		cached_ref=$(awk -F= '$1 == "ref" {print $2; exit}' \
			"${SOURCE_DIR}/.iwchaos-source")
		[[ -n "${cached_ref}" ]] || die "pre-staged source has no ref stamp"
		echo "iwchaos: using pre-staged iwlwifi source ${cached_ref} for ${KERNELRELEASE}"
		exit 0
	fi
fi

mkdir -p "${ROOT}/vendor"
STAGE_ROOT="$(mktemp -d "${ROOT}/vendor/.iwlwifi-stage.XXXXXX")"
FETCH_ROOT=""
cleanup() {
	if [[ -n "${FETCH_ROOT}" && -d "${FETCH_ROOT}" ]]; then
		rm -rf -- "${FETCH_ROOT}"
	fi
	if [[ -d "${STAGE_ROOT}" ]]; then
		rm -rf -- "${STAGE_ROOT}"
	fi
}
trap cleanup EXIT

IWL_SOURCE="${IWCHAOS_IWLWIFI_SOURCE:-}"
if [[ -z "${IWL_SOURCE}" && -f "${KERNEL_SRC}/drivers/net/wireless/intel/iwlwifi/iwl-drv.c" ]]; then
	IWL_SOURCE="${KERNEL_SRC}/drivers/net/wireless/intel/iwlwifi"
	LINUX_REF="kernel-tree"
fi
if [[ -z "${IWL_SOURCE}" && -d "${ROOT}/vendor/iwlwifi-${KERNEL_BASE}" ]]; then
	IWL_SOURCE="${ROOT}/vendor/iwlwifi-${KERNEL_BASE}"
	LINUX_REF="v${KERNEL_BASE}"
fi
if [[ -n "${IWL_SOURCE}" ]]; then
	if [[ -f "${IWL_SOURCE}/iwl-drv.c" ]]; then
		:
	elif [[ -f "${IWL_SOURCE}/iwlwifi/iwl-drv.c" ]]; then
		IWL_SOURCE="${IWL_SOURCE}/iwlwifi"
	else
		die "IWCHAOS_IWLWIFI_SOURCE is not an iwlwifi source directory: ${IWL_SOURCE}"
	fi
	echo "iwchaos: staging iwlwifi source from ${IWL_SOURCE}"
	cp -a -- "${IWL_SOURCE}" "${STAGE_ROOT}/iwlwifi"
else
	command -v git >/dev/null 2>&1 || die "git is required to fetch ${LINUX_REF}"
	FETCH_ROOT="$(mktemp -d "${ROOT}/vendor/.iwlwifi-fetch.XXXXXX")"
	echo "iwchaos: fetching iwlwifi source ${LINUX_REF}"
	if ! (for i in 1 2 3 4 5; do git -c advice.detachedHead=false clone --filter=blob:none --no-checkout \
		--depth 1 --branch "${LINUX_REF}" "${LINUX_REPO}" "${FETCH_ROOT}/linux" && break; sleep 2; rm -rf "${FETCH_ROOT}/linux"; done); then
		# Linux releases with a distribution patch suffix do not always publish
		# a matching three-component tag.  Try the stable minor tag when the
		# caller did not explicitly choose a reference.
		minor_ref="v${KERNEL_BASE%.*}"
		rm -rf -- "${FETCH_ROOT}/linux"
		if [[ -z "${IWCHAOS_LINUX_REF:-}" && "${minor_ref}" != "${LINUX_REF}" ]] && \
		   (for j in 1 2 3 4 5; do git -c advice.detachedHead=false clone --filter=blob:none --no-checkout \
			--depth 1 --branch "${minor_ref}" "${LINUX_REPO}" "${FETCH_ROOT}/linux" && break; sleep 2; rm -rf "${FETCH_ROOT}/linux"; done); then
			LINUX_REF="${minor_ref}"
		else
			die "kernel source tag ${LINUX_REF} was not found; set IWCHAOS_LINUX_REF or IWCHAOS_IWLWIFI_SOURCE"
		fi
	fi
	git -C "${FETCH_ROOT}/linux" sparse-checkout set drivers/net/wireless/intel/iwlwifi
	git -C "${FETCH_ROOT}/linux" checkout --quiet
	cp -a -- "${FETCH_ROOT}/linux/drivers/net/wireless/intel/iwlwifi" "${STAGE_ROOT}/iwlwifi"
fi

[[ -f "${STAGE_ROOT}/iwlwifi/iwl-drv.c" ]] || die "staged source is missing iwl-drv.c"
[[ -f "${STAGE_ROOT}/iwlwifi/Makefile" ]] || die "staged source is missing its Kbuild Makefile"
[[ -f "${STAGE_ROOT}/iwlwifi/mvm/Makefile" ]] || die "staged source is missing the MVM Kbuild Makefile"

printf 'ref=%s\nkernel=%s\nbase=%s\n' "${LINUX_REF}" "${KERNELRELEASE}" "${KERNEL_BASE}" \
	> "${STAGE_ROOT}/iwlwifi/.iwchaos-source"

if [[ -e "${SOURCE_DIR}" || -L "${SOURCE_DIR}" ]]; then
	BACKUP="${SOURCE_DIR}.previous.$$.${KERNELRELEASE}"
	echo "iwchaos: preserving previous source at ${BACKUP}"
	mv -- "${SOURCE_DIR}" "${BACKUP}"
fi
mkdir -p "$(dirname "${SOURCE_DIR}")"
mv -- "${STAGE_ROOT}/iwlwifi" "${SOURCE_DIR}"
echo "iwchaos: source ready at ${SOURCE_DIR}"
