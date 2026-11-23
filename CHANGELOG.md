# Changelog

## 1.2.0 (2026-11-23)

- Settings redesign: reorganised Updates page, new Device & Drivers page, iOS-style HD icon
  tiles (1x/2x/3x), search, page transitions
- Per-part updates with versions: system, Android image, Proton-GE (latest, checksum-verified),
  Windows app setups, apps, containers, Game Mode plugins, plus Update everything
- Hardware detection (model, BIOS, CPU, GPUs, Wi-Fi/Ethernet and their drivers)
- Update all drivers, device firmware and BIOS through fwupd/LVFS; maker support page when the
  BIOS isn't published there
- Nvidia desktop edition (on bazzite-nvidia-open) with a one-tap switch when an Nvidia GPU is found
- macOS-style motion defaults: scale open/close, magic lamp, sheets, overview, timing, sounds
- 81 tests

## 1.1.0 (2026-11-23)

- Notifications with live progress in Game Mode: `gosaab-notify-hub` takes the standard
  notification, KDE job (V1 + V2) and launcher-progress services in the Steam session
- Gill-OSaab Notifications Decky plugin: pop-ups and a Quick Access tab with progress bars,
  Cancel, Dismiss, Clear all; auto-installed and updated at boot when Decky is present
- `gosaab-open` reports live progress (works in desktop mode and Game Mode)
- Settings: Game Mode notifications status line
- 53 tests, including a live D-Bus test of the hub

## 1.0.0 (2026-11-23)

First build (Phase 1 and part of Phase 2).

- Handheld and desktop editions on Bazzite, built by GitHub Actions with keyless signing
- `gosaab-open`: one-click .exe/.msi (sandboxed Wine), .apk, .AppImage, .deb, .rpm, Flatpak
- Gill-OSaab Settings app with update switches (All / OS / Apps / Containers), sandbox, screen-off, appearance
- Own updater (`gosaab-update.timer`) replacing stock updaters, respecting the switches
- Screen-off mode with auto wake and Overnight / Work option
- Gill-OSaab look: colour schemes, top bar + floating dock layout, Inter + Papirus, Aurora wallpaper, logo
- NTSYNC and scx_lavd gaming scheduler
- 47 unit tests
