#!/bin/bash
# Shrink the USB image's btrfs system partition to what it uses + headroom, and cut the image file
# there (bootc-image-builder makes it ~2x the system size). gosaab-grow-usb grows it back to fill
# the stick on the first start.   sudo tools/shrink-usb-image.sh IMAGE.raw [HEADROOM_GIB]
set -euo pipefail
img=$1 headroom=${2:-2}
GIB=$((1024 * 1024 * 1024))
loop=$(losetup -fP --show "$img")
trap 'umount "$mnt" 2>/dev/null || true; losetup -d "$loop" 2>/dev/null || true' EXIT
udevadm settle || true
root=$(lsblk -lnpo NAME,FSTYPE "$loop" | awk '$2 == "btrfs" {print $1}' | head -1)
pn() { cat "/sys/class/block/$(basename "$1")/partition" 2>/dev/null; }
num=$(pn "$root")
last=$(for d in $(lsblk -lnpo NAME "$loop"); do pn "$d"; done | sort -n | tail -1)
[ -n "$root" ] && [ "$num" = "$last" ] || { echo "system partition isn't the last btrfs one; not shrinking"; exit 0; }
mnt=$(mktemp -d)
mount "$root" "$mnt"
used=$(btrfs filesystem usage -b "$mnt" | awk '/^ *Used:/ {print $2; exit}')
target=$(( (used + headroom * GIB + GIB - 1) / GIB * GIB ))
cur=$(blockdev --getsize64 "$root")
echo "system: $(( used / 1048576 )) MiB used, partition $(( cur / 1048576 )) MiB -> $(( target / 1048576 )) MiB"
if [ "$target" -ge "$cur" ]; then echo "already small"; exit 0; fi
btrfs filesystem resize "$target" "$mnt"
umount "$mnt"
start=$(cat "/sys/class/block/$(basename "$root")/start")
losetup -d "$loop"
trap - EXIT
sectors=$(( target / 512 + 2048 ))  # 1 MiB slack past the filesystem
echo ", $sectors" | sfdisk --no-reread --force -N "$num" "$img"
truncate -s $(( (start + sectors) * 512 + 2 * 1048576 )) "$img"
sfdisk --relocate gpt-bak-std "$img"
sfdisk --verify "$img"
# check it still mounts and the system is all there
loop=$(losetup -fP --show "$img")
udevadm settle || true
root=$(lsblk -lnpo NAME,FSTYPE "$loop" | awk '$2 == "btrfs" {print $1}' | head -1)
btrfs check --readonly "$root"
mount -o ro "$root" "$mnt"
find "$mnt" -maxdepth 3 -name ostree -print -quit | grep -q . || { echo "no ostree in the shrunk image"; exit 1; }
df -h "$mnt" | tail -1
umount "$mnt"
losetup -d "$loop"
echo "image now $(( $(stat -c %s "$img") / 1048576 )) MiB"
