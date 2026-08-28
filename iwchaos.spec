Name:           iwchaos
Version:        0.1.0
Release:        1%{?dist}
Summary:        Drop-in replacement for Linux iwlwifi + iwlmvm with chaos-theory rate-control layer

License:        GPL-2.0-only
URL:            https://github.com/SisyphusAeolides/iwchaos
VCS:            {{{ git_dir_vcs }}}
Source:         {{{ git_dir_pack }}}

BuildRequires:  rsync
Requires:       dkms
Requires:       rust
Requires:       cargo
Requires:       idris2
Requires:       gcc
Requires:       make
Requires:       rsync
Requires:       wget
Requires:       kernel-devel
Requires:       clang
Requires:       llvm

BuildArch:      noarch

%description
Drop-in replacement for Linux iwlwifi + iwlmvm on Intel AX200/AX201, with a
chaos-theory rate-control layer.

%prep
{{{ git_dir_setup_macro }}}

%build

%install
mkdir -p %{buildroot}/usr/src/%{name}-%{version}
rsync -a --exclude='.git' . %{buildroot}/usr/src/%{name}-%{version}/

# Install firmware
mkdir -p %{buildroot}/lib/firmware
install -m 0644 firmware/iwchaos-firmware.ucode %{buildroot}/lib/firmware/

# Install modprobe.d
mkdir -p %{buildroot}/etc/modprobe.d
install -m 0644 modprobe.d/iwchaos.conf %{buildroot}/etc/modprobe.d/

%post
dkms add -m %{name} -v %{version} --rpm_safe_upgrade || :
dkms build -m %{name} -v %{version} || :
dkms install -m %{name} -v %{version} || :

%preun
dkms remove -m %{name} -v %{version} --all --rpm_safe_upgrade || :

%files
/usr/src/%{name}-%{version}/
/lib/firmware/iwchaos-firmware.ucode
/etc/modprobe.d/iwchaos.conf

%changelog
* Thu Aug 27 2026 Sisyphus Aeolides <SisyphusAeolides@pm.me> - 0.1.0-1
- Initial release
