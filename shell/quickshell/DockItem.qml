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
    readonly property string label: entry ? entry.name : appId

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
        anchors.fill: parent
        anchors.bottomMargin: item.bounce
        source: Theme.icon(item.entry ? item.entry.icon : "", item.appId, (item.appId || "").toLowerCase(), "application-x-executable")
        asynchronous: true
        scale: press.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
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
