#!/bin/sh
# Get scenefx 0.5 and add Gill(OS)'s Liquid Glass lens, with retries (network hiccups happen
# during image builds). Meson then uses subprojects/scenefx as is.
set -e
cd "$(dirname "$0")/subprojects"
[ -f scenefx/.gosaab-patched ] && exit 0
rm -rf scenefx
for try in 1 2 3 4 5 6; do
  git clone -q -c advice.detachedHead=false --depth 1 --branch 0.5 https://github.com/wlrfx/scenefx.git scenefx && break
  rm -rf scenefx
  echo "scenefx download failed (try $try), retrying..." >&2
  sleep $((try * 10))
done
[ -d scenefx ] || { echo "could not download scenefx" >&2; exit 1; }
git -C scenefx apply ../packagefiles/scenefx-lens.patch
touch scenefx/.gosaab-patched
