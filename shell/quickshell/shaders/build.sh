#!/bin/sh
# Compile the live wallpapers' shaders (*.frag -> *.frag.qsb) with Qt's shader baker (qsb), so
# they match the Qt the shell runs on. Usage: build.sh [folder]
dir=${1:-$(dirname "$0")}
qsb=$(command -v qsb || command -v qsb-qt6 || ls /usr/lib64/qt6/bin/qsb /usr/lib/qt6/bin/qsb 2>/dev/null | head -1)
[ -n "$qsb" ] || qsb=$(command -v pyside6-qsb)
if [ -z "$qsb" ]; then
  echo "qsb not found: live wallpapers will show their still pictures"
  exit 0
fi
for f in "$dir"/*.frag; do
  "$qsb" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$f.qsb" "$f" || { echo "shader failed: $f"; exit 1; }
done
echo "live wallpaper shaders built with $qsb"
