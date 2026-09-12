# Maintainer: Kenny Glauner <SisyphusAeolides@pm.me>
pkgname=iwchaos
pkgver=0.2.4
pkgrel=6
_commit=HEAD
pkgdesc="Target-kernel Intel Wi-Fi modules with a bounded rate policy"
arch=('x86_64')
url="https://github.com/SisyphusAeolides/iwchaos"
license=('GPL-2.0-only')
depends=(
  'binutils'
  'curl'
  'dkms'
  'gcc'
  'git'
  'kmod'
  'make'
  'python'
  'rust'
)
makedepends=('git')
options=(!lto !debug)
source=("git+file://${PWD}#commit=${_commit}")
sha256sums=('SKIP')

prepare() {
  cd "$pkgname"
  mkdir -p vendor

  # The published package is built in an Arch container without installed
  # kernel trees.  Keep a source baseline in the package so DKMS does not
  # need network access during installation.  A local makepkg run also adds
  # the base version for every installed kernel.
  local bootstrap_base="${IWCHAOS_KERNEL_BASE:-7.2.4}"
  local -a kernel_bases=("$bootstrap_base")

  for kdir in /usr/lib/modules/*/build/Makefile; do
    [ -f "$kdir" ] || continue
    local kver=$(awk -F= -v key="VERSION" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$kdir")
    local kpatch=$(awk -F= -v key="PATCHLEVEL" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$kdir")
    local ksub=$(awk -F= -v key="SUBLEVEL" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$kdir")
    local KERNEL_BASE="${kver}.${kpatch}.${ksub}"
    [ -n "$KERNEL_BASE" ] && kernel_bases+=("$KERNEL_BASE")
  done

  local -A seen=()
  local KERNEL_BASE FETCH_ROOT
  for KERNEL_BASE in "${kernel_bases[@]}"; do
    [ -n "$KERNEL_BASE" ] || continue
    [ -z "${seen[$KERNEL_BASE]:-}" ] || continue
    seen["$KERNEL_BASE"]=1
    [ -d "vendor/iwlwifi-${KERNEL_BASE}" ] && continue

    FETCH_ROOT=$(mktemp -d "${PWD}/vendor/.iwlwifi-fetch.XXXXXX")
    echo "iwchaos: staging iwlwifi source v${KERNEL_BASE}"
    if ! git -c advice.detachedHead=false clone --filter=blob:none --no-checkout \
        --depth 1 --branch "v${KERNEL_BASE}" \
        https://github.com/gregkh/linux.git "${FETCH_ROOT}/linux"; then
      rm -rf -- "$FETCH_ROOT"
      error "could not fetch Linux tag v${KERNEL_BASE}; set IWCHAOS_KERNEL_BASE to an available tag or provide a local source tree"
    fi
    git -C "${FETCH_ROOT}/linux" sparse-checkout set drivers/net/wireless/intel/iwlwifi
    git -C "${FETCH_ROOT}/linux" checkout --quiet
    [ -f "${FETCH_ROOT}/linux/drivers/net/wireless/intel/iwlwifi/iwl-drv.c" ] || {
      rm -rf -- "$FETCH_ROOT"
      error "Linux tag v${KERNEL_BASE} has no iwlwifi source tree"
    }
    cp -a -- "${FETCH_ROOT}/linux/drivers/net/wireless/intel/iwlwifi" "vendor/iwlwifi-${KERNEL_BASE}"
    rm -rf -- "$FETCH_ROOT"
  done
}

build() {
  cd "$pkgname"
  make rust-build
}

package() {
  cd "$pkgname"
  local _dest="$pkgdir/usr/src/${pkgname}-${pkgver}"

  install -dm755 "$_dest"
  cp -a . "$_dest/"
  rm -rf "$_dest/.git" "$_dest/.github"
  rm -rf "$_dest/rust/target" "$_dest/rust/.ar-extract"
  find "$_dest" -type f \
    \( -name '*.o' ! -name 'libiwchaos_core.prebuilt.o' -o -name '*.ko' -o -name '*.cmd' -o -name '*.d' \) -delete
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
