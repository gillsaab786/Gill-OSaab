#!/usr/bin/env bash
# Gill(OS) Core only: turn the minimal Fedora base into a booting desktop.
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

# Login screen: Gill(OS) theme, Wayland greeter; sessions: Gill(OS) desktop + Game Mode
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
systemctl enable gosaab-android-folders.service || log "warning: android folders not enabled"
# printers/scanners appear by themselves (driverless IPP, USB printers), firmware updates
for unit in cups.socket ipp-usb.service fwupd-refresh.timer; do systemctl enable "$unit" 2>/dev/null || true; done

# Face unlock for the lock screen (Howdy; infrared "Windows Hello" cameras). Optional: its unofficial
# Fedora packages sometimes lag behind a new Fedora, so a failure here never breaks the build.
repo=/etc/yum.repos.d/gosaab-howdy.repo
if curl -fsSL --retry 2 -o "$repo" \
    "https://copr.fedorainfracloud.org/coprs/ronnypfannschmidt/howdy-beta/repo/fedora-$(rpm -E %fedora)/ronnypfannschmidt-howdy-beta-fedora-$(rpm -E %fedora).repo"; then
    dnf -y install howdy >/dev/null 2>&1 && log "face unlock: howdy installed" || log "note: howdy not installable on this Fedora yet"
fi
rm -f "$repo"
bash "$(dirname "$(readlink -f "$0")")/gosaab-howdy.sh" || true

# Button/combo shortcuts (handheld buttons, Windows+R -> Game Mode) in both sessions
systemctl enable gosaab-hotkeyd.service || log "warning: shortcut service not enabled"
systemctl enable thermald.service 2>/dev/null || true  # Intel only (see its drop-in)
# After "Install on this PC (encrypted)": your account is created on the first start
systemctl enable gosaab-firstboot-user.service || log "warning: first-boot account service not enabled"

# Firewall: nothing on this PC is reachable from the network unless allowed. Allowed: finding printers
# and other devices (mDNS), Steam Remote Play/LAN game downloads; Android (Waydroid) gets its own
# trusted network link so its apps keep internet access.
if [ -f /etc/firewalld/firewalld.conf ]; then  # zones: /etc/firewalld/zones (public = ours)
    sed -i 's/^DefaultZone=.*/DefaultZone=public/' /etc/firewalld/firewalld.conf
    systemctl enable firewalld.service || log "warning: firewalld not enabled"
else
    log "warning: firewalld missing"
fi

# Frame generation (off by default) comes from the lsfg-vk package (recipe); games opt in from
# Settings > Game Mode or with the launch option LSFG_PROCESS=gosaab %command%
ls /usr/share/vulkan/implicit_layer.d/ 2>/dev/null | grep -qi lsfg || log "warning: lsfg-vk layer not installed"

# Brave installs into /opt, which on this kind of system is per-machine state (/var/opt) and is
# not shipped in the image: keep Brave in /usr/lib and point /opt/brave.com at it on every boot.
if [ ! -x /usr/lib/brave.com/brave/brave ]; then
    if [ ! -e /opt/brave.com/brave/brave ]; then
        opt_link=$(readlink /opt || true)
        [ -L /opt ] && rm /opt && mkdir /opt
        dnf -y reinstall brave-browser >/dev/null 2>&1 || dnf -y install brave-browser >/dev/null 2>&1 || true
    fi
    if [ -d /opt/brave.com ]; then
        mv /opt/brave.com /usr/lib/brave.com
        log "Brave kept in /usr/lib/brave.com"
    fi
    if [ -n "${opt_link:-}" ] && [ -d /opt ] && [ ! -L /opt ]; then
        rmdir /opt 2>/dev/null && ln -s "$opt_link" /opt
    fi
fi
mkdir -p /usr/lib/tmpfiles.d
printf 'd /var/opt 0755 root root -\nL+ /var/opt/brave.com - - - - /usr/lib/brave.com\n' > /usr/lib/tmpfiles.d/gill-osaab-brave.conf

# Brave and VLC run sandboxed: each sees only its own data plus up to two folders you allow
for pair in brave-browser:brave com.brave.Browser:brave vlc:vlc org.videolan.VLC:vlc; do
    desktop=/usr/share/applications/${pair%%:*}.desktop
    [ -f "$desktop" ] && sed -i "s#^Exec=\(gosaab-sandbox [^ ]* \)\?#Exec=gosaab-sandbox ${pair##*:} #" "$desktop" &&
        log "sandboxed ${pair%%:*}" || true
done

# Boot screen: Liquid Glass progress ring with percentage (needs the initramfs rebuilt with it)
if command -v plymouth-set-default-theme >/dev/null; then
    plymouth-set-default-theme gill-osaab || log "warning: could not set boot theme"
    KVER=$(ls /usr/lib/modules | head -1)
    if [ -n "$KVER" ] && command -v dracut >/dev/null; then
        dracut --no-hostonly --kver "$KVER" --reproducible --add ostree -f "/usr/lib/modules/$KVER/initramfs.img" \
            >/dev/null 2>&1 && log "boot screen in initramfs ($KVER)" || log "warning: initramfs not rebuilt"
    fi
fi

# Wine: make sure the plain "wine" command exists (Fedora may only ship it via alternatives)
if [ ! -e /usr/bin/wine ]; then
    for c in /etc/alternatives/wine /usr/bin/wine64 /usr/bin/wine-stable /usr/lib64/wine/x86_64-unix/wine /usr/lib/wine/wine64; do
        if [ -x "$c" ]; then ln -sf "$c" /usr/bin/wine; log "wine -> $c"; break; fi
    done
    [ -e /usr/bin/wine ] || log "warning: no wine binary found: $(ls /usr/bin | grep -i wine | tr '\n' ' ')"
fi

# Name shown at boot, in the boot menu and in "About": Gill(OS). ID stays fedora so updates keep working.
if [ -f /usr/lib/os-release ]; then
    sed -i -e 's/^NAME=.*/NAME="Gill(OS)"/' -e 's/^PRETTY_NAME=.*/PRETTY_NAME="Gill(OS) Core"/' \
        -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="gill-os"/' /usr/lib/os-release
    grep -q '^VARIANT=' /usr/lib/os-release || echo 'VARIANT="Core"' >> /usr/lib/os-release
    log "os-release: $(grep ^PRETTY_NAME /usr/lib/os-release)"
fi

log "core setup complete"
