#!/usr/bin/env bash
# Fetch complete iwlwifi + mvm tree from Linux for out-of-tree iwchaos build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-v7.2}"
BASE="https://raw.githubusercontent.com/torvalds/linux/${REF}"
VENDOR="${ROOT}/vendor/iwlwifi"

echo "Fetching complete iwlwifi tree (${REF})..."
rm -rf "${VENDOR}"
mkdir -p "${VENDOR}"

mapfile -t PATHS < <(curl -sL "https://api.github.com/repos/torvalds/linux/git/trees/${REF}?recursive=1" \
	| python3 -c "
import sys, json
d = json.load(sys.stdin)
skip = ('/tests/', '/kunit/', '/dvm/', '/mld/', '/mei/')
for t in d['tree']:
    p = t['path']
    if not p.startswith('drivers/net/wireless/intel/iwlwifi/'):
        continue
    if any(s in p for s in skip):
        continue
    if p.endswith('.c') or p.endswith('.h'):
        print(p)
")

total=${#PATHS[@]}
i=0
for p in "${PATHS[@]}"; do
	i=$((i + 1))
	rel="${p#drivers/net/wireless/intel/iwlwifi/}"
	dest="${VENDOR}/${rel}"
	mkdir -p "$(dirname "${dest}")"
	curl -sL "${BASE}/${p}" -o "${dest}"
	if (( i % 50 == 0 )); then
		echo "  ${i}/${total}..."
	fi
done

echo "Vendor tree: $(find "${VENDOR}" -name '*.c' | wc -l) C files, $(find "${VENDOR}" -name '*.h' | wc -l) headers"
