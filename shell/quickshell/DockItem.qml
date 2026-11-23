import QtQuick
import Quickshell
import Quickshell.Widgets

// One app in the Dock.
Item {
    id: item
    property var entry: null       // DesktopEntry (may be null for unknown apps)
    property string appId: ""
    property var windows: []
    property real pointerX: -1000
    readonly property bool isRunning: windows.length > 0
    readonly property bool isActive: windows.some(w => w.activated)
    property string label: entry ? Theme.displayName(entry) : appId
    property string builtinIcon: "" // Gill-OSaab's own items (Launchpad, Trash) draw their own icon
    signal activated()
    property var dockWindow: null

    // Tell the window manager where this icon is, so minimised windows fly into it
    function publishRect() {
        if (!dockWindow || windows.length === 0) return
        const p = item.mapToItem(null, 0, 0)
        for (const w of windows) w.setRectangle(dockWindow, Qt.rect(Math.round(p.x), Math.round(p.y), Math.round(width), Math.round(height)))
    }
    Timer { id: rectTimer; interval: 250; onTriggered: item.publishRect() }
    onWindowsChanged: rectTimer.restart()
    onXChanged: rectTimer.restart()

    // macOS magnification: icons swell smoothly as the pointer passes over them
    readonly property real centre: x + width / 2
    readonly property real distance: Math.abs(pointerX - centre)
    readonly property real zoom: distance > 140 ? 0 : (Math.cos(distance / 140 * Math.PI) + 1) / 2
    width: Theme.dockIcon + (Theme.dockMagnified - Theme.dockIcon) * zoom
    height: width
    Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    property real bounce: 0
    SequentialAnimation {
        id: bounceAnim
        loops: 2
        NumberAnimation { target: item; property: "bounce"; to: 22; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "bounce"; to: 0; duration: 260; easing.type: Easing.OutBounce }
    }

    IconImage {
        id: img
        visible: item.builtinIcon === ""
        anchors.fill: parent
        anchors.bottomMargin: item.bounce
        source: visible ? Theme.icon(item.entry ? item.entry.icon : "", item.appId, (item.appId || "").toLowerCase(), "application-x-executable") : ""
        asynchronous: true
        scale: press.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
    }
    Rectangle { // built-in item: a glossy rounded tile with a drawn symbol
        visible: item.builtinIcon !== ""
        anchors.fill: parent
        anchors.margins: parent.width * 0.06
        anchors.bottomMargin: item.bounce + parent.width * 0.06
        radius: width * 0.23
        scale: press.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
        gradient: Gradient {
            GradientStop { position: 0; color: item.builtinIcon === "trash" ? "#8e8e93" : "#5e5ce6" }
            GradientStop { position: 1; color: item.builtinIcon === "trash" ? "#48484a" : "#0a84ff" }
        }
        Icon { anchors.centerIn: parent; width: parent.width * 0.58; height: width; name: item.builtinIcon; color: "white" }
    }

    // running indicator
    Rectangle {
        width: 4; height: 4; radius: 2
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 1 }
        color: Theme.text
        opacity: item.isRunning ? (item.isActive ? 0.95 : 0.55) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }

    // name label above the icon
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
        width: tip.implicitWidth + 20; height: 26; radius: 7
        color: Theme.panel
        border { color: Theme.panelBorder; width: 1 }
        opacity: press.containsMouse ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Text { id: tip; anchors.centerIn: parent; text: item.label; color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
    }

    MouseArea {
        id: press
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: m => {
            if (item.builtinIcon !== "") {
                item.activated()
                return
            }
            if (m.button === Qt.MiddleButton || !item.isRunning) {
                if (item.entry) item.entry.execute()
                bounceAnim.restart()
                return
            }
            // Click the active app to hide it; click again (or any other app) to bring it back
            const w = item.windows
            if (item.isActive && w.length === 1) {
                w[0].minimized = true
            } else {
                for (const win of w) win.activate()
            }
        }
    }
}
