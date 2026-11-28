#!/bin/bash
# CI: a small stand-in for the USB stick — publish-size image written to a bigger "stick", then
# gosaab-grow-usb must grow the system partition and btrfs to fill it.   sudo tools/test-grow-usb.sh
set -euo pipefail
d=$(mktemp -d)
img=$d/stick.img
truncate -s 600M "$img"
printf 'label: gpt\n,64M,U\n,,L\n' | sfdisk -q "$img"
loop=$(losetup -fP --show "$img"); udevadm settle || true
mkfs.btrfs -q -f "${loop}p2"
losetup -d "$loop"
truncate -s 2G "$img"                      # flashed onto a bigger stick
loop=$(losetup -fP --show "$img"); udevadm settle || true
mkdir -p "$d/m"; mount "${loop}p2" "$d/m"
before=$(btrfs filesystem usage -b "$d/m" | awk '/Device size:/ {print $3; exit}')
bash files/core-system/usr/libexec/gill-osaab/gosaab-grow-usb --disk "$loop" --part 2 --mount "$d/m"
after=$(btrfs filesystem usage -b "$d/m" | awk '/Device size:/ {print $3; exit}')
bash files/core-system/usr/libexec/gill-osaab/gosaab-grow-usb --disk "$loop" --part 2 --mount "$d/m"  # 2nd run: nothing
umount "$d/m"; sfdisk --verify "$loop"; losetup -d "$loop"
echo "btrfs $(( before / 1048576 )) MiB -> $(( after / 1048576 )) MiB"
[ "$after" -gt $(( 1800 * 1048576 )) ] || { echo "FAIL: did not grow"; exit 1; }
echo "PASS: grows to fill the stick"
