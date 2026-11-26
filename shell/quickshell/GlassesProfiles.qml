import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// XREAL (and other) glasses: per-app modes, refresh rate and emulator 3D.
// ~/.config/gill-osaab/glasses.conf:
//   <app-id>=3d|2d|only|extend   mode while that app is in front
//   hz.<app-id>=60|72|90|120     refresh rate while that app is in front (hz.default for the rest)
//   hz.<app-id>=30               play at 30 FPS: the app draws 30 frames a second (gosaab-wm caps it) and
//                                the glasses run at 60 Hz, so each frame shows exactly twice (smooth)
//   depth.<3ds|dolphin|rpcs3|vb>=0..100   3D depth per emulator (gosaab-3d)
//   auto3d=off                   don't set emulators up for 3D when the glasses are plugged in
Scope {
    id: root
    property var profiles: ({})
    property var rates: ({})
    property bool auto3d: true
    property string applied: ""
    property string appliedHz: ""
    readonly property string appId: ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.appId : ""

    // glasses plugged in? (their screen reports the maker's model name)
    readonly property bool connected: Quickshell.screens.some(s => /XREAL|Nreal|NREAL|VITURE|Rokid|MRG|\bAir\b/i.test((s.model || "") + " " + (s.name || "")))
    // side-by-side 3D: a screen twice as wide as normal (3840x1080)
    readonly property bool stereo: Quickshell.screens.some(s => s.height > 0 && s.width / s.height > 3.3)
    onConnectedChanged: {
        ShellState.glassesConnected = connected
        if (auto3d) Quickshell.execDetached(["gosaab-3d", connected ? "on" : "off"])
    }
    onStereoChanged: ShellState.stereo = stereo
    Component.onCompleted: { ShellState.glassesConnected = connected; ShellState.stereo = stereo }

    FileView {
        path: Quickshell.env("HOME") + "/.config/gill-osaab/glasses.conf"
        watchChanges: true
        printErrors: false // no file yet = no profiles
        onFileChanged: reload()
        onLoaded: {
            const p = {}, r = {}
            let auto = true
            for (const line of text().split("\n")) {
                const t = line.trim()
                let m = t.match(/^([^#=\s.]+(?:\.[^#=\s]+)*)\s*=\s*(3d|2d|only|extend)$/)
                if (m && !t.startsWith("hz.") && !t.startsWith("depth.")) { p[m[1].toLowerCase()] = m[2]; continue }
                m = t.match(/^hz\.([^=\s]+)\s*=\s*(30|60|72|90|120)$/)
                if (m) { r[m[1].toLowerCase()] = m[2]; continue }
                if (/^auto3d\s*=\s*off$/.test(t)) auto = false
            }
            root.profiles = p
            root.rates = r
            // 30 FPS apps: tell the compositor (one "app-id fps" line each)
            capFile.setText(Object.keys(r).filter(k => r[k] === "30" && k !== "default").map(k => k + " 30\n").join(""))
            root.auto3d = auto
            ShellState.glasses3dApps = Object.keys(p).filter(k => p[k] === "3d")
        }
    }

    FileView {
        id: capFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/gosaab-fps-cap"
        printErrors: false
    }

    onAppIdChanged: {
        const id = (appId || "").toLowerCase()
        const mode = root.profiles[id] || root.profiles["default"] || ""
        if (mode && mode !== root.applied) {
            root.applied = mode
            Quickshell.execDetached(["gosaab-glasses", mode])
        }
        // refresh rate matched to what's in front (e.g. 60 Hz for emulators, 120 for the desktop)
        const want = root.rates[id] || root.rates["default"] || ""
        const hz = want === "30" ? "60" : want // 30 FPS plays on 60 Hz (each frame twice)
        if (root.connected && hz && hz !== root.appliedHz) {
            root.appliedHz = hz
            Quickshell.execDetached(["gosaab-glasses", "hz", hz])
        }
    }
}
