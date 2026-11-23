# Gill-OSaab

Gill-OSaab is your own OS for handhelds and PCs. Developer: GILL-Saab.
It's built on [Bazzite](https://bazzite.gg) (Fedora Atomic), so you get SteamOS-style Game Mode,
handheld support (ROG Ally, GPD Win Max 2, Steam Deck) and rollback-safe updates, plus the
Gill-OSaab features below.

| Edition | Image | For |
| --- | --- | --- |
| **Core (new)** | `ghcr.io/gillsaab786/gill-osaab-core` | Our own desktop on minimal Fedora bootc, no Bazzite and no KDE: the Gill-OSaab window manager and shell (macOS-style), Game Mode (Steam + gamescope), Windows/Android/Linux apps, drivers |
| Handheld | `ghcr.io/gillsaab786/gill-osaab` | ROG Ally, GPD Win Max 2, Steam Deck. Boots into Game Mode |
| Desktop | `ghcr.io/gillsaab786/gill-osaab-desktop` | Intel/AMD desktops and laptops. Boots to the desktop |
| Desktop Nvidia | `ghcr.io/gillsaab786/gill-osaab-desktop-nvidia` | PCs with Nvidia GTX 16 / RTX 20 or newer (Settings offers the switch) |

## The Gill-OSaab desktop (Core edition)

Our own window manager (`gosaab-wm`) and shell, written for Gill-OSaab (`shell/`):
- **Windows**: macOS-style title bars with red/yellow/green buttons, rounded corners, soft
  shadows, frosted glass; windows spring open and fade closed; minimise flies into the Dock.
- **Menu bar** with the Gill-OSaab menu (Settings, Updates, Game Mode, Sleep/Restart/Shut Down,
  Lock), app name, battery and clock. **Dock** with magnification, running dots, Launchpad, Trash.
- **Control Centre**: Wi-Fi, Bluetooth, Focus, Dark Mode, Game Mode, VPN, Screen Off, Glasses,
  brightness and volume. **Notifications** with download/update progress bars.
- **Spotlight** (Super+Space, also does sums), **Launchpad** (Super+G), **Mission Control**
  (Super+Up), **lock screen** (Super+L) and a matching **login screen** with Desktop / Game Mode.
- Windows (X11) apps and games get the same look; games get pointer lock and raw mouse input.
- Every change is tested by CI: the desktop runs headless, a robot clicks the buttons and
  screenshots are checked (`shell/tests/run-headless.sh`, screenshots on the `ci-shots` branch).

Try it: on any Fedora Atomic / bootc install run
`sudo bootc switch ghcr.io/gillsaab786/gill-osaab-core:latest`, reboot, pick **Gill-OSaab** at
the login screen.

## What's in 1.2.0

**One-click apps** (`gosaab-open`, the default for these files):

| File | Runs through |
| --- | --- |
| `.exe` `.msi` | Wine, each app in its own sandbox (bubblewrap): it sees only its own folder, never your files |
| `.apk` | Waydroid (Android) |
| `.AppImage` | Copied to `~/Applications`, added to the app menu |
| `.deb` / `.rpm` | Ubuntu / Fedora container (distrobox), added to the app menu |
| `.flatpakref` `.flatpak` | Flatpak |

**Updates, drivers and BIOS** (Settings › Updates and Settings › Device & Drivers):
- **Update everything**, plus an Update button and version for each part: Gill-OSaab system
  (kernel, graphics and Wi-Fi drivers, Wine, Android support), Android system image, Proton-GE
  (latest release, checksum-verified), Windows app setups, apps and emulators, Linux containers,
  Game Mode plugins. Progress shows in notifications, including in Game Mode.
- **This device**: model, BIOS version, processor, graphics and Wi-Fi/Ethernet chips with the driver
  each one uses.
- **Update all drivers** (system bundle + device firmware), **Device firmware** (LVFS) and **BIOS**
  (when the maker publishes it to LVFS; otherwise it opens the maker's support page). The BIOS is
  never updated automatically.
- Nvidia graphics found → one tap switches to the Nvidia edition.
- Everything follows the latest Bazzite stable; the images rebuild daily.

**Gill-OSaab Settings** (app menu): sharp iOS-style icons, search, and switches for
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
macOS/iOS-style motion (windows zoom open and closed, minimise into the dock like a genie,
dialogs slide down as sheets, Mission Control-style overview, snappier animation timing,
system sounds including the Trash), a macOS-style top bar (menu, app menu, tray, clock) and a floating, centred dock that moves out of
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
| `gosaab-update-component PART` | Update one part: `all`, `os`, `drivers`, `firmware`, `bios`, `android`, `proton`, `wine`, `apps`, `containers`, `decky`, `nvidia` |
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
after the unit tests pass. Images are unsigned for now (see the note in the workflow to turn signing on). To run the tests locally:
`python3 -m unittest discover -s tests`.

## Roadmap

See the Version 1 plan doc. Next phases: Quick Access tiles and per-game profiles (Game Mode),
built-in emulation setup, XREAL auto profiles and auto 3D, then the installer and ROG Ally move.
