pragma Singleton
import QtQuick
import Quickshell

// Which panels are open, shared by the bar, dock and keyboard shortcuts.
Singleton {
    id: root
    property bool controlCenter: false
    property bool notificationCenter: false
    property bool spotlight: false
    property bool systemMenu: false
    property bool launchpad: false
    property bool doNotDisturb: false
    readonly property bool anyPopup: controlCenter || notificationCenter || systemMenu

    function closeAll() {
        controlCenter = false
        notificationCenter = false
        systemMenu = false
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
    // on-screen keyboard (wvkbd) for typing with the touch screen in any app
    function toggleKeyboard() {
        run("pkill -x wvkbd-mobintl || wvkbd-mobintl -L 300 -H 260 -R 12 --bg 1c1c1ed9 --fg 48484af2 --fg-sp 2c2c2ef2 "
            + "--press 0a84ffff --press-sp 0a84ffff --text ffffffff --text-sp ffffffff --fn 'Inter 18' &")
    }
    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd])
    }
}
