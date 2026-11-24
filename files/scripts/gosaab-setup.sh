#!/usr/bin/env bash
# Runs once at image build time.
set -euo pipefail

log() { echo "[gill-osaab] $*"; }

# Executables
chmod 0755 /usr/bin/gosaab-* /usr/libexec/gill-osaab/* 2>/dev/null || true

# --- Updates: Gill-OSaab's own updater replaces the stock ones so the
# on/off switches in /etc/gill-osaab/updates.conf are the single source of truth.
# bootc-fetch-apply-updates restarts the PC by itself (mid-game!) — ours asks first
for unit in uupd.timer rpm-ostreed-automatic.timer flatpak-system-update.timer bootc-fetch-apply-updates.timer; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        systemctl disable "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
        log "disabled stock updater $unit"
    fi
done
systemctl --global disable flatpak-user-update.timer >/dev/null 2>&1 || true
systemctl enable gosaab-update.timer

# --- Security: no remote login by default (the test build has a known password)
for unit in sshd.service sshd.socket; do systemctl disable "$unit" >/dev/null 2>&1 || true; done
systemctl enable gosaab-security-check.service gosaab-security-check.path || log "warning: security check not enabled"

# --- Drivers: record every part, install missing firmware/driver updates; Problems page; battery limit
systemctl enable gosaab-drivers.timer gosaab-battery.service gosaab-battery.path || log "warning: driver units"
systemctl --global enable gosaab-diagnose.timer || log "warning: could not enable problem check"
# Smart TDP (power follows what you do) and graphics switching on PCs with two graphics chips
systemctl enable gosaab-smart-power.service || log "warning: smart power not enabled"
# Driver search: describe every built-in driver once, at build time
/usr/bin/gosaab-drivers index /usr/share/gill-osaab/driver-index.json || log "warning: driver index not built"

# --- Notifications in Game Mode (starts and stops with the Steam session)
systemctl --global enable gosaab-notify-hub.service || log "warning: could not enable notify hub"
systemctl enable gosaab-decky-sync.service

# --- Performance: gaming CPU scheduler (scx_lavd) when the loader exists
if systemctl list-unit-files scx_loader.service >/dev/null 2>&1; then
    systemctl enable scx_loader.service || log "warning: could not enable scx_loader"
else
    log "scx_loader not in base image; skipping scheduler setup"
fi

# --- App launcher: make gosaab-open the default for app files, keeping the
# base image's other defaults, then refresh caches
python3 - <<'EOF'
import configparser, pathlib
target = pathlib.Path("/etc/xdg/mimeapps.list")
ours = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
ours.optionxform = str
ours.read("/usr/share/gill-osaab/mimeapps-defaults.list")
cfg = configparser.ConfigParser(interpolation=None, strict=False, allow_no_value=True, delimiters=("=",))
cfg.optionxform = str
if target.exists():
    cfg.read(target)
if not cfg.has_section("Default Applications"):
    cfg.add_section("Default Applications")
for key, value in ours["Default Applications"].items():
    cfg["Default Applications"][key] = value
target.parent.mkdir(parents=True, exist_ok=True)
with open(target, "w") as fh:
    cfg.write(fh, space_around_delimiters=False)
EOF
update-desktop-database /usr/share/applications || true

# --- Look and feel: system-wide KDE defaults (merged, base settings kept)
python3 - <<'EOF'
import configparser, pathlib

FONT = "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
DEFAULTS = {
    "/etc/xdg/kdeglobals": {
        "KDE": {"LookAndFeelPackage": "org.gillosaab.desktop", "widgetStyle": "Breeze",
                "AnimationDurationFactor": "0.8"},
        "Sounds": {"Enable": "true", "Theme": "ocean"},
        "General": {"ColorScheme": "GillOSaabDark", "font": FONT, "menuFont": FONT,
                    "toolBarFont": "Inter,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1",
                    "smallestReadableFont": "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"},
        "WM": {"activeFont": "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"},
        "Icons": {"Theme": "Papirus-Dark"},
    },
    "/etc/xdg/kwinrc": {
        # macOS/iOS feel: windows zoom open/closed, minimise into the dock like a genie,
        # dialogs slide down as sheets, glass blur, Mission Control-style overview
        "Plugins": {"blurEnabled": "true", "contrastEnabled": "true", "magiclampEnabled": "true",
                    "squashEnabled": "false", "scaleEnabled": "true", "glideEnabled": "false",
                    "fadeEnabled": "false", "sheetEnabled": "true", "dimscreenEnabled": "true",
                    "overviewEnabled": "true", "slideEnabled": "true", "shakecursorEnabled": "true",
                    "wobblywindowsEnabled": "false"},
        "Effect-magiclamp": {"AnimationDuration": "300"},
        "org.kde.kdecoration2": {"library": "org.kde.breeze", "theme": "Breeze",
                                 "ButtonsOnLeft": "XIA", "ButtonsOnRight": ""},
        "WindowSwitcher": {"LayoutName": "thumbnail_grid"},
    },
    "/etc/xdg/kscreenlockerrc": {
        "Greeter][Wallpaper][org.kde.image][General": {"Image": "file:///usr/share/wallpapers/GillOSaab/"},
    },
}

for path, groups in DEFAULTS.items():
    cfg = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",), allow_no_value=True)
    cfg.optionxform = str
    p = pathlib.Path(path)
    if p.exists():
        cfg.read(p)
    for group, keys in groups.items():
        if not cfg.has_section(group):
            cfg.add_section(group)
        for k, v in keys.items():
            cfg[group][k] = v
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w") as fh:
        cfg.write(fh, space_around_delimiters=False)
    print("[gill-osaab] defaults merged into", path)
EOF

# Login screen wallpaper (SDDM Breeze theme), when present
if [ -d /usr/share/sddm/themes/breeze ]; then
    printf '[General]\nbackground=/usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png\n' \
        > /usr/share/sddm/themes/breeze/theme.conf.user
fi

gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true

log "setup complete"
