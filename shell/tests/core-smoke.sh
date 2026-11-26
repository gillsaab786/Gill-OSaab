#!/usr/bin/env bash
# Inside the Gill(OS) Core image: is everything there, and does the real session start?
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
/usr/libexec/gill-osaab/gosaab-session-select-root smokeuser gill-osaab
/usr/libexec/gill-osaab/gosaab-session-select-root --restore smokeuser
check "Game Mode/Desktop switch signs in once only (no password-free sign-in after a restart)" "[ ! -e /etc/sddm.conf.d/zz-gill-osaab-autologin.conf ]"
check "App Info tells apps apart" "/usr/libexec/gill-osaab/gosaab-appinfo info org.gnome.Nautilus 2>/dev/null | grep -q '\"source\": \"system\"' || /usr/libexec/gill-osaab/gosaab-appinfo info gosaab-settings | grep -q '\"kind\": \"Linux\"'"
check "Game Mode startup movie and switch sound installed" "[ -s /usr/share/gill-osaab/media/deck_startup.webm ] && [ -s /usr/share/gill-osaab/media/mode-switch.wav ]"
check "compressed memory (zram) set up" "rpm -q zram-generator >/dev/null && grep -q zstd /usr/lib/systemd/zram-generator.conf && grep -q 'swappiness = 180' /usr/lib/sysctl.d/60-gill-osaab.conf"
check "memory view lists apps" "/usr/libexec/gill-osaab/gosaab-memory list | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"total\"] > 0 and \"apps\" in d'"
check "per-game profiles save through the settings tool" "gosaab-config profile set steam:42 '{\"name\": \"Test\", \"tdp\": 12, \"fps\": 40}' && grep -q steam:42 /etc/gill-osaab/game-profiles.json && gosaab-config profile remove steam:42"
check "FPS cap tool for Game Mode present" "command -v xprop >/dev/null"
check "phone link installed (off until switched on)" "[ -x /usr/libexec/kdeconnectd ] || rpm -q kde-connect >/dev/null"
check "Optional Features are off by default" "! grep -qE '^(phone_link|shared_game_library|vrr|suspend_then_hibernate|undervolt|smart_updates)[[:space:]]*=[[:space:]]*(on|true|1|yes)' /etc/gill-osaab/features.conf"
check "shared game library tool runs" "HOME=/tmp/libtest /usr/libexec/gill-osaab/gosaab-library list | python3 -c 'import json,sys; json.load(sys.stdin)'"
check "emulator 3D tool runs" "HOME=/tmp/3dtest gosaab-3d status | grep -q dolphin"
check "AMOLED black wallpaper present" "[ -f /usr/share/wallpapers/GillOSaab/contents/images_black/3840x2160.png ]"
check "named Gill(OS)" "grep -q '^NAME=\"Gill(OS)\"' /usr/lib/os-release"
check "shell config installed" "[ -f /etc/xdg/quickshell/gill-osaab/shell.qml ]"
check "login theme installed" "[ -f /usr/share/sddm/themes/gill-osaab/Main.qml ]"
check "desktop session listed" "[ -f /usr/share/wayland-sessions/gill-osaab.desktop ]"
check "Game Mode session listed" "[ -f /usr/share/wayland-sessions/gill-osaab-gamemode.desktop ]"
check "login screen uses our theme" "grep -q 'Current=gill-osaab' /etc/sddm.conf.d/10-gill-osaab.conf"
check "no KDE Plasma in Core" "! rpm -q plasma-workspace >/dev/null 2>&1"
check "wallpaper present" "[ -f /usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png ]"
check "Tide wallpaper has light and dark versions, Aurora kept" "[ -f /usr/share/wallpapers/GillOSaab/contents/images/3840x2160.png ] && [ -f /usr/share/wallpapers/GillOSaab-Classic/contents/images_dark/3840x2160.png ]"
check "weather and clipboard helpers run" "/usr/libexec/gill-osaab/gosaab-weather | grep -q Settings && XDG_RUNTIME_DIR=/tmp /usr/libexec/gill-osaab/gosaab-clipboard list | grep -q '\['"
check "Ally stick lights service enabled (idles on other PCs)" "systemctl is-enabled gosaab-ally-lights.service >/dev/null 2>&1 && /usr/libexec/gill-osaab/gosaab-ally-lights status | grep -q '\"ally\": false'"

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
check "problem report can be copied (personal details removed)" "grep -q 'Gill(OS) problem report' /tmp/report.txt && ! grep -q \"\$(hostname)\" /tmp/report.txt"
check "button shortcuts: Windows+R switches Game Mode/Desktop" "grep -q '^META+R = mode' /etc/gill-osaab/hotkeys.conf"
check "button shortcuts: add your own" "HOME=/tmp/hk gosaab-hotkeys set BTN_MODE+BTN_SOUTH app:steam && HOME=/tmp/hk gosaab-hotkeys list | grep -q 'Home button + A'"
check "button shortcuts: typing keys refused" "! HOME=/tmp/hk gosaab-hotkeys set R mode 2>/dev/null"
# update schedule, driver search and rollback, encrypted install
check "update schedule: every 3 months / never / drivers only" "gosaab-config set updates.conf frequency 3months && gosaab-config set updates.conf scope drivers && ! gosaab-config set updates.conf frequency fortnightly 2>/dev/null"
mkdir -p /var/lib/gill-osaab && date +%s > /var/lib/gill-osaab/last-auto-update
check "nothing updates before the chosen time" "timeout 20 /usr/libexec/gill-osaab/gosaab-update-run | grep -q 'not due'"
gosaab-config set updates.conf frequency daily; gosaab-config set updates.conf scope everything
check "driver search index built ($(python3 -c 'import json;print(sum(len(v) for v in json.load(open("/usr/share/gill-osaab/driver-index.json")).values()))' 2>/dev/null) drivers)" "[ -s /usr/share/gill-osaab/driver-index.json ]"
gosaab-drivers search realtek wifi > /tmp/search.json; echo "search 'realtek wifi': $(python3 -c 'import json;r=json.load(open("/tmp/search.json"));print(len(r), [x["name"] for x in r[:5]])')"
check "search any driver (e.g. Realtek Wi-Fi)" "grep -q 'Built-in driver' /tmp/search.json"
check "driver changes listed for rollback" "gosaab-drivers history | python3 -c 'import json,sys;assert isinstance(json.load(sys.stdin),list)'"
check "encryption status" "gosaab-encryption status | grep -q '\"encrypted\": false'"
check "installer lists drives (JSON)" "gosaab-install --list | python3 -c 'import json,sys;json.load(sys.stdin)'"
gosaab-install /dev/nvme9n9 --dry-run --yes > /tmp/install.txt 2>&1; grep '^+' /tmp/install.txt | head -3
check "encrypted install: whole drive LUKS2 + security chip" "grep -q 'bootc install to-disk --wipe --filesystem btrfs --block-setup tpm2-luks /dev/nvme9n9' /tmp/install.txt"
check "first start after install creates your account" "systemctl is-enabled gosaab-firstboot-user.service >/dev/null 2>&1"
# graphics, FPS, Secure Boot, installer, touch keyboard
for pkg in microcode_ctl amd-ucode-firmware thermald intel-media-driver mesa-vulkan-drivers.i686 gamemode mokutil; do
  check "installed: $pkg" "rpm -q $pkg >/dev/null"
done
check "thermald only runs on Intel processors" "grep -q GenuineIntel /usr/lib/systemd/system/thermald.service.d/gill-osaab-intel-only.conf"
gosaab-fps status > /tmp/fps.json; echo "fps: $(python3 -c 'import json;d=json.load(open("/tmp/fps.json"));print(d["main"], d["env"])')"
check "best FPS setup is detected for the graphics chip" "python3 -c 'import json;d=json.load(open(\"/tmp/fps.json\"));assert \"recommendation\" in d'"
check "FPS settings reach games (both sessions)" "grep -q 60-gill-osaab-fps /usr/libexec/gill-osaab/gosaab-session-start && grep -q 60-gill-osaab-fps /usr/libexec/gill-osaab/gosaab-gamemode-session"
check "Secure Boot status" "gosaab-secureboot status | python3 -c 'import json,sys;json.load(sys.stdin)'"
check "graphical installer" "python3 -m py_compile /usr/bin/gosaab-installer && grep -q gosaab-installer /usr/share/applications/gosaab-installer.desktop"
check "installer picks the Nvidia edition on RTX/GTX 16 PCs" "python3 -c 'import runpy;g=runpy.run_path(\"/usr/bin/gosaab-install\");assert g[\"image_ref\"](nvidia=True).endswith(\"-nvidia:latest\")'"
check "on-screen keyboard for touch screens" "command -v wvkbd-mobintl >/dev/null"
check "touch keyboard on the login screen" "[ -f /usr/share/sddm/themes/gill-osaab/OnScreenKeyboard.qml ] && [ ! -L /usr/share/sddm/themes/gill-osaab/OnScreenKeyboard.qml ]"
check "Android helper pinned to a reviewed version, asks for a password" "grep -q WS_COMMIT= /usr/bin/gosaab-android-setup && grep -A8 org.gillosaab.android /usr/share/polkit-1/actions/org.gillosaab.session.policy | grep -q auth_admin_keep"
# Smart TDP and graphics switching
check "Smart TDP runs at start-up" "systemctl is-enabled gosaab-smart-power.service >/dev/null 2>&1"
timeout 15 /usr/libexec/gill-osaab/gosaab-smart-power --once >/dev/null 2>&1
echo "power: $(cat /run/gill-osaab/power.json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["label"], d["device"], d["backend"], d["backends"])' 2>&1)"
check "Smart TDP decides a power mode" "python3 -c 'import json;d=json.load(open(\"/run/gill-osaab/power.json\"));assert d[\"mode\"] in (\"idle\",\"video\",\"desktop\",\"game\")'"
check "graphics switching tool" "gosaab-gpu status | python3 -c 'import json,sys;assert \"hybrid\" in json.load(sys.stdin)'"
check "Smart TDP settings can be changed" "gosaab-config set features.conf tdp_game 28 && gosaab-config set features.conf gpu_mode integrated && gosaab-config set features.conf gpu_mode auto && ! gosaab-config set features.conf gpu_mode turbo 2>/dev/null"
# face unlock, haptics, Game Mode panel
echo "face unlock: $(gosaab-face status 2>&1) howdy: $(rpm -q howdy 2>&1 | tail -1)"
check "face unlock status" "gosaab-face status | python3 -c 'import json,sys;json.load(sys.stdin)'"
check "haptic feedback runs without a controller" "XDG_RUNTIME_DIR=/tmp /usr/libexec/gill-osaab/gosaab-haptic tick"
check "Game Mode panel: volume, brightness, battery" "grep -q 'Quick settings' /usr/share/gill-osaab/decky/gill-osaab-notify/dist/index.js && grep -q 'def set_brightness' /usr/share/gill-osaab/decky/gill-osaab-notify/main.py"
check "battery time left is estimated" "python3 -c 'import json;d=json.load(open(\"/run/gill-osaab/power.json\"));assert \"battery\" in d'"
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
check "Gill(OS) session starts and the shell answers" "qs -c gill-osaab ipc call shell ping | grep -q ok"
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
for pg in problems device buttons security game; do
  QT_QPA_PLATFORM=wayland gosaab-settings $pg >/dev/null 2>&1 & sp=$!; sleep 4; grim "$OUT/07-settings-$pg.png"; kill $sp
done
check "desktop still running" "pgrep -x gosaab-wm >/dev/null"
grep -E "ERROR|TypeError|ReferenceError|is not a type" "$OUT/session.log" | grep -v "EGL\|pipewire\|renderer" | sort -u | head -10
exit $fail
