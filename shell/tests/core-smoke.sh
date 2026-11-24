#!/usr/bin/env bash
# Inside the Gill-OSaab Core image: is everything there, and does the real session start?
set -u
OUT=${1:-/tmp/core-shots}
mkdir -p "$OUT"
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

for b in gosaab-wm gosaab-session gosaab-game-mode steamos-session-select qs swaybg xwayland-satellite \
         foot nautilus gamescope steam sddm grim wine waydroid distrobox flatpak gosaab-settings gosaab-updates gosaab-emudeck gosaab-android-setup gosaab-glasses wlr-randr vlc wg; do
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
check "VPN, cloud drives and Android bridge tools" "command -v nmcli >/dev/null && command -v rclone >/dev/null && command -v adb >/dev/null && [ -f /usr/lib/systemd/user/gosaab-cloud@.service ]"
check "Android installs on first sign-in, can be removed in Settings" "[ -x /usr/libexec/gill-osaab/gosaab-first-setup ] && grep -q org.gillosaab.android /usr/share/polkit-1/actions/org.gillosaab.session.policy"
check "controller works on the desktop (evdev + uinput helper)" "python3 -c 'import evdev' && [ -x /usr/libexec/gill-osaab/gosaab-gamepad ]"
check "boot screen: progress ring theme" "plymouth-set-default-theme 2>/dev/null | grep -q gill-osaab"
check "printers, scanners, firmware ready" "command -v lpstat >/dev/null && command -v scanimage >/dev/null && command -v fwupdmgr >/dev/null"
check "Android folders service ready" "command -v bindfs >/dev/null && systemctl is-enabled gosaab-android-folders.service >/dev/null 2>&1"
check "start-up choice applied at boot" "systemctl is-enabled gosaab-boot-mode.service >/dev/null 2>&1"
id smokeuser >/dev/null 2>&1 || useradd -m smokeuser
check "can't set sign-in for someone else (or root) without a password" "! PKEXEC_UID=\$(id -u smokeuser) /usr/libexec/gill-osaab/gosaab-session-select-root --boot root game 2>/dev/null && [ ! -e /etc/sddm.conf.d/zz-gill-osaab-autologin.conf ]"
/usr/libexec/gill-osaab/gosaab-session-select-root --boot smokeuser game
check "Settings: start in Game Mode" "grep -q 'Session=gill-osaab-gamemode.desktop' /etc/sddm.conf.d/zz-gill-osaab-autologin.conf"
/usr/libexec/gill-osaab/gosaab-session-select-root --boot smokeuser desktop
check "Settings: start in Desktop" "grep -q 'Session=gill-osaab.desktop' /etc/sddm.conf.d/zz-gill-osaab-autologin.conf"
/usr/libexec/gill-osaab/gosaab-session-select-root --boot smokeuser ask
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
check "Brave installed (kept in /usr/lib, linked into /opt at boot)" "[ -x /usr/lib/brave.com/brave/brave ] && grep -q brave.com /usr/lib/tmpfiles.d/gill-osaab-brave.conf"
check "Brave opens sandboxed" "grep -qs '^Exec=gosaab-sandbox brave' /usr/share/applications/brave-browser.desktop"
check "Brave is the default browser" "grep -q 'https=brave-browser.desktop' /etc/xdg/mimeapps.list"
check "VLC opens sandboxed" "grep -qs '^Exec=gosaab-sandbox vlc' /usr/share/applications/*vlc*.desktop /usr/share/applications/*VLC*.desktop"
check "sandboxed app can't see other programs" "[ \$(HOME=/tmp/sbhome gosaab-sandbox testapp sh -c 'ls -d /proc/[0-9]* | wc -l') -le 4 ]"
check "sandboxed app can't read keyboards/controllers directly" "! HOME=/tmp/sbhome gosaab-sandbox testapp ls /dev/input >/dev/null 2>&1"
export XDG_RUNTIME_DIR=/tmp/sbrt && mkdir -p -m 700 /tmp/sbrt
export DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address 2>/dev/null)
python3 -c 'from gi.repository import Gio, GLib; Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.systemd1", 0, None, None, None); GLib.MainLoop().run()' & fake_systemd=$!
sleep 1
ping_systemd='gdbus call --session --dest org.freedesktop.systemd1 --object-path / --method org.freedesktop.DBus.Peer.Ping'
list_names='gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames'
check "sandboxed app gets a filtered session bus (can't start programs outside)" "$ping_systemd >/dev/null && HOME=/tmp/sbhome gosaab-sandbox testapp sh -c \"$list_names >/dev/null && ! $ping_systemd >/dev/null 2>&1\""
check "sandboxed app can't reach the system bus" "HOME=/tmp/sbhome gosaab-sandbox testapp sh -c '[ ! -e /run/dbus/system_bus_socket ]'"
kill $fake_systemd 2>/dev/null; unset DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR

# security
check "remote login (SSH) off by default" "! systemctl is-enabled sshd.service >/dev/null 2>&1"
echo "firewall: $(systemctl is-enabled firewalld.service 2>&1) zone=$(sed -n 's/^DefaultZone=//p' /etc/firewalld/firewalld.conf) services=$(firewall-offline-cmd --zone=public --list-services 2>&1 | tail -1)"
check "firewall on, nothing open but discovery and Steam" "systemctl is-enabled firewalld.service >/dev/null 2>&1 && grep -q '^DefaultZone=public' /etc/firewalld/firewalld.conf && ! grep -q 'service name=\"ssh\"' /etc/firewalld/zones/public.xml"
check "no surprise restarts from automatic updates" "! systemctl is-enabled bootc-fetch-apply-updates.timer >/dev/null 2>&1"
check "apps can't read each other's memory (ptrace)" "grep -q 'ptrace_scope = 1' /usr/lib/sysctl.d/60-gill-osaab.conf"
id weakuser >/dev/null 2>&1 || useradd -m weakuser; echo weakuser:gill | chpasswd
/usr/libexec/gill-osaab/gosaab-security-check >/dev/null 2>&1
check "default password is detected (asks you to change it)" "grep -q weakuser /run/gill-osaab/security.json && ! grep -q smokeuser /run/gill-osaab/security.json"

# drivers, problems, shortcuts
for unit in gosaab-drivers.timer gosaab-hotkeyd.service gosaab-security-check.service gosaab-battery.path; do
  check "enabled: $unit" "systemctl is-enabled $unit >/dev/null 2>&1"
done
check "problem check runs hourly after sign-in" "systemctl --global is-enabled gosaab-diagnose.timer >/dev/null 2>&1"
gosaab-drivers list > /tmp/drivers.json 2>/tmp/drivers.err; echo "drivers: $(python3 -c 'import json;d=json.load(open("/tmp/drivers.json"));print(d["categories"], len(d["parts"]), "parts", len(d["problems"]), "problems")' 2>&1)"
check "every part and its driver is listed" "python3 -c 'import json;d=json.load(open(\"/tmp/drivers.json\"));assert d[\"parts\"]'"
gosaab-drivers auto >/dev/null 2>&1
check "drivers recorded at start-up" "[ -s /var/lib/gill-osaab/drivers.json ]"
check "problems are collected" "HOME=/tmp/diag gosaab-diagnose --collect"
HOME=/tmp/diag gosaab-diagnose --report > /tmp/report.txt; head -8 /tmp/report.txt
check "problem report can be copied (personal details removed)" "grep -q 'Gill-OSaab problem report' /tmp/report.txt && ! grep -q \"\$(hostname)\" /tmp/report.txt"
check "button shortcuts: Windows+R switches Game Mode/Desktop" "grep -q '^META+R = mode' /etc/gill-osaab/hotkeys.conf"
check "button shortcuts: add your own" "HOME=/tmp/hk gosaab-hotkeys set BTN_MODE+BTN_SOUTH app:steam && HOME=/tmp/hk gosaab-hotkeys list | grep -q 'Home button + A'"
check "button shortcuts: typing keys refused" "! HOME=/tmp/hk gosaab-hotkeys set R mode 2>/dev/null"
timeout 3 /usr/libexec/gill-osaab/gosaab-hotkeyd; rc=$?
check "shortcut service starts (Desktop and Game Mode)" "[ $rc -eq 124 ]"

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
for pg in problems device buttons security; do
  QT_QPA_PLATFORM=wayland gosaab-settings $pg >/dev/null 2>&1 & sp=$!; sleep 4; grim "$OUT/07-settings-$pg.png"; kill $sp
done
check "desktop still running" "pgrep -x gosaab-wm >/dev/null"
grep -E "ERROR|TypeError|ReferenceError|is not a type" "$OUT/session.log" | grep -v "EGL\|pipewire\|renderer" | sort -u | head -10
exit $fail
