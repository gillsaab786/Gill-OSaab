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

# Login screen: Gill-OSaab theme, Wayland greeter; sessions: Gill-OSaab desktop + Game Mode
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-gill-osaab.conf <<'EOF'
[General]
DisplayServer=wayland
[Theme]
Current=gill-osaab
CursorTheme=Adwaita
EOF
# Game Mode switching needs no password for the person at the screen (polkit allow_active)
chmod 0755 /usr/libexec/gill-osaab/gosaab-session-select-root 2>/dev/null || true

systemctl enable gosaab-boot-mode.service || log "warning: gosaab-boot-mode not enabled"

# Frame generation (off by default) comes from the lsfg-vk package (recipe); games opt in from
# Settings > Game Mode or with the launch option LSFG_PROCESS=gosaab %command%
ls /usr/share/vulkan/implicit_layer.d/ 2>/dev/null | grep -qi lsfg || log "warning: lsfg-vk layer not installed"

# Wine: make sure the plain "wine" command exists (Fedora may only ship it via alternatives)
if [ ! -e /usr/bin/wine ]; then
    for c in /etc/alternatives/wine /usr/bin/wine64 /usr/bin/wine-stable /usr/lib64/wine/x86_64-unix/wine /usr/lib/wine/wine64; do
        if [ -x "$c" ]; then ln -sf "$c" /usr/bin/wine; log "wine -> $c"; break; fi
    done
    [ -e /usr/bin/wine ] || log "warning: no wine binary found: $(ls /usr/bin | grep -i wine | tr '\n' ' ')"
fi

log "core setup complete"
