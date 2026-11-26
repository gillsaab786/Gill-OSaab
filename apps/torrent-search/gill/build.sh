#!/bin/sh
# Build Torrent Search Engine for Gill(OS): Flutter's Linux desktop target, from the same code as
# the iPhone app. Usage: build.sh <app folder> <output folder>   (SKIP_TESTS=1 to skip flutter test)
set -eu
APP=$(cd "$1" && pwd)
OUT=$2
if ! command -v flutter >/dev/null; then
  if [ ! -x /opt/flutter/bin/flutter ]; then
    for try in 1 2 3; do
      git clone -q --depth 1 -b stable https://github.com/flutter/flutter /opt/flutter && break
      rm -rf /opt/flutter; sleep $((try * 10))
    done
  fi
  export PATH=/opt/flutter/bin:$PATH
fi
git config --global --add safe.directory /opt/flutter 2>/dev/null || true
export FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=${PUB_CACHE:-/tmp/pub-cache}
flutter config --no-analytics --enable-linux-desktop >/dev/null 2>&1 || true
flutter --version | head -1
cd "$APP"
if [ ! -d linux ]; then
  flutter create --platforms=linux --project-name seedfinder --org org.gillosaab . >/dev/null
  # flutter create adds a sample test for a counter app we don't have
  grep -q "MyApp" test/widget_test.dart 2>/dev/null && rm -f test/widget_test.dart
  python3 gill/patch_runner.py .
fi
flutter pub get
if [ "${SKIP_TESTS:-}" != 1 ]; then
  flutter analyze --no-fatal-infos --no-fatal-warnings lib || true
  flutter test
fi
flutter build linux --release
mkdir -p "$OUT"
cp -a build/linux/x64/release/bundle/. "$OUT/"
echo "built: $OUT"
