Name:           iwchaos
Version:        0.2.0
Release:        1%{?dist}
Summary:        Target-kernel Intel Wi-Fi modules with a bounded rate policy

License:        GPL-2.0-only
URL:            https://github.com/SisyphusAeolides/iwchaos
Source0:        https://github.com/SisyphusAeolides/iwchaos/archive/refs/tags/v%{version}.tar.gz

BuildRequires:  binutils
BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  git
BuildRequires:  make
BuildRequires:  python3
BuildRequires:  rust

Requires:       binutils
Requires:       cargo
Requires:       curl
Requires:       dkms
Requires:       gcc
Requires:       git
Requires:       make
Requires:       python3
Requires:       rust

BuildArch:      noarch

%description
Target-kernel-compatible Intel iwlwifi, iwlmvm, and iwldvm DKMS modules with a
small bounded fixed-point rate-policy advisory. The upstream transport and
firmware interface remain authoritative.

%prep
%autosetup -n %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/src/%{name}-%{version}
cp -a . %{buildroot}/usr/src/%{name}-%{version}/
rm -rf %{buildroot}/usr/src/%{name}-%{version}/.git
rm -rf %{buildroot}/usr/src/%{name}-%{version}/vendor
rm -rf %{buildroot}/usr/src/%{name}-%{version}/rust/target
rm -rf %{buildroot}/usr/src/%{name}-%{version}/rust/.ar-extract
find %{buildroot}/usr/src/%{name}-%{version} -type f \
  \( -name '*.o' -o -name '*.ko' -o -name '*.cmd' -o -name '*.d' \) -delete

%post
if command -v dkms >/dev/null 2>&1; then
  dkms add -m %{name} -v %{version} --rpm_safe_upgrade || :
  dkms autoinstall -m %{name} -v %{version} || :
fi

%preun
if [ "$1" -eq 0 ] && command -v dkms >/dev/null 2>&1; then
  dkms remove -m %{name} -v %{version} --all --rpm_safe_upgrade || :
fi

%files
/usr/src/%{name}-%{version}/
/usr/share/licenses/%{name}/LICENSE

%changelog
* Sat Aug 29 2026 Sisyphus Aeolides <SisyphusAeolides@pm.me> - 0.2.0-1
- Build target-kernel iwlwifi modules with DKMS
- Remove the monolithic replacement and fake firmware paths
