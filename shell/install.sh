#!/usr/bin/env bash
# Builds and installs the Gill-OSaab desktop (gosaab-wm + shell) into the image.
# Usage: install.sh <path to the shell/ folder>   (run as root during the image build)
set -euo pipefail
SRC=${1:-$(dirname "$(readlink -f "$0")")}
BUILD_DEPS="gcc meson ninja-build pkgconf wayland-devel wayland-protocols-devel wlroots-devel scenefx-devel
  libxkbcommon-devel pixman-devel pango-devel cairo-devel libdrm-devel"
dnf -y install $BUILD_DEPS
meson setup /tmp/gosaab-wm-build "$SRC/compositor" --prefix=/usr --buildtype=release
meson compile -C /tmp/gosaab-wm-build
meson test -C /tmp/gosaab-wm-build --print-errorlogs
meson install -C /tmp/gosaab-wm-build
rm -rf /tmp/gosaab-wm-build
# keep the image small: the compiler and build tools go again. The -devel packages stay
# (they are tiny, and removing them would also remove the runtime libraries they pulled in).
dnf mark user scenefx wlroots pango cairo libdrm libxkbcommon pixman >/dev/null 2>&1 || true
dnf -y remove gcc meson ninja-build || true
/usr/bin/gosaab-wm -v # still runs without the build tools

# the shell UI (Quickshell config) -> `qs -c gill-osaab`
install -d /usr/share/gill-osaab/shell /etc/xdg/quickshell
cp -r "$SRC/quickshell/." /usr/share/gill-osaab/shell/
ln -sfn /usr/share/gill-osaab/shell /etc/xdg/quickshell/gill-osaab

# login screen theme
if [ -d "$SRC/sddm-theme" ]; then
  install -d /usr/share/sddm/themes/gill-osaab
  cp -r "$SRC/sddm-theme/." /usr/share/sddm/themes/gill-osaab/
fi
gosaab-wm -v
echo "Gill-OSaab desktop installed"
