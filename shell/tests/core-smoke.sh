#!/usr/bin/env bash
# Inside the Gill-OSaab Core image: is everything there, and does the real session start?
set -u
OUT=${1:-/tmp/core-shots}
mkdir -p "$OUT"
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

for b in gosaab-wm gosaab-session gosaab-game-mode steamos-session-select qs swaybg xwayland-satellite \
         foot nautilus firefox gamescope steam sddm grim wine waydroid distrobox flatpak gosaab-settings gosaab-updates; do
  check "installed: $b" "command -v $b >/dev/null"
done
echo "wine files: $(ls -d /usr/bin/wine* /etc/alternatives/wine* 2>/dev/null | tr "\n" " ")"
check "Windows apps: wine runs" "wine --version >/dev/null 2>&1"
check "shell config installed" "[ -f /etc/xdg/quickshell/gill-osaab/shell.qml ]"
check "login theme installed" "[ -f /usr/share/sddm/themes/gill-osaab/Main.qml ]"
check "desktop session listed" "[ -f /usr/share/wayland-sessions/gill-osaab.desktop ]"
check "Game Mode session listed" "[ -f /usr/share/wayland-sessions/gill-osaab-gamemode.desktop ]"
check "login screen uses our theme" "grep -q 'Current=gill-osaab' /etc/sddm.conf.d/10-gill-osaab.conf"
check "no KDE Plasma in Core" "! rpm -q plasma-workspace >/dev/null 2>&1"
check "wallpaper present" "[ -f /usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png ]"

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
qs -c gill-osaab ipc call controlcenter toggle; sleep 1.5; grim "$OUT/03-core-control-centre.png"
qs -c gill-osaab ipc call controlcenter toggle
qs -c gill-osaab ipc call launchpad toggle; sleep 1.5; grim "$OUT/04-core-launchpad.png"
qs -c gill-osaab ipc call launchpad toggle; sleep 0.5
check "desktop still running" "pgrep -x gosaab-wm >/dev/null"
grep -E "ERROR|TypeError|ReferenceError|is not a type" "$OUT/session.log" | grep -v "EGL\|pipewire\|renderer" | sort -u | head -10
exit $fail
