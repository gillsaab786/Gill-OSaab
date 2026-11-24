#!/usr/bin/env bash
# Face unlock engine (Howdy 3) built from a reviewed source version, because the unofficial Fedora
# packages lag behind new Fedora releases. Called by gosaab-core-setup.sh; never fails the image build.
set -uo pipefail
log() { echo "[gill-osaab howdy] $*"; }
command -v howdy >/dev/null && { log "already installed"; exit 0; }
HOWDY_COMMIT=a8a3b29c53c430f6ffdbf6cc742be5eac325b94e # boltgolt/howdy master (3.0.2), reviewed
dnf -y install gcc-c++ meson ninja-build pam-devel libevdev-devel inih-devel python3-opencv python3-dlib \
    python3-numpy bzip2 >/dev/null || { log "dependencies missing on this Fedora: face unlock left out"; exit 0; }
src=/tmp/howdy-src
rm -rf "$src"
for try in 1 2 3; do
    git clone -q https://github.com/boltgolt/howdy "$src" && git -C "$src" checkout -q "$HOWDY_COMMIT" && break
    sleep $((try * 10))
done
[ -d "$src/howdy" ] || { log "source not reachable: face unlock left out"; exit 0; }
cd "$src/howdy" || exit 0
if meson setup build --prefix=/usr -Dpython_path=/usr/bin/python3 -Dinstall_config=true >/tmp/howdy-meson.log 2>&1 &&
   meson compile -C build >>/tmp/howdy-meson.log 2>&1 && meson install -C build >>/tmp/howdy-meson.log 2>&1; then
    # the face models (dlib), about 30 MB
    data=$(find /usr/share -maxdepth 2 -type d -name dlib-data | head -1)
    if [ -n "$data" ]; then
        (cd "$data" && for m in dlib_face_recognition_resnet_model_v1 mmod_human_face_detector shape_predictor_5_face_landmarks; do
            curl -fsSL --retry 5 -o "$m.dat.bz2" "https://github.com/davisking/dlib-models/raw/master/$m.dat.bz2" &&
                bunzip2 -f "$m.dat.bz2"
        done)
    fi
    command -v howdy >/dev/null && log "installed $(howdy --version 2>/dev/null | head -1)" || log "built, but no howdy command"
else
    log "build failed: face unlock left out"; tail -n 25 /tmp/howdy-meson.log
fi
rm -rf "$src"
exit 0
