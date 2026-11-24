#!/usr/bin/env bash
# Builds and installs the Gill-OSaab desktop (gosaab-wm + shell) into the image.
# Usage: install.sh <path to the shell/ folder>   (run as root during the image build)
set -euo pipefail
SRC=${1:-$(dirname "$(readlink -f "$0")")}
BUILD_DEPS="gcc make meson ninja-build pkgconf wayland-devel wayland-protocols-devel wlroots-devel scenefx-devel
  libxkbcommon-devel pixman-devel pango-devel cairo-devel libdrm-devel libinput-devel git-core mesa-libEGL-devel mesa-libgbm-devel libglvnd-devel"
dnf -y install $BUILD_DEPS
sh "$SRC/compositor/fetch-scenefx.sh"
meson setup /tmp/gosaab-wm-build "$SRC/compositor" --prefix=/usr --buildtype=release
meson compile -C /tmp/gosaab-wm-build
meson test -C /tmp/gosaab-wm-build --print-errorlogs
meson install -C /tmp/gosaab-wm-build
rm -rf /tmp/gosaab-wm-build
# Build tools stay installed: removing gcc also removed 200 packages Wine needs.
/usr/bin/gosaab-wm -v # still runs without the build tools

# on-screen keyboard (wvkbd) for touch screens, if the distribution doesn't ship it
if ! command -v wvkbd-mobintl >/dev/null; then
  WVKBD_COMMIT=f7e9ea3a7565decd0d120861c1cb36a7b6836244 # v0.21, reviewed
  for try in 1 2 3; do
    rm -rf /tmp/wvkbd
    git clone -q https://github.com/jjsullivan5196/wvkbd /tmp/wvkbd && git -C /tmp/wvkbd checkout -q "$WVKBD_COMMIT" && break
    sleep $((try * 10))
  done
  make -C /tmp/wvkbd LAYOUT=mobintl wvkbd-mobintl
  install -m 0755 /tmp/wvkbd/wvkbd-mobintl /usr/bin/wvkbd-mobintl
  rm -rf /tmp/wvkbd
fi

# the shell UI (Quickshell config) -> `qs -c gill-osaab`
install -d /usr/share/gill-osaab/shell /etc/xdg/quickshell
cp -r "$SRC/quickshell/." /usr/share/gill-osaab/shell/
ln -sfn /usr/share/gill-osaab/shell /etc/xdg/quickshell/gill-osaab

# login screen theme
if [ -d "$SRC/sddm-theme" ]; then
  install -d /usr/share/sddm/themes/gill-osaab
  cp -rL "$SRC/sddm-theme/." /usr/share/sddm/themes/gill-osaab/  # -L: the touch keyboard is shared with the lock screen
fi
gosaab-wm -v
echo "Gill-OSaab desktop installed"
