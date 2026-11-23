# Gill-OSaab

Gill-OSaab is your own OS for handhelds and PCs. Developer: GILL-Saab.
It's built on [Bazzite](https://bazzite.gg) (Fedora Atomic), so you get SteamOS-style Game Mode,
handheld support (ROG Ally, GPD Win Max 2, Steam Deck) and rollback-safe updates, plus the
Gill-OSaab features below.

| Edition | Image | For |
| --- | --- | --- |
| Handheld | `ghcr.io/gillsaab786/gill-osaab` | ROG Ally, GPD Win Max 2, Steam Deck. Boots into Game Mode |
| Desktop | `ghcr.io/gillsaab786/gill-osaab-desktop` | Intel/AMD desktops and laptops. Boots to the desktop |

## What's in 1.1.0

**One-click apps** (`gosaab-open`, the default for these files):

| File | Runs through |
| --- | --- |
| `.exe` `.msi` | Wine, each app in its own sandbox (bubblewrap): it sees only its own folder, never your files |
| `.apk` | Waydroid (Android) |
| `.AppImage` | Copied to `~/Applications`, added to the app menu |
| `.deb` / `.rpm` | Ubuntu / Fedora container (distrobox), added to the app menu |
| `.flatpakref` `.flatpak` | Flatpak |

**Gill-OSaab Settings** (app menu): iOS-style switches for
- Updates: **All updates** master switch, plus OS, Apps and emulators, Linux containers
- Windows app sandbox on/off
- Screen-off mode: Overnight / Work option, wake-after-idle time
- Appearance: Dark (default) / Light, Night light, re-apply the Gill-OSaab look
- Optional features (all off by default; shown as "coming in a later update")
- Status of every component

**Screen-off mode** (`gosaab-screen-off`): turns off only the display while downloads, copies,
installs or Steam downloads run. The device stays awake and the screen comes back with "Done"
when the work finishes. Run it again to wake early. `--overnight` sleeps after "Done".

**Notifications with live progress, in desktop mode and Game Mode**: downloads, file copies,
installs and app notifications show percentages, like Android. In desktop mode KDE Plasma's
notification panel shows them. In Game Mode the Gill-OSaab hub collects them and the
**Gill-OSaab Notifications** Decky plugin shows pop-ups plus a Quick Access tab with live progress
bars, Cancel and Dismiss. Anything that reports progress the standard Linux ways appears: KDE jobs
(Dolphin, KIO), the notification progress hint and launcher progress bars (Chromium-based
browsers). Apps that never report a percentage, like Firefox without its browser extension or
Windows apps, still show their normal notifications. Gill-OSaab's own installer reports progress too.

**Look and feel**: dark Gill-OSaab colour scheme with a teal accent, Inter font, Papirus icons,
a macOS-style top bar (menu, app menu, tray, clock) and a floating, centred dock that moves out of
the way of windows. Window buttons sit on the left, Magic Lamp minimise and blur are on, and the
original Gill-OSaab Aurora wallpaper (dark and light) also appears on the lock and login screens.

**Performance**: NTSYNC loaded for Proton/Wine, gaming CPU scheduler (scx_lavd) enabled, and
Gill-OSaab's own updater replaces the stock one so the switches are the only thing that decides
what updates.

## Install on the GPD Win Max 2 (test device first)

1. Install stock **Bazzite** on the GPD from [bazzite.gg](https://bazzite.gg) (choose the handheld/Deck edition).
2. On GitHub: **Packages → gill-osaab → Package settings → Change visibility → Public** (once only).
3. Open a terminal on the GPD and run:
   ```
   rpm-ostree rebase ostree-unverified-registry:ghcr.io/gillsaab786/gill-osaab:latest
   systemctl reboot
   ```
4. In desktop mode, apply the look once: `ujust gosaab-apply-look` (new users get it automatically).
5. One-time Android setup: `ujust setup-waydroid`.
6. Game Mode notifications: `ujust gosaab-setup-notifications` (installs Decky Loader if needed;
   the plugin then updates itself with every Gill-OSaab update).

Going back is one command: `rpm-ostree rollback` (or pick the previous entry at boot).

## Commands

| Command | Does |
| --- | --- |
| `gosaab-settings` | Settings app |
| `gosaab-open FILE` | Install or run any app (`--dry-run` shows the plan) |
| `gosaab-updates` | Show switches; `gosaab-updates all off`, `os on`, `now` |
| `gosaab-screen-off` | Screen off until tasks finish; `--overnight` |
| `ujust gosaab-status` | Check every component |
| `ujust gosaab-setup-notifications` | Game Mode notifications and progress (Decky plugin) |
| `ujust gosaab-install-xreal` | XREAL glasses support for games (Breezy; trial, then paid features) |

## Phase 1 test checklist (GPD)

- [ ] Boots into Game Mode; Desktop mode works
- [ ] Controller, back buttons, TDP slider, sleep/resume
- [ ] Wi-Fi, Bluetooth, audio, brightness
- [ ] Double-click a small `.exe` (e.g. Notepad++ installer): installs, menu entry launches it
- [ ] Double-click an `.apk` after `ujust setup-waydroid`
- [ ] Double-click an `.AppImage` and a `.deb`
- [ ] Gill-OSaab Settings: flip each update switch and reopen; the switches persist
- [ ] Screen-off during a Firefox download; the screen returns when it finishes
- [ ] Game Mode: copy a big file in Desktop mode's Dolphin, switch to Game Mode, and check Quick
      Access > Gill-OSaab Notifications shows its progress; pop-up when done
- [ ] Top bar + dock + wallpaper look right, Dark/Light switch works
- [ ] `ujust gosaab-status` shows everything ready

## Building

GitHub Actions builds both editions daily and on every push (`.github/workflows/build.yml`),
after the unit tests pass. Images are signed keyless through GitHub. To run the tests locally:
`python3 -m unittest discover -s tests`.

## Roadmap

See the Version 1 plan doc. Next phases: Quick Access tiles and per-game profiles (Game Mode),
built-in emulation setup, XREAL auto profiles and auto 3D, then the installer and ROG Ally move.
