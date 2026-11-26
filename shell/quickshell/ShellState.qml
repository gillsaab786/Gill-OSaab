pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which panels are open, shared by the bar, dock and keyboard shortcuts.
Singleton {
    id: root
    property bool controlCenter: false
    property bool notificationCenter: false
    property bool spotlight: false
    property bool systemMenu: false
    property bool launchpad: false
    property bool doNotDisturb: false
    property bool glassesConnected: false
    property bool stereo: false          // glasses showing side-by-side 3D: overlays draw once per eye
    property var glasses3dApps: []       // apps set to 3D in Settings > Glasses (Launchpad's 3D shelf)
    property real intro: 1 // 0 -> 1 as the desktop arrives (Dock rises, widgets fade in); see ModeTransition.qml
    property string dockPopup: "" // "downloads" (the stack fan) or "trash" (its menu)
    // App menu (right-click / hold on an app in the Dock or Launchpad) and App Info
    property var menuApp: null      // DesktopEntry
    property point menuAt: Qt.point(0, 0)
    property string menuFrom: ""    // "dock" | "launchpad"
    property var menuScreen: null
    property var infoApp: null      // DesktopEntry shown in App Info
    function openAppMenu(entry, item, from) {
        if (!entry) return
        const win = item.QsWindow.window
        const p = item.mapToItem(null, item.width / 2, 0)
        const sc = win ? win.screen : null
        // layer windows not anchored left (the Dock) are centred on the screen
        const offX = win && sc && from === "dock" ? (sc.width - win.width) / 2 : 0
        const offY = win && sc && from === "dock" ? sc.height - win.height : 0
        menuScreen = sc
        menuAt = Qt.point(offX + p.x, offY + p.y)
        menuFrom = from
        menuApp = entry
        haptic("tick")
    }
    readonly property bool anyPopup: controlCenter || notificationCenter || systemMenu || dockPopup !== ""

    // Haptic feedback from the built-in controller (gosaab-haptic): tick, toggle, success, error
    Socket {
        id: hapticSocket
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/gosaab-haptic.sock"
        connected: true
    }
    function haptic(kind) {
        if (!hapticSocket.connected) { hapticSocket.connected = true; return }
        hapticSocket.write(kind + "\n")
        hapticSocket.flush()
    }

    function closeAll() {
        controlCenter = false
        notificationCenter = false
        systemMenu = false
        dockPopup = ""
        menuApp = null
        spotlight = false
        launchpad = false
    }
    function toggle(name) {
        const was = root[name]
        closeAll()
        root[name] = !was
    }
    // Tell the compositor where an app is being opened from (icon centre, layout coordinates)
    // so its window zooms out of that icon, iOS-style. Read once, within a few seconds.
    function launchFrom(item, ox, oy, size) {
        if (!item) return
        const p = item.mapToItem(null, item.width / 2, item.height / 2)
        const x = Math.round(ox + p.x - size / 2), y = Math.round(oy + p.y - size / 2)
        run("printf '%d %d %d %d' " + x + " " + y + " " + size + " " + size + " > \"$XDG_RUNTIME_DIR/gosaab-launch-origin\"")
    }
    // on-screen keyboard (wvkbd) for typing with the touch screen in any app. It may already be
    // running hidden (the window manager shows it when a text box is tapped): SIGRTMIN toggles it.
    function toggleKeyboard() {
        run("pkill --signal RTMIN -x wvkbd-mobintl || wvkbd-mobintl -L 300 -H 260 -R 12 --bg 1c1c1ed9 --fg 48484af2 --fg-sp 2c2c2ef2 "
            + "--press 0a84ffff --press-sp 0a84ffff --text ffffffff --text-sp ffffffff --fn 'Inter 18' &")
    }
    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd])
    }
}
