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

## Milestones
- [x] **M1 Window manager core**: windows, popups, layer-shell (bar/dock/wallpaper), centred
      placement, maximise/fullscreen, Alt/Super+Tab, Super+Q/Return/F, spring open + fade/shrink
      close animations, rounded corners, shadows, blur, screencopy/xdg-output, clean shutdown.
      CI: 11/11 checks.
- [ ] **M2 macOS window chrome**: server-side title bars drawn by gosaab-wm (traffic-light
      close/minimise/zoom buttons, centred title in Inter, rounded on all corners, inactive
      dimming), force SSD for apps that accept it; title bar scales with open/close animations.
- [ ] **M3 Shell UI (Quickshell/QML)**: top bar (logo menu, app name, tray, clock, Control Center
      button), floating dock with magnification + running indicators (needs
      wlr-foreign-toplevel-management in gosaab-wm), wallpaper, notification server + center,
      Control Center (Wi-Fi, Bluetooth, volume, brightness, dark mode, night light).
- [ ] **M4 Motion and spaces**: minimise to dock (genie), Mission Control overview, Launchpad,
      Spotlight search, workspaces with swipe, iOS-style spring physics everywhere.
- [ ] **M5 System integration**: lock screen + greeter (greetd), XWayland, Game Mode session
      switch (gamescope + Steam), Gill-OSaab Settings restyled to match, notifications hub
      reuse, multi-monitor, HiDPI/fractional scaling, touch + controller navigation.
- [ ] **M6 Ship**: replace KDE in the Core image, installer ISO, first-boot setup, test on GPD
      Win Max 2 and ROG Ally, performance pass (idle RAM/CPU, frame pacing).
