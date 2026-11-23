import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Per-app glasses modes: when an app with a profile comes to the front, switch the glasses
// (e.g. 3D for the 3DS emulator, back to 2D for the browser). ~/.config/gill-osaab/glasses.conf
Scope {
    id: root
    property var profiles: ({})
    property string applied: ""
    readonly property string appId: ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.appId : ""

    FileView {
        path: Quickshell.env("HOME") + "/.config/gill-osaab/glasses.conf"
        watchChanges: true
        printErrors: false // no file yet = no profiles
        onFileChanged: reload()
        onLoaded: {
            const p = {}
            for (const line of text().split("\n")) {
                const m = line.trim().match(/^([^#=\s]+)\s*=\s*(3d|2d|only|extend)$/)
                if (m) p[m[1].toLowerCase()] = m[2]
            }
            root.profiles = p
        }
    }

    onAppIdChanged: {
        const mode = root.profiles[(appId || "").toLowerCase()] || root.profiles["default"] || ""
        if (mode && mode !== root.applied) {
            root.applied = mode
            Quickshell.execDetached(["gosaab-glasses", mode])
        }
    }
}
