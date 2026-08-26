#!/usr/bin/env bash
# Fetch iwlwifi headers + mvm sources from Linux v6.12 for out-of-tree build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-v7.2}"
BASE="https://raw.githubusercontent.com/torvalds/linux/${REF}"
VENDOR="${ROOT}/vendor/iwlwifi"
MVM="${VENDOR}/mvm"

mkdir -p "${MVM}"

echo "Fetching iwlwifi tree (${REF})..."
mapfile -t PATHS < <(curl -sL "https://api.github.com/repos/torvalds/linux/git/trees/${REF}?recursive=1" \
	| python3 -c "
import sys, json
d = json.load(sys.stdin)
for t in d['tree']:
    p = t['path']
    if not p.startswith('drivers/net/wireless/intel/iwlwifi/'):
        continue
    if '/tests/' in p or p.endswith('/tests'):
        continue
    if p.endswith('.h') or (('/mvm/' in p or '/fw/' in p or '/pcie/' in p or '/cfg/' in p) and p.endswith('.c')):
        if '/mvm/' in p and p.endswith('.c'):
            pass
        elif p.endswith('.h'):
            pass
        elif '/fw/' in p and p.endswith('.c'):
            pass
        else:
            continue
    if p.endswith('.h'):
        print(p)
for t in d['tree']:
    p = t['path']
    if p.startswith('drivers/net/wireless/intel/iwlwifi/mvm/') and p.endswith('.c') and '/tests/' not in p:
        print(p)
")

for p in "${PATHS[@]}"; do
    rel="${p#drivers/net/wireless/intel/iwlwifi/}"
    dest="${VENDOR}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    if [[ ! -f "${dest}" ]]; then
        curl -sL "${BASE}/${p}" -o "${dest}"
    fi
done

# mvm needs all .c in mvm/
mapfile -t MVM_C < <(curl -sL "https://api.github.com/repos/torvalds/linux/contents/drivers/net/wireless/intel/iwlwifi/mvm?ref=${REF}" \
	| python3 -c "import sys,json; [print(x['name']) for x in json.load(sys.stdin) if x['name'].endswith('.c')]")

for f in "${MVM_C[@]}"; do
    dest="${MVM}/${f}"
    [[ -f "${dest}" ]] || curl -sL "${BASE}/drivers/net/wireless/intel/iwlwifi/mvm/${f}" -o "${dest}"
done

# Essential iwlwifi .c stubs referenced by headers (drv not needed for mvm-only)
for f in iwl-io.c iwl-debug.c iwl-drv.c iwl-nvm-utils.c iwl-phy-db.c iwl-nvm-parse.c \
         iwl-dbg-tlv.c iwl-trans.c fw/img.c fw/notif-wait.c fw/rs.c fw/dbg.c fw/pnvm.c \
         fw/dump.c fw/regulatory.c fw/paging.c fw/smem.c fw/init.c; do
    dest="${VENDOR}/${f}"
    mkdir -p "$(dirname "${dest}")"
    [[ -f "${dest}" ]] && continue
    curl -sL "${BASE}/drivers/net/wireless/intel/iwlwifi/${f}" -o "${dest}" 2>/dev/null || true
done

echo "Vendor tree ready under ${VENDOR}"
find "${VENDOR}" -name '*.c' | wc -l
find "${VENDOR}" -name '*.h' | wc -l
