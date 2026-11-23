#!/usr/bin/env bash
# Gill-OSaab Core only: turn the minimal Fedora base into a booting desktop.
set -euo pipefail

log() { echo "[gill-osaab-core] $*"; }

# Boot to the graphical login
systemctl set-default graphical.target
for unit in sddm.service NetworkManager.service bluetooth.service tuned-ppd.service upower.service \
            fwupd-refresh.timer; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        systemctl enable "$unit"
        log "enabled $unit"
    else
        log "warning: $unit not found"
    fi
done

# Flathub for apps (system-wide, added on first boot when the network is up)
mkdir -p /etc/flatpak/remotes.d
curl -fsSL --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo || log "warning: could not fetch Flathub repo file"

# Plasma on Wayland is the only session
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-gill-osaab.conf <<'EOF'
[General]
DisplayServer=wayland
[Theme]
Current=breeze
EOF

log "core setup complete"
