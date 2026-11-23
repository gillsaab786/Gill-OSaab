#!/usr/bin/env bash
# Inside the Gill-OSaab Core image: is everything there, and does the real session start?
set -u
OUT=${1:-/tmp/core-shots}
mkdir -p "$OUT"
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

for b in gosaab-wm gosaab-session gosaab-game-mode steamos-session-select qs swaybg xwayland-satellite \
         foot nautilus firefox gamescope steam sddm grim wine waydroid distrobox flatpak gosaab-settings gosaab-updates gosaab-emudeck gosaab-android-setup vlc wg; do
  check "installed: $b" "command -v $b >/dev/null"
done
echo "wine files: $(ls -d /usr/bin/wine* /etc/alternatives/wine* 2>/dev/null | tr "\n" " ")"
check "Windows apps: wine runs" "wine --version >/dev/null 2>&1"
check "Windows games: DXVK (DirectX on Vulkan) is the default" "rpm -q wine-dxvk >/dev/null 2>&1"
if [ -f /src/core-test/hello64.exe ]; then
  export WINEPREFIX=/tmp/wineprefix WINEDEBUG=-all
  wineboot -u >/dev/null 2>&1
  check "64-bit Windows app runs" "wine /src/core-test/hello64.exe 2>/dev/null | grep -q 'hello from 64-bit'"
  check "32-bit Windows app runs" "wine /src/core-test/hello32.exe 2>/dev/null | grep -q 'hello from 32-bit'"
fi
check "TDP/fans/buttons: Handheld Daemon installed" "command -v hhd >/dev/null"
check "frame generation layer installed (lsfg-vk)" "ls /usr/share/vulkan/implicit_layer.d/ 2>/dev/null | grep -qi lsfg"
check "Android folders service ready" "command -v bindfs >/dev/null && systemctl is-enabled gosaab-android-folders.service >/dev/null 2>&1"
check "start-up choice applied at boot" "systemctl is-enabled gosaab-boot-mode.service >/dev/null 2>&1"
/usr/libexec/gill-osaab/gosaab-session-select-root --boot root game
check "Settings: start in Game Mode" "grep -q 'Session=gill-osaab-gamemode.desktop' /etc/sddm.conf.d/zz-gill-osaab-autologin.conf"
/usr/libexec/gill-osaab/gosaab-session-select-root --boot root desktop
check "Settings: start in Desktop" "grep -q 'Session=gill-osaab.desktop' /etc/sddm.conf.d/zz-gill-osaab-autologin.conf"
/usr/libexec/gill-osaab/gosaab-session-select-root --boot root ask
check "Settings: ask at the login screen" "[ ! -e /etc/sddm.conf.d/zz-gill-osaab-autologin.conf ]"
check "shell config installed" "[ -f /etc/xdg/quickshell/gill-osaab/shell.qml ]"
check "login theme installed" "[ -f /usr/share/sddm/themes/gill-osaab/Main.qml ]"
check "desktop session listed" "[ -f /usr/share/wayland-sessions/gill-osaab.desktop ]"
check "Game Mode session listed" "[ -f /usr/share/wayland-sessions/gill-osaab-gamemode.desktop ]"
check "login screen uses our theme" "grep -q 'Current=gill-osaab' /etc/sddm.conf.d/10-gill-osaab.conf"
check "no KDE Plasma in Core" "! rpm -q plasma-workspace >/dev/null 2>&1"
check "wallpaper present" "[ -f /usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png ]"

# app sandbox: only its own files + up to two allowed folders
mkdir -p /tmp/sbhome/secret /tmp/sbhome/Movies /tmp/sbhome/.config/gill-osaab/app-folders
echo top-secret > /tmp/sbhome/secret/file; echo film > /tmp/sbhome/Movies/film
echo /tmp/sbhome/Movies > /tmp/sbhome/.config/gill-osaab/app-folders/testapp.conf
check "sandboxed app cannot see your other files" "! HOME=/tmp/sbhome gosaab-sandbox testapp cat /tmp/sbhome/secret/file 2>/dev/null"
check "sandboxed app can use its allowed folder" "HOME=/tmp/sbhome gosaab-sandbox testapp cat /tmp/sbhome/Movies/film | grep -q film"
check "Firefox opens sandboxed" "grep -qs '^Exec=gosaab-sandbox firefox' /usr/share/applications/*firefox*.desktop"
check "VLC opens sandboxed" "grep -qs '^Exec=gosaab-sandbox vlc' /usr/share/applications/*vlc*.desktop /usr/share/applications/*VLC*.desktop"

# start the real session the way the login screen does (headless, software GPU)
VKMS=
for card in /sys/class/drm/card[0-9]*; do
  [ "$(basename "$(readlink -f "$card/device")")" = vkms ] && VKMS=/dev/dri/$(basename "$card")
done
export XDG_RUNTIME_DIR=/tmp/xdg && mkdir -p -m 700 $XDG_RUNTIME_DIR
export HOME=/tmp/home USER=gill && mkdir -p $HOME
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER_ALLOW_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1
export GOSAAB_RENDER_CARD=$VKMS GOSAAB_HEADLESS_SIZE=1920x1080 QT_QUICK_BACKEND=software
export DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address 2>/dev/null)
gosaab-session >"$OUT/session.log" 2>&1 &
for _ in $(seq 1 60); do [ -s $XDG_RUNTIME_DIR/gosaab-wm.socket ] && break; sleep 0.5; done
export WAYLAND_DISPLAY=$(cat $XDG_RUNTIME_DIR/gosaab-wm.socket 2>/dev/null)
for _ in $(seq 1 40); do qs -c gill-osaab ipc call shell ping 2>/dev/null | grep -q ok && break; sleep 0.5; done
check "Gill-OSaab session starts and the shell answers" "qs -c gill-osaab ipc call shell ping | grep -q ok"
sleep 3; grim "$OUT/01-core-desktop.png"
foot -T Terminal -e sh -c 'sleep 60' & sleep 2; grim "$OUT/02-core-window.png"
notify-send -a Steam -h int:value:64 "Downloading Cyberpunk 2077" "41.2 GB of 64 GB"; sleep 1.5; grim "$OUT/03a-core-notification.png"
qs -c gill-osaab ipc call controlcenter toggle; sleep 1.5; grim "$OUT/03-core-control-centre.png"
qs -c gill-osaab ipc call controlcenter toggle
qs -c gill-osaab ipc call launchpad toggle; sleep 1.5; grim "$OUT/04-core-launchpad.png"
qs -c gill-osaab ipc call launchpad toggle; sleep 0.5
qs -c gill-osaab ipc call spotlight search "fire"; sleep 1.5; grim "$OUT/05-core-spotlight.png"
qs -c gill-osaab ipc call spotlight toggle; sleep 0.5
QT_QPA_PLATFORM=wayland gosaab-settings >/dev/null 2>&1 & sleep 4; grim "$OUT/06-core-settings.png"
check "desktop still running" "pgrep -x gosaab-wm >/dev/null"
grep -E "ERROR|TypeError|ReferenceError|is not a type" "$OUT/session.log" | grep -v "EGL\|pipewire\|renderer" | sort -u | head -10
exit $fail
