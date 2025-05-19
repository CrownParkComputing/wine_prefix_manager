Name:           wine_prefix_manager
Version:        3.0.0
Release:        1%{?dist}
Summary:        Wine Prefix Manager for Linux gaming
License:        MIT
URL:            https://github.com/jon/wine_prefix_manager
Source0:        %{name}-%{version}.tar.gz
Requires:       wine zenity

%description
A Flutter application to create and manage Wine prefixes for running
Windows games and applications on Linux.

%prep
%setup -q

%install
mkdir -p %{buildroot}/usr/lib/%{name}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/512x512/apps

cp -r . %{buildroot}/usr/lib/%{name}/

# Create launcher script
echo '#!/bin/sh' > %{buildroot}/usr/bin/%{name}
echo 'exec /usr/lib/%{name}/%{name} "$@"' >> %{buildroot}/usr/bin/%{name}
chmod +x %{buildroot}/usr/bin/%{name}

# Copy desktop file and icon
cp %{_sourcedir}/../../../%{name}.desktop %{buildroot}/usr/share/applications/
cp %{_sourcedir}/../../../assets/icons/winehero.jpg %{buildroot}/usr/share/icons/hicolor/512x512/apps/%{name}.jpg

%files
%{_bindir}/%{name}
/usr/lib/%{name}/
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/512x512/apps/%{name}.jpg

%changelog
* Mon May 19 2025 Builder <builder@example.com> - 3.0.0-1
- Automatic build
