#!/usr/bin/env bash
# Apply iwchaos patches to a freshly fetched vendor/iwlwifi tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHDIR="${ROOT}/patches"
VENDOR="${ROOT}/vendor/iwlwifi"

if [[ ! -d "${VENDOR}" ]]; then
	echo "vendor/iwlwifi missing — run scripts/fetch-iwlwifi-full.sh first" >&2
	exit 1
fi

for patch in "${PATCHDIR}"/iwchaos-*.patch; do
	[[ -s "${patch}" ]] || continue
	echo "Applying $(basename "${patch}")..."
	patch -p0 -d "${ROOT}" --forward --batch < "${patch}"
done

# mei headers (not in default fetch filter historically)
MEI="${VENDOR}/mei"
if [[ ! -f "${MEI}/iwl-mei.h" ]]; then
	mkdir -p "${MEI}"
	REF="${IWCHAOS_LINUX_REF:-v7.2}"
	BASE="https://raw.githubusercontent.com/torvalds/linux/${REF}"
	for f in iwl-mei.h internal.h sap.h trace.h trace-data.h; do
		curl -sL "${BASE}/drivers/net/wireless/intel/iwlwifi/mei/${f}" \
			-o "${MEI}/${f}"
	done
fi

echo "Vendor patches applied."
