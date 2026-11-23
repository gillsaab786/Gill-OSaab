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
    property bool doNotDisturb: false
    readonly property bool anyPopup: controlCenter || notificationCenter || systemMenu

    function closeAll() {
        controlCenter = false
        notificationCenter = false
        systemMenu = false
        spotlight = false
    }
    function toggle(name) {
        const was = root[name]
        closeAll()
        root[name] = !was
    }
    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd])
    }
}
