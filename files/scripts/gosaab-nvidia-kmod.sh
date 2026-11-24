#!/usr/bin/env bash
# Nvidia driver for Gill-OSaab Core: builds Nvidia's open kernel module for the image's kernel
# (RPM Fusion akmod) and adds the user-space driver, including 32-bit parts Steam games need.
# Older cards (GTX 10 and earlier) keep using the open NVK/nouveau driver.
set -euo pipefail
log() { echo "[gill-osaab nvidia] $*"; }

kver=$(ls /usr/lib/modules | head -1)
log "kernel $kver"
if ! dnf install -y "kernel-devel-$kver"; then
    # the image's kernel can be older than the newest one in the repos: fetch the exact match
    v=${kver%%-*}; rest=${kver#*-}; r=${rest%.*}; arch=${rest##*.}
    dnf install -y "https://kojipkgs.fedoraproject.org/packages/kernel/$v/$r/$arch/kernel-devel-$kver.rpm"
fi

echo "%_with_kmod_nvidia_open 1" > /etc/rpm/macros.nvidia-kmod   # open module: Turing (RTX 20/GTX 16) and newer
dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 \
    xorg-x11-drv-nvidia-cuda-libs nvidia-modprobe libva-nvidia-driver
dnf install -y --skip-unavailable nvidia-settings xorg-x11-drv-nvidia-power

akmods --force --kernels "$kver" --kmod nvidia || true
if ! find "/usr/lib/modules/$kver" -name 'nvidia.ko*' | grep -q .; then
    log "ERROR: nvidia module not built; build log:"
    tail -n 80 /var/cache/akmods/nvidia/*.failed.log 2>/dev/null || true
    exit 1
fi
log "built: $(modinfo -k "$kver" -F version nvidia)"

# load Nvidia's driver instead of nouveau, with modesetting for Wayland/gamescope
mkdir -p /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/00-gill-osaab-nvidia.toml <<'TOML'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "nvidia-drm.fbdev=1"]
TOML
cat > /usr/lib/modprobe.d/gill-osaab-nvidia.conf <<'CONF'
blacklist nouveau
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
CONF
for unit in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service nvidia-powerd.service; do
    systemctl enable "$unit" 2>/dev/null || true
done
echo "nvidia" > /usr/share/gill-osaab/edition-gpu
log "done"
