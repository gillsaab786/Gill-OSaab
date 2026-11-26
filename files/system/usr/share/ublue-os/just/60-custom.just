# Gill(OS) commands. Run with:  ujust <name>

# Show Gill(OS) status: update switches and components
gosaab-status:
    #!/usr/bin/bash
    echo "== Gill(OS) $(cat /usr/share/gill-osaab/version 2>/dev/null) =="
    gosaab-updates
    echo
    for tool in wine bwrap waydroid distrobox; do
        if command -v "$tool" >/dev/null; then echo "ready      $tool"; else echo "missing    $tool"; fi
    done
    systemctl is-active --quiet scx_loader.service && echo "ready      gaming CPU scheduler" || echo "off        gaming CPU scheduler"
    grep -q '^ntsync ' /proc/modules && echo "ready      ntsync" || echo "off        ntsync"

# Apply the Gill(OS) desktop look (top bar + floating dock). Resets panels.
gosaab-apply-look:
    plasma-apply-lookandfeel --apply org.gillosaab.desktop --resetLayout

# One-time Android (Waydroid) setup so .apk files open with a double-click
gosaab-setup-android:
    ujust setup-waydroid

# Screen off while downloads/copies run; wakes when done
gosaab-screen-off:
    gosaab-screen-off

# Screen off, then sleep after the task finishes (Overnight / Work)
gosaab-overnight:
    gosaab-screen-off --overnight

# Turn every update off / back on
gosaab-updates-off:
    gosaab-updates all off

gosaab-updates-on:
    gosaab-updates all on

# Install XREAL glasses support for games (Breezy Vulkan by wheaney; trial, then paid features)
gosaab-install-xreal:
    #!/usr/bin/bash
    set -euo pipefail
    echo "This installs Breezy Vulkan (XREAL head tracking and virtual screen in games)."
    echo "Breezy has a free trial; some features need a paid licence afterwards."
    read -r -p "Continue? [y/N] " answer
    [[ "${answer,,}" == "y" ]] || exit 0
    tmp=$(mktemp -d)
    curl -fL --retry 3 -o "$tmp/breezy_vulkan_setup" \
        https://github.com/wheaney/breezy-desktop/releases/latest/download/breezy_vulkan_setup
    chmod +x "$tmp/breezy_vulkan_setup"
    sudo "$tmp/breezy_vulkan_setup"

# Notifications + live progress in Game Mode (installs Decky Loader if needed)
gosaab-setup-notifications:
    #!/usr/bin/bash
    set -euo pipefail
    if ! systemctl list-unit-files plugin_loader.service >/dev/null 2>&1; then
        echo "Installing Decky Loader first..."
        ujust setup-decky
    fi
    sudo /usr/libexec/gill-osaab/gosaab-decky-sync
    echo "Done. Open Quick Access (Armoury Crate / ... button) > Decky > Gill(OS) Notifications."

# Update everything (system, Android, Proton-GE, Windows app setups, apps, containers, plugins)
gosaab-update-all:
    gosaab-update-component all

# Update all drivers (kernel, graphics, Wi-Fi, audio) and device firmware
gosaab-update-drivers:
    gosaab-update-component drivers

# Update the BIOS when the maker publishes it to LVFS
gosaab-update-bios:
    gosaab-update-component bios
