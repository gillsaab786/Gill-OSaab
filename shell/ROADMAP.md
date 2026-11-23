# Gill-OSaab Shell: roadmap and status

Gill-OSaab's own desktop: our own window manager (`gosaab-wm`, C on wlroots 0.20 + scenefx 0.5)
and our own shell UI (bar, dock, Launchpad, Control Center, notifications, lock screen) in
Qt Quick via Quickshell. Runs on the Gill-OSaab Core image (minimal Fedora bootc).

## How work is tested
- `.github/workflows/shell.yml` builds in Fedora 45, runs unit tests, then runs the real
  compositor headless on a software GPU (vkms card + llvmpipe, `WLR_RENDERER_ALLOW_SOFTWARE`),
  opens real apps (foot), takes screenshots with grim and checks them (`shell/tests/run-headless.sh`).
- Slow-motion mode (`GOSAAB_ANIM_SLOWDOWN=10`) captures frames mid-animation.
- Screenshots + logs are force-pushed to the `ci-shots` branch:
  `git fetch --depth 1 origin ci-shots && git --work-tree=/tmp/shots checkout FETCH_HEAD -- .`
- Lessons: link scenefx BEFORE wlroots (both export wlr_scene_*); xdg decoration mode may only be
  set after the toplevel's initial commit; GitHub artifact downloads are blocked from the agent
  workspace, so use the ci-shots branch.

## Next up (asked by Jas, do these first)
Done 2026-11-24: 1 touch, 2 tap/natural scroll (+Settings), 3 pinch/hold to apps, 4 snapping,
5 desktop progress notifications, 7 DXVK + 32/64-bit test, 8 Android setup (multi-window, libndk),
9 sandbox + App Folders, 10 ~/Android + Android download folder. 6 Android notifications (adb bridge), VPN switch + import (Settings, Control Centre), cloud drives
(rclone, several accounts, off by default). Open: XREAL modes, lens effect, controller nav, multi-monitor.
1. Touchscreen in the desktop (wlr touch events -> clients; tap, drag, scroll) - Ally/GPD screens.
2. libinput setup: tap-to-click, natural scrolling, disable-while-typing (+ Settings switches).
3. Pinch-zoom and 2-finger swipe back/forward in browsers: wlr pointer-gestures protocol
   (forward pinch/hold; only 3+ finger swipes are kept for spaces).
4. Window snapping / split screen: drag to an edge or Super+Left/Right = half screen, corners =
   quarters, macOS-style tile menu on the green button.
5. Download/progress notifications in the desktop: run gosaab-notify-hub's JobView + Unity
   LauncherEntry bridges in the Core desktop too (Chromium, file copies, Steam, Flatpak).
6. Android (Waydroid) notifications, incl. download progress, mirrored to the shell.
7. Windows apps: DXVK + VKD3D-Proton in the .exe sandboxes (gosaab-open) for full-speed DirectX;
   check 32-bit (new WoW64) apps and installers in CI with a test .exe.
8. Android apps: Waydroid multi-window mode on by default (each app its own resizable window,
   full screen on maximise), ARM translation (libndk on AMD/Intel) for ARM-only apps, GPU accel.
9. Every app sandboxed, up to 2 folders each: Settings > Privacy > App folders. Linux apps as
   Flatpaks (Firefox, VLC, Files-picked via portal) with `flatpak override --nofilesystem=home
   --filesystem=<folder>`; Windows apps: bwrap binds in gosaab-open; Android: Waydroid shared
   folder. Default: each app gets only its own folder; picking a file in a dialog still works.
   Steam stays outside the sandbox (games need full speed / controllers).
10. Android files in Files: an "Android" place in the file manager (Download, Pictures, Movies,
   Music, Documents + Android/data/<app>), readable without root (bind mounts with the right
   owner). Settings > Android > Folders: point each Android folder (e.g. Download) at any Linux
   folder you choose (bind mount into ~/.local/share/waydroid/data/media/0).

## Milestones
- [x] **M1 Window manager core**: windows, popups, layer-shell (bar/dock/wallpaper), centred
      placement, maximise/fullscreen, Alt/Super+Tab, Super+Q/Return/F, spring open + fade/shrink
      close animations, rounded corners, shadows, blur, screencopy/xdg-output, clean shutdown.
      CI: 11/11 checks.
- [x] **M2 macOS window chrome**: server-side title bars drawn by gosaab-wm (traffic-light
      close/minimise/zoom buttons, centred title in Inter, rounded corners, inactive dimming),
      SSD for apps that accept it, title bar scales with open/close animations, double-click
      title to zoom, drag to move, resize grips around the frame. CI clicks every button.
- [x] **M3 Shell UI (Quickshell/QML, `shell/quickshell`)**: menu bar (logo menu, app name,
      battery, clock), Dock (magnification, running dots, launch bounce, Launchpad + Trash, click
      to show/hide via wlr-foreign-toplevel-management), frosted glass behind shell panels
      (namespace `gosaab-*`), notification banners + Notification Centre with progress bars,
      Control Centre (Wi-Fi, Bluetooth, Focus, Dark Mode, Game Mode, VPN, Screen Off, Glasses,
      brightness + volume), Spotlight (apps + maths).
- [~] **M4 Motion and spaces**: done: Launchpad, Mission Control (Super+Up / F3), minimise flies
      into the app's Dock icon and back. Spaces: 4 workspaces that slide (Super+1..4, Ctrl+Super+Left/Right,
      Super+Shift+1..4 moves a window, 3-finger swipe; swipe up = Mission Control).
- [~] **M5 System integration**: done: lock screen (ext-session-lock + PAM, Super+L), login
      screen (SDDM theme, Desktop/Game Mode choice), X11 apps via xwayland-satellite (with title
      bars), pointer lock + raw mouse for games, xdg-activation, Game Mode switch
      (`gosaab-game-mode`, SteamOS-compatible `steamos-session-select`). Next: idle lock/dim,
      multi-monitor arrangement, HiDPI scaling UI, controller navigation in the shell.
- Shortcuts: Super+Space Spotlight, Super+G Launchpad, Super+Up Mission Control, Super+1..4 spaces, Super+A Control
  Centre, Super+N notifications, Super+L lock, Super+Q close, Super+M minimise, Super+F zoom,
  Super+Return terminal, Alt/Super+Tab switch.
- [~] **M6 Ship**: done: Core image uses gosaab-wm + shell instead of KDE (`shell/install.sh`,
      `files/core-system`); CI boots the real image (core-smoke.yml); bootable USB image on the
      `core-usb` release (iso.yml; Anaconda ISO blocked: bootc-image-builder lacks Fedora 45
      installer defs). Idle dim/lock via swayidle + idle-inhibit. Liquid Glass panels (GlassRim). Settings > Game
      Mode: start in Game Mode/Desktop/Ask, TDP via Handheld Daemon, frame generation (lsfg-vk),
      Decky install. Next: Liquid Glass lens/refraction shader in gosaab-wm, workspaces,
      controller navigation, multi-monitor; installer ISO, first-boot setup, test on GPD
      Win Max 2 and ROG Ally, performance pass (idle RAM/CPU, frame pacing).
