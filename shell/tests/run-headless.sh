#!/usr/bin/env bash
# Runs gosaab-wm with no screen (headless) on a virtual GPU, opens real apps,
# takes screenshots at key moments and checks the results.
# Usage: run-headless.sh <build dir> <output dir>
set -u
BUILD=${1:-shell/compositor/build}
OUT=${2:-artifacts}
WALL=files/system/usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png
mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/gosaab-xdg
rm -rf "$XDG_RUNTIME_DIR" && mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 GOSAAB_HEADLESS_SIZE=1920x1080
unset WAYLAND_DISPLAY

# Use the virtual KMS card (vkms) for rendering
for card in /sys/class/drm/card[0-9]*; do
  drv=$(basename "$(readlink -f "$card/device/driver" 2>/dev/null)")
  echo "$(basename "$card"): $drv"
  # vkms shows up as "vkms" or, on newer kernels, "faux_driver"
  if [ "$drv" = vkms ] || [ "$drv" = faux_driver ]; then
    WLR_RENDER_DRM_DEVICE=/dev/dri/$(basename "$card")
    export WLR_RENDER_DRM_DEVICE
  fi
done
echo "render device: ${WLR_RENDER_DRM_DEVICE:-auto}"

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
shot() { grim "$OUT/$1.png" && echo "shot $1"; }

"$BUILD/gosaab-wm" -s "swaybg -i $WALL -m fill" >"$OUT/gosaab-wm.log" 2>&1 &
WM=$!
for _ in $(seq 1 50); do [ -s "$XDG_RUNTIME_DIR/gosaab-wm.socket" ] && break; sleep 0.1; done
check "compositor starts" "[ -s $XDG_RUNTIME_DIR/gosaab-wm.socket ] && kill -0 $WM"
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
checks = [
    ("wallpaper is drawn (not a flat colour)", ImageStat.Stat(load("01-wallpaper")).stddev[0] > 5),
    ("a window appears", diff("01-wallpaper", "03-one-window") > 2),
    ("second window appears", diff("03-one-window", "04-two-windows") > 1),
    ("closing removes the window", diff("04-two-windows", "06-after-close") > 1),
    ("after close matches one window", diff("03-one-window", "06-after-close") < 1.5),
]
bad = 0
for name, ok in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
    bad += not ok
print("diffs:", {k: round(diff(*k.split("|")), 2) for k in ["01-wallpaper|03-one-window", "03-one-window|06-after-close", "02-opening|03-one-window", "05-closing|06-after-close"]})
sys.exit(1 if bad else 0)
EOF

kill $WM 2>/dev/null
wait $WM 2>/dev/null
tail -20 "$OUT/gosaab-wm.log"
exit $fail
