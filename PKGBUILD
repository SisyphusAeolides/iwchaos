# Maintainer: Kenny Glauner <SisyphusAeolides@pm.me>
pkgname=iwchaos
pkgver=0.2.4
pkgrel=1
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
  
  for kdir in /usr/lib/modules/*/build/Makefile; do
    [ -f "$kdir" ] || continue
    local kver=$(awk -F= -v key="VERSION" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$kdir")
    local kpatch=$(awk -F= -v key="PATCHLEVEL" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$kdir")
    local ksub=$(awk -F= -v key="SUBLEVEL" '$1 ~ "^" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$kdir")
    local KERNEL_BASE="${kver}.${kpatch}.${ksub}"
    
    if [ ! -d "vendor/iwlwifi-${KERNEL_BASE}" ]; then
      local FETCH_ROOT=$(mktemp -d "${PWD}/vendor/.iwlwifi-fetch.XXXXXX")
      if git -c advice.detachedHead=false clone --filter=blob:none --no-checkout \
          --depth 1 --branch "v${KERNEL_BASE}" https://github.com/gregkh/linux.git "${FETCH_ROOT}/linux"; then
        git -C "${FETCH_ROOT}/linux" sparse-checkout set drivers/net/wireless/intel/iwlwifi
        git -C "${FETCH_ROOT}/linux" checkout --quiet
        cp -a -- "${FETCH_ROOT}/linux/drivers/net/wireless/intel/iwlwifi" "vendor/iwlwifi-${KERNEL_BASE}"
      fi
      rm -rf "${FETCH_ROOT}"
    fi
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
