#!/usr/bin/env bash
# Runs gosaab-wm with no screen (headless) on a virtual GPU, opens real apps,
# takes screenshots at key moments and checks the results.
# Usage: run-headless.sh <build dir> <output dir>
set -u
BUILD=${1:-shell/compositor/build}
OUT=${2:-artifacts}
WALL=files/system/usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png
mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/gosaab-xdg LANG=C.UTF-8 LC_ALL=C.UTF-8
rm -rf "$XDG_RUNTIME_DIR" && mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 GOSAAB_HEADLESS_SIZE=1920x1080 WLR_RENDERER_ALLOW_SOFTWARE=1
unset WAYLAND_DISPLAY

# Find the virtual cards (vkms / vgem show up as "faux_driver" on new kernels)
VKMS= VGEM=
for card in /sys/class/drm/card[0-9]*; do
  [ -e "$card" ] || continue
  dev=$(basename "$(readlink -f "$card/device" 2>/dev/null)")
  echo "$(basename "$card"): $dev"
  [ "$dev" = vkms ] && VKMS=/dev/dri/$(basename "$card")
  [ "$dev" = vgem ] && VGEM=/dev/dri/$(basename "$card")
done

start_wm() { # $1 = label; environment already set
  rm -f "$XDG_RUNTIME_DIR/gosaab-wm.socket"
  "$BUILD/gosaab-wm" -s "swaybg -i $WALL -m fill" >"$OUT/gosaab-wm.log" 2>&1 &
  WM=$!
  for _ in $(seq 1 30); do [ -s "$XDG_RUNTIME_DIR/gosaab-wm.socket" ] && break; sleep 0.1; done
  sleep 1.5
  if kill -0 $WM 2>/dev/null && ! grep -q "Failed to allocate\|failed test\|failed to create" "$OUT/gosaab-wm.log"; then
    echo "GPU setup that works: $1"; return 0
  fi
  echo "GPU setup failed: $1"; grep "\[ERROR\]" "$OUT/gosaab-wm.log" | sort -u | head -3
  kill $WM 2>/dev/null; wait $WM 2>/dev/null; return 1
}

try_setups() {
  ( export GOSAAB_RENDER_CARD=$VKMS LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=kms_swrast; start_wm "vkms+always_software" ) && return 0
  ( export GOSAAB_RENDER_CARD=$VKMS LIBGL_ALWAYS_SOFTWARE=1; start_wm "vkms+libgl_software" ) && return 0
  ( export GOSAAB_RENDER_CARD=$VKMS MESA_LOADER_DRIVER_OVERRIDE=swrast; start_wm "vkms+swrast" ) && return 0
  ( export WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128 LIBGL_ALWAYS_SOFTWARE=1; start_wm "vgem-render+software" ) && return 0
  return 1
}

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
shot() { grim "$OUT/$1.png" && echo "shot $1"; }

SETUP=$(try_setups 2>&1 | tee /dev/stderr | sed -n 's/^GPU setup that works: //p')
pkill -f "$BUILD/gosaab-wm" 2>/dev/null; sleep 0.5
case "$SETUP" in
  vkms+always_software) export GOSAAB_RENDER_CARD=$VKMS LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=kms_swrast ;;
  vkms+libgl_software) export GOSAAB_RENDER_CARD=$VKMS LIBGL_ALWAYS_SOFTWARE=1 ;;
  vkms+swrast) export GOSAAB_RENDER_CARD=$VKMS MESA_LOADER_DRIVER_OVERRIDE=swrast ;;
  vgem-render+software) export WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128 LIBGL_ALWAYS_SOFTWARE=1 ;;
esac
rm -f "$XDG_RUNTIME_DIR/gosaab-wm.socket"
"$BUILD/gosaab-wm" -s "swaybg -i $WALL -m fill" >"$OUT/gosaab-wm.log" 2>&1 &
WM=$!
for _ in $(seq 1 50); do [ -s "$XDG_RUNTIME_DIR/gosaab-wm.socket" ] && break; sleep 0.1; done
check "compositor starts (GPU setup: ${SETUP:-none})" "[ -n \"$SETUP\" ] && [ -s $XDG_RUNTIME_DIR/gosaab-wm.socket ] && kill -0 $WM"
export WAYLAND_DISPLAY=$(cat "$XDG_RUNTIME_DIR/gosaab-wm.socket" 2>/dev/null)
sleep 1.5
shot 01-wallpaper

foot -W 100x30 -o font=monospace:size=13 -e sh -c 'echo "Gill-OSaab window 1"; sleep 120' &
sleep 0.10; shot 02-opening
sleep 1.2;  shot 03-one-window

foot -W 70x18 -o font=monospace:size=13 -e sh -c 'echo "Gill-OSaab window 2"; sleep 120' &
sleep 1.2;  shot 04-two-windows

kill -USR1 $WM            # close the focused window (window 2)
sleep 0.06; shot 05-closing
sleep 1.0;  shot 06-after-close

check "compositor still running" "kill -0 $WM"
check "no compositor errors" "! grep -E '\\[ERROR\\]|Segmentation|Aborted' $OUT/gosaab-wm.log"
python3 - "$OUT" <<'EOF' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
def load(n):
    return Image.open(f"{out}/{n}.png").convert("RGB")
def diff(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(load(a), load(b))).mean) / 3
def changed(a, b):  # fraction of pixels that visibly changed
    d = ImageChops.difference(load(a), load(b)).convert("L").point(lambda v: 255 if v > 24 else 0)
    return ImageStat.Stat(d).mean[0] / 255
checks = [
    ("wallpaper is drawn (not a flat colour)", ImageStat.Stat(load("01-wallpaper")).stddev[0] > 5),
    ("a window appears", diff("01-wallpaper", "03-one-window") > 2),
    ("second window appears", changed("03-one-window", "04-two-windows") > 0.0004),
    ("closing removes the window", changed("04-two-windows", "06-after-close") > 0.0004),
    ("after close matches one window", diff("03-one-window", "06-after-close") < 1.5),
]
bad = 0
for name, ok in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
    bad += not ok
print("diffs:", {k: round(diff(*k.split("|")), 2) for k in ["01-wallpaper|03-one-window", "03-one-window|06-after-close", "02-opening|03-one-window", "05-closing|06-after-close"]})
sys.exit(1 if bad else 0)
EOF

kill -TERM $WM 2>/dev/null
wait $WM; rc=$?
echo "compositor exit code: $rc"; tail -3 "$OUT/gosaab-wm.log"
check "clean shutdown" "[ $rc -eq 0 ]"

# Slow-motion run (animations 10x slower) to capture frames mid-animation
pkill foot 2>/dev/null
rm -f "$XDG_RUNTIME_DIR/gosaab-wm.socket"
GOSAAB_ANIM_SLOWDOWN=10 "$BUILD/gosaab-wm" -s "swaybg -i $WALL -m fill" >"$OUT/gosaab-wm-slow.log" 2>&1 &
WM=$!
for _ in $(seq 1 50); do [ -s "$XDG_RUNTIME_DIR/gosaab-wm.socket" ] && break; sleep 0.1; done
WAYLAND_DISPLAY=$(cat "$XDG_RUNTIME_DIR/gosaab-wm.socket")
export WAYLAND_DISPLAY
sleep 1
foot -W 100x30 -e sh -c 'echo "opening in slow motion"; sleep 120' &
sleep 0.6; shot 07-slow-opening
sleep 3.5; shot 08-slow-open-done
kill -USR1 $WM
sleep 0.9; shot 09-slow-closing
sleep 2.5; shot 10-slow-closed
python3 - "$OUT" <<'EOF2' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
d = lambda a, b: sum(ImageStat.Stat(ImageChops.difference(
    Image.open(f"{out}/{a}.png").convert("RGB"), Image.open(f"{out}/{b}.png").convert("RGB"))).mean) / 3
res = {"opening vs open": d("07-slow-opening", "08-slow-open-done"),
       "closing vs closed": d("09-slow-closing", "10-slow-closed"),
       "closing vs open": d("09-slow-closing", "08-slow-open-done")}
print("animation diffs:", {k: round(v, 2) for k, v in res.items()})
ok = [("open animation shows an in-between frame", res["opening vs open"] > 0.3),
      ("close animation shows an in-between frame", res["closing vs closed"] > 0.3 and res["closing vs open"] > 0.3)]
for name, good in ok:
    print(("PASS: " if good else "FAIL: ") + name)
sys.exit(0 if all(g for _, g in ok) else 1)
EOF2
# minimise flies into the Dock (slow motion)
foot -W 100x30 -e sh -c 'echo "minimise me"; sleep 120' &
sleep 4.5; shot 10a-slow-window
kill -USR2 $WM
sleep 1.6; shot 10b-slow-minimizing
sleep 3.5; shot 10c-slow-minimized
python3 - "$OUT" <<'EOF6' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
d = lambda a, b: sum(ImageStat.Stat(ImageChops.difference(
    Image.open(f"{out}/{a}.png").convert("RGB"), Image.open(f"{out}/{b}.png").convert("RGB"))).mean) / 3
r = {"mid vs open": d("10b-slow-minimizing", "10a-slow-window"), "mid vs gone": d("10b-slow-minimizing", "10c-slow-minimized"),
     "gone vs empty": d("10c-slow-minimized", "10-slow-closed")}
print("minimise diffs:", {k: round(v, 2) for k, v in r.items()})
ok = r["mid vs open"] > 0.3 and r["mid vs gone"] > 0.3 and r["gone vs empty"] < 0.5
print(("PASS: " if ok else "FAIL: ") + "minimise animates into the Dock and the window ends hidden")
sys.exit(0 if ok else 1)
EOF6
kill -TERM $WM 2>/dev/null; wait $WM 2>/dev/null

# ---- M2: macOS-style title bar (traffic lights, title), clicked like a real user would
pkill foot 2>/dev/null
CLICKS=$XDG_RUNTIME_DIR/clicks; : >"$CLICKS"
rm -f "$XDG_RUNTIME_DIR/gosaab-wm.socket"
GOSAAB_TEST_CLICKS=$CLICKS "$BUILD/gosaab-wm" -s "swaybg -i $WALL -m fill" >"$OUT/gosaab-wm-chrome.log" 2>&1 &
WM=$!
for _ in $(seq 1 50); do [ -s "$XDG_RUNTIME_DIR/gosaab-wm.socket" ] && break; sleep 0.1; done
export WAYLAND_DISPLAY=$(cat "$XDG_RUNTIME_DIR/gosaab-wm.socket")
sleep 1; shot 11-empty
# find the traffic lights in a screenshot -> "close_x close_y min_x min_y zoom_x zoom_y" (or nothing)
lights() {
python3 - "$OUT/$1.png" <<'EOF3'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); W, H = im.size; px = im.load()
def find(rgb, tol=40):
    xs = ys = n = 0
    for y in range(0, H, 1):
        for x in range(0, W, 2):
            r, g, b = px[x, y]
            if abs(r - rgb[0]) < tol and abs(g - rgb[1]) < tol and abs(b - rgb[2]) < tol:
                xs += x; ys += y; n += 1
    return (round(xs / n), round(ys / n), n) if n > 10 else None
red, yel, grn = find((255, 95, 87)), find((254, 188, 46)), find((40, 200, 64))
if red and yel and grn and abs(red[1] - grn[1]) < 4 and 20 < yel[0] - red[0] < 40 and 20 < grn[0] - yel[0] < 40:
    print(red[0], red[1], yel[0], yel[1], grn[0], grn[1])
EOF3
}
click() { echo "$1 $2" >>"$CLICKS"; }
foot -W 100x30 -T "Gill-OSaab Terminal" -e sh -c 'sleep 300' &
sleep 1.5; shot 12-titlebar
L=($(lights 12-titlebar)); echo "traffic lights at: ${L[*]:-none}"
check "title bar with traffic lights is drawn" "[ \${#L[@]} -eq 6 ]"
python3 - "$OUT" ${L[@]:-0 0 0 0 0 0} <<'EOF4' || fail=1
import sys
from PIL import Image
out = sys.argv[1]; rx, ry, gx = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[6])
im = Image.open(f"{out}/12-titlebar.png").convert("RGB")
if rx == 0:
    print("FAIL: title text is drawn"); sys.exit(1)
# the title bar is dark grey; the centred title has light text pixels
row = [im.getpixel((x, y)) for y in range(ry - 6, ry + 7) for x in range(gx + 30, im.size[0] - 30)]
bar = im.getpixel((gx + 20, ry))
text = sum(1 for p in row if p[0] > 150 and abs(p[0] - p[2]) < 30)
print("title bar colour", bar, "light text pixels", text)
ok = text > 40 and all(30 < c < 70 for c in bar)
print(("PASS: " if ok else "FAIL: ") + "title text is drawn on a dark title bar")
sys.exit(0 if ok else 1)
EOF4
if [ ${#L[@]} -eq 6 ]; then
  click ${L[4]} ${L[5]}; sleep 1.0; shot 13-zoomed          # green: zoom
  Z=($(lights 13-zoomed)); echo "after zoom: ${Z[*]:-none}"
  check "zoom button fills the screen" "[ \${#Z[@]} -eq 6 ] && [ \${Z[0]} -lt 30 ] && [ \${Z[1]} -lt 30 ]"
  click ${Z[4]:-0} ${Z[5]:-0}; sleep 1.0; shot 14-unzoomed  # green again: back to normal size
  U=($(lights 14-unzoomed)); echo "after un-zoom: ${U[*]:-none}"
  check "zoom again restores the window" "[ \${#U[@]} -eq 6 ] && [ \${U[0]} -eq ${L[0]} ] && [ \${U[1]} -eq ${L[1]} ]"
  click ${U[2]:-0} ${U[3]:-0}; sleep 1.0; shot 15-minimized # yellow: minimise
  M=($(lights 15-minimized))
  check "minimise button hides the window" "[ \${#M[@]} -eq 0 ] && kill -0 $WM"
  foot -W 80x20 -T "Second window" -e sh -c 'sleep 300' &
  sleep 1.5; shot 16-second
  S=($(lights 16-second)); echo "second window: ${S[*]:-none}"
  kill -USR2 $WM; sleep 1.0; shot 17-usr2
  check "minimise via shortcut hook" "[ -z \"\$(lights 17-usr2)\" ]"
  foot -W 80x20 -T "Close me" -e sh -c 'sleep 300' &
  sleep 1.5; shot 18-close-me; C=($(lights 18-close-me))
  click ${C[0]:-0} ${C[1]:-0}; sleep 1.2; shot 19-closed   # red: close
  check "close button closes the app" "[ -z \"\$(lights 19-closed)\" ] && [ \$(pgrep -c -f 'Close me') -eq 0 ]"
  # Mission Control: three windows side by side, click the desktop to go back
  pkill -f "Close me|Second window|Gill-OSaab Terminal" 2>/dev/null; sleep 0.8
  for n in 1 2 3; do foot -W $((60 + n * 15))x$((18 + n * 4)) -T "Window $n" -e sh -c 'sleep 300' & sleep 0.6; done
  sleep 1.2; shot 30-three-windows
  echo overview >>"$CLICKS"; sleep 1.2; shot 31-mission-control
  click 6 1074; sleep 1.0; shot 32-back-to-desktop
  python3 - "$OUT" <<'EOF7' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
def changed(a, b):
    d = ImageChops.difference(Image.open(f"{out}/{a}.png").convert("RGB"), Image.open(f"{out}/{b}.png").convert("RGB"))
    return ImageStat.Stat(d.convert("L").point(lambda v: 255 if v > 24 else 0)).mean[0] / 255
a, b = changed("30-three-windows", "31-mission-control"), changed("30-three-windows", "32-back-to-desktop")
print("mission control change", round(a, 3), "after leaving", round(b, 4))
for name, ok in [("Mission Control spreads the windows out", a > 0.05), ("clicking the desktop returns to normal", b < 0.01)]:
    print(("PASS: " if ok else "FAIL: ") + name)
sys.exit(0 if a > 0.05 and b < 0.01 else 1)
EOF7
  # Spaces: slide to space 2 (empty), open a window there, slide back, send a window to space 3
  echo "ws 2" >>"$CLICKS"; sleep 1.2; shot 33-space-2
  foot -W 70x16 -T "On space 2" -e sh -c 'sleep 300' & sleep 1.5; shot 34-space-2-window
  echo "ws 1" >>"$CLICKS"; sleep 1.2; shot 35-back-to-space-1
  echo "movews 3" >>"$CLICKS"; sleep 1.2; shot 36-moved-to-space-3
  echo "ws 1" >>"$CLICKS"; sleep 1.2; shot 37-space-1-without-it
  python3 - "$OUT" <<'EOF9' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
def changed(a, b):
    d = ImageChops.difference(Image.open(f"{out}/{a}.png").convert("RGB"), Image.open(f"{out}/{b}.png").convert("RGB"))
    return ImageStat.Stat(d.convert("L").point(lambda v: 255 if v > 24 else 0)).mean[0] / 255
r = {"space2 vs space1": changed("32-back-to-desktop", "33-space-2"), "space2 window": changed("33-space-2", "34-space-2-window"),
     "back vs before": changed("32-back-to-desktop", "35-back-to-space-1"), "moved": changed("35-back-to-space-1", "37-space-1-without-it")}
print("space changes", {k: round(v, 4) for k, v in r.items()})
checks = [("switching space hides this space's windows", r["space2 vs space1"] > 0.05),
          ("a window opens on the new space", r["space2 window"] > 0.02),
          ("going back shows the first space exactly as it was", r["back vs before"] < 0.01),
          ("a window can be sent to another space", r["moved"] > 0.005)]
for name, ok in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
sys.exit(0 if all(ok for _, ok in checks) else 1)
EOF9
  # Split screen: drag the front window's title bar to the left edge -> left half
  shot 38-before-snap
  S=($(lights 38-before-snap)); echo "front window lights: ${S[*]:-none}"
  if [ ${#S[@]} -eq 6 ]; then
    echo "drag $((S[4] + 60)) ${S[5]} 1 500" >>"$CLICKS"; sleep 1.5; shot 39-snapped-left
    T=($(lights 39-snapped-left)); echo "after snap: ${T[*]:-none}"
    check "dragging to the left edge snaps the window to the left half" "[ \${#T[@]} -eq 6 ] && [ \${T[0]} -lt 40 ] && [ \${T[1]} -lt 40 ]"
    # touchscreen: a finger tap on the red button closes the window
    before=$(pgrep -c -x foot)
    echo "tap ${T[0]} ${T[1]}" >>"$CLICKS"; sleep 1.5; shot 40-touch-closed
    check "touchscreen tap on the close button closes the app" "[ \$(pgrep -c -x foot) -lt $before ]"
  else
    echo "FAIL: no front window found for the snap test"; fail=1
  fi
  # Several screens: wlr-randr sees the display and can change its resolution
  if command -v wlr-randr >/dev/null; then
    wlr-randr >"$OUT/wlr-randr.txt" 2>&1
    check "display settings: screens are listed" "grep -q HEADLESS-1 $OUT/wlr-randr.txt"
    wlr-randr --output HEADLESS-1 --custom-mode 1600x900 >/dev/null 2>&1; sleep 1; shot 41-resolution-1600
    check "display settings: resolution changes" "python3 -c \"from PIL import Image;import sys;sys.exit(0 if Image.open('$OUT/41-resolution-1600.png').size==(1600,900) else 1)\""
    wlr-randr --output HEADLESS-1 --custom-mode 1920x1080 >/dev/null 2>&1; sleep 1
  fi
fi
check "compositor survived the clicks" "kill -0 $WM"
kill -TERM $WM 2>/dev/null; wait $WM; rc=$?
check "clean shutdown after window chrome tests" "[ $rc -eq 0 ]"
pkill foot 2>/dev/null

# ---- M3: the Gill-OSaab shell (menu bar, Dock, notifications, Control Centre, Spotlight)
if command -v qs >/dev/null; then
  SHELLDIR=$(pwd)/shell/quickshell
  export QT_QUICK_BACKEND=software QT_QPA_PLATFORM=wayland GOSAAB_TEST=1 GOSAAB_WALLPAPER=$(pwd)/$WALL
  export GOSAAB_SHELL_IPC="qs -p $SHELLDIR ipc call"
  # a session bus, for notifications
  DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address 2>/dev/null) && export DBUS_SESSION_BUS_ADDRESS
  rm -f "$XDG_RUNTIME_DIR/gosaab-wm.socket"
  "$BUILD/gosaab-wm" -s "swaybg -i $WALL -m fill" >"$OUT/gosaab-wm-shell.log" 2>&1 &
  WM=$!
  for _ in $(seq 1 50); do [ -s "$XDG_RUNTIME_DIR/gosaab-wm.socket" ] && break; sleep 0.1; done
  export WAYLAND_DISPLAY=$(cat "$XDG_RUNTIME_DIR/gosaab-wm.socket")
  # apps from several systems: YouTube for Android and Windows, Netflix only for Android
  APPS=$HOME/.local/share/applications; mkdir -p "$APPS"
  printf '[Desktop Entry]\nType=Application\nName=YouTube\nExec=waydroid app launch com.google.android.youtube\nIcon=youtube\n' > "$APPS/waydroid.com.google.android.youtube.desktop"
  printf '[Desktop Entry]\nType=Application\nName=YouTube\nExec=gosaab-open --wine-run "/x" "C:/YouTube.exe"\nIcon=youtube\n' > "$APPS/wine-youtube.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Netflix\nExec=waydroid app launch com.netflix.mediaclient\nIcon=netflix\n' > "$APPS/waydroid.com.netflix.mediaclient.desktop"
  qs -p "$SHELLDIR" >"$OUT/quickshell.log" 2>&1 &
  QS=$!
  for _ in $(seq 1 40); do qs -p "$SHELLDIR" ipc call shell ping 2>/dev/null | grep -q ok && break; sleep 0.5; done
  sleep 2; shot 20-shell-desktop
  check "shell starts and answers" "qs -p $SHELLDIR ipc call shell ping | grep -q ok"
  foot -W 90x26 -T "Terminal" -e sh -c 'sleep 300' &
  sleep 2; shot 21-shell-window
  notify-send -a "Firefox" -i firefox -h int:value:42 "Downloading Gill-OSaab.iso" "1.2 GB of 2.9 GB — 3 min left"
  sleep 0.15; shot 22a-banner-sliding
  sleep 1.5; shot 22-notification
  check "notification arrived" "[ \$(qs -p $SHELLDIR ipc call notifications count) -ge 1 ]"
  # progress from file copies / browser downloads (KDE job API, Unity launcher API) -> notifications
  python3 files/system/usr/libexec/gill-osaab/gosaab-notify-hub --desktop >"$OUT/notify-hub.log" 2>&1 & HUBPID=$!
  for _ in $(seq 1 30); do gdbus introspect --session --dest org.gillosaab.NotifyHub --object-path / >/dev/null 2>&1 && break; sleep 0.2; done
  n0=$(qs -p "$SHELLDIR" ipc call notifications count)
  P=$(gdbus call --session --dest org.kde.JobViewServer --object-path /JobViewServer \
    --method org.kde.JobViewServerV2.requestView "org.gnome.Nautilus" 1 "{}" | grep -o "/JobView/[0-9]*")
  gdbus call --session --dest org.kde.JobViewServer --object-path $P --method org.kde.JobViewV3.update \
    "{'title': <'Copying Movies'>, 'percent': <uint32 37>}" >/dev/null
  gdbus emit --session --object-path /x --signal com.canonical.Unity.LauncherEntry.Update \
    "application://chromium.desktop" "{'progress': <0.62>, 'progress-visible': <true>}"
  sleep 1.5; shot 22b-progress-from-apps
  check "app progress (copies, downloads) shows as notifications" "[ \$(qs -p $SHELLDIR ipc call notifications count) -ge \$((n0 + 2)) ]"
  kill $HUBPID 2>/dev/null
  qs -p "$SHELLDIR" ipc call controlcenter toggle; sleep 1.2; shot 23-control-center
  qs -p "$SHELLDIR" ipc call controlcenter toggle; sleep 0.8
  qs -p "$SHELLDIR" ipc call notifications toggle; sleep 1.2; shot 24-notification-center
  qs -p "$SHELLDIR" ipc call notifications toggle; sleep 0.8
  qs -p "$SHELLDIR" ipc call spotlight search "foo"; sleep 1.2; shot 25-spotlight
  qs -p "$SHELLDIR" ipc call spotlight search "youtube"; sleep 1; R=$(qs -p "$SHELLDIR" ipc call spotlight results); echo "youtube -> $R"
  shot 25b-spotlight-two-youtubes
  check "same app on two systems: shown as Android-YouTube and Windows-YouTube" "echo '$R' | grep -q 'Android-YouTube' && echo '$R' | grep -q 'Windows-YouTube'"
  qs -p "$SHELLDIR" ipc call spotlight search "netflix"; sleep 1; R=$(qs -p "$SHELLDIR" ipc call spotlight results); echo "netflix -> $R"
  check "app on only one system: just its name (Netflix)" "[ '$R' = Netflix ]"
  qs -p "$SHELLDIR" ipc call spotlight search "12*(3+4)"; sleep 0.8; shot 26-spotlight-maths
  qs -p "$SHELLDIR" ipc call spotlight toggle; sleep 0.8; shot 27-after-spotlight
  qs -p "$SHELLDIR" ipc call launchpad toggle; sleep 1.2; shot 28-launchpad
  qs -p "$SHELLDIR" ipc call launchpad toggle; sleep 0.8; shot 29-after-launchpad
  python3 - "$OUT" <<'EOF5' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
L = lambda n: Image.open(f"{out}/{n}.png").convert("RGB")
def changed(a, b, box=None):
    A, B = L(a), L(b)
    if box: A, B = A.crop(box), B.crop(box)
    d = ImageChops.difference(A, B).convert("L").point(lambda v: 255 if v > 24 else 0)
    return ImageStat.Stat(d).mean[0] / 255
desk = L("20-shell-desktop"); W, H = desk.size
bar = ImageStat.Stat(desk.crop((0, 0, W, 30))).stddev
wall = ImageStat.Stat(L("01-wallpaper").crop((0, 0, W, 30)))
checks = [
  ("menu bar is drawn", changed("01-wallpaper", "20-shell-desktop", (0, 0, W, 30)) > 0.008),
  ("dock is drawn", changed("01-wallpaper", "20-shell-desktop", (W // 4, H - 110, 3 * W // 4, H)) > 0.002),
  ("notification banner shows (top right)", changed("21-shell-window", "22-notification", (W - 400, 30, W, 200)) > 0.05),
  ("control centre opens", changed("22-notification", "23-control-center", (W - 360, 30, W, 500)) > 0.05),
  ("notification centre opens", changed("23-control-center", "24-notification-center", (W - 400, 30, W, 400)) > 0.03),
  ("spotlight opens", changed("27-after-spotlight", "25-spotlight", (W // 2 - 320, int(H * 0.2), W // 2 + 320, int(H * 0.2) + 200)) > 0.02),
  ("spotlight closes", changed("21-shell-window", "27-after-spotlight", (W // 2 - 320, int(H * 0.2), W // 2 + 320, int(H * 0.2) + 200)) < 0.02),
  ("launchpad opens", changed("27-after-spotlight", "28-launchpad", (0, 30, W, H - 120)) > 0.05),
  ("launchpad closes", changed("27-after-spotlight", "29-after-launchpad", (0, 30, W, H - 120)) < 0.01),
]
bad = 0
for name, ok in checks:
    print(("PASS: " if ok else "FAIL: ") + name); bad += not ok
sys.exit(1 if bad else 0)
EOF5
  # lock screen: covers everything, new windows stay hidden, unlock brings the desktop back
  shot 39-before-lock
  qs -p "$SHELLDIR" ipc call lock lock; sleep 1.5; shot 40-locked
  check "lock screen engages" "[ \"\$(qs -p $SHELLDIR ipc call lock isLocked)\" = true ]"
  foot -W 60x10 -T "Sneaky" -e sh -c 'sleep 300' & sleep 1.2; shot 41-locked-new-window
  qs -p "$SHELLDIR" ipc call lock unlockForTest; sleep 1.2; shot 42-unlocked
  pkill -f Sneaky; sleep 0.8
  python3 - "$OUT" <<'EOF8' || fail=1
import sys
from PIL import Image, ImageChops, ImageStat
out = sys.argv[1]
def changed(a, b, box=None):
    A, B = Image.open(f"{out}/{a}.png").convert("RGB"), Image.open(f"{out}/{b}.png").convert("RGB")
    if box: A, B = A.crop(box), B.crop(box)
    d = ImageChops.difference(A, B)
    return ImageStat.Stat(d.convert("L").point(lambda v: 255 if v > 24 else 0)).mean[0] / 255
r = (changed("39-before-lock", "40-locked", (700, 360, 1220, 690)), changed("40-locked", "41-locked-new-window"), changed("39-before-lock", "42-unlocked"))
print("lock changes", [round(x, 4) for x in r])
for name, ok in [("lock screen covers the desktop", r[0] > 0.1), ("windows stay hidden while locked", r[1] < 0.01),
                 ("unlocking shows the desktop again", r[2] < 0.6 and r[2] < r[0])]:
    print(("PASS: " if ok else "FAIL: ") + name)
sys.exit(0 if r[0] > 0.1 and r[1] < 0.01 and r[2] < r[0] else 1)
EOF8
  # X11 apps through xwayland-satellite get the same title bars
  if [ -s "$XDG_RUNTIME_DIR/gosaab-wm.display" ] && command -v xclock >/dev/null; then
    pkill foot; sleep 1
    DISPLAY=$(cat "$XDG_RUNTIME_DIR/gosaab-wm.display") xclock -geometry 300x300 &
    sleep 3; shot 43-x11-app
    check "X11 app opens with a Gill-OSaab title bar" "[ -n \"\$(lights 43-x11-app)\" ] && ! pgrep -x foot >/dev/null"
  else
    echo "FAIL: X11 support (xwayland-satellite) not available"; fail=1
  fi
  # the login screen theme, in SDDM's test mode
  if command -v sddm-greeter-qt6 >/dev/null; then
    pkill xclock; sleep 0.5
    sddm-greeter-qt6 --test-mode --theme "$(pwd)/shell/sddm-theme" >"$OUT/sddm-greeter.log" 2>&1 &
    sleep 4; shot 44-login-screen
    check "login screen theme loads" "! grep -iE 'error|is not a type|ReferenceError|TypeError' $OUT/sddm-greeter.log && pgrep -f sddm-greeter-qt6 >/dev/null"
    pkill -f sddm-greeter-qt6
  fi
  check "shell has no QML errors" "! grep -v -i 'pipewire\|bluetooth\|bluez' $OUT/quickshell.log | grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Could not load icon'"
  grep -E "WARN|ERROR|TypeError|ReferenceError|is not|Cannot" "$OUT/quickshell.log" | sort | uniq -c | sort -rn | head -15
  check "compositor survived the shell" "kill -0 $WM"
  kill $QS 2>/dev/null; pkill foot 2>/dev/null
  kill -TERM $WM 2>/dev/null; wait $WM 2>/dev/null
else
  echo "FAIL: quickshell (qs) is not installed"; fail=1
fi
grep -E "\[ERROR\]|Assertion" "$OUT"/gosaab-wm*.log | head -5
exit $fail
