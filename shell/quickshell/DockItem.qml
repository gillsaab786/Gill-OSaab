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
    property string builtinIcon: "" // Gill(OS)'s own items (Launchpad, Trash) draw their own icon
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

    // macOS magnification: icons swell smoothly as the pointer passes over them, neighbours a bit
    // less. Distances are measured on the Dock at rest (pointerX comes in rest coordinates), so
    // growing icons don't push the zoom around and it stays steady under the pointer.
    property real restCentre: 0
    readonly property real centreNow: x + width / 2
    onCentreNowChanged: if (pointerX < -999) restCentre = centreNow
    Component.onCompleted: restCentre = centreNow
    readonly property real reach: Theme.dockIcon * 2.4
    readonly property real distance: Math.abs(pointerX - restCentre)
    readonly property real zoom: distance > reach ? 0 : Math.pow((Math.cos(distance / reach * Math.PI) + 1) / 2, 1.3)
    width: Theme.dockIcon + (Theme.dockMagnified - Theme.dockIcon) * zoom
    height: width
    Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

    property real bounce: 0
    SequentialAnimation {
        id: bounceAnim
        loops: 2
        NumberAnimation { target: item; property: "bounce"; to: 22; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "bounce"; to: 0; duration: 260; easing.type: Easing.OutBounce }
    }

    IconTile {
        id: img
        visible: item.builtinIcon === ""
        anchors.fill: parent
        anchors.bottomMargin: item.bounce
        source: visible ? Theme.icon(item.entry ? item.entry.icon : "", item.appId, (item.appId || "").toLowerCase(), "applications-games", "application-x-executable", "system-run") : ""
        label: item.entry ? Theme.displayName(item.entry) : (item.appId || "")
        scale: press.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
    }
    TrashIcon { // Trash: frosted glass bin, papers inside when full
        visible: item.builtinIcon === "trash"
        anchors.fill: parent
        anchors.bottomMargin: item.bounce
        full: item.trashFull
        lift: item.drop
        scale: (press.pressed ? 0.88 : 1) * (dropZone.containsDrag ? 1.12 : 1)
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.002 } }
    }
    Rectangle { // Launchpad / Downloads: a glossy glass squircle with a drawn symbol
        visible: item.builtinIcon !== "" && item.builtinIcon !== "trash"
        anchors.fill: parent
        anchors.margins: parent.width * 0.05
        anchors.bottomMargin: item.bounce + parent.width * 0.05
        radius: width * 0.26
        scale: press.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
        gradient: Gradient {
            GradientStop { position: 0; color: item.builtinIcon === "downloads" ? "#64d2ff" : "#7d7aff" }
            GradientStop { position: 1; color: item.builtinIcon === "downloads" ? "#0a84ff" : "#0a60ff" }
        }
        GlassRim { radius: parent.radius; strength: 1.2 }
        Icon { anchors.centerIn: parent; width: parent.width * 0.56; height: width; name: item.builtinIcon; color: "white" }
    }

    // Trash takes files dragged from Files and other apps
    property bool trashFull: false
    property real drop: 0
    signal filesDropped(var urls)
    signal menuRequested()
    SequentialAnimation {
        id: dropAnim
        NumberAnimation { target: item; property: "drop"; to: 8; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "drop"; to: 0; duration: 380; easing.type: Easing.OutBounce }
    }
    DropArea {
        id: dropZone
        anchors.fill: parent
        enabled: item.builtinIcon === "trash"
        keys: ["text/uri-list"]
        onDropped: d => {
            if (!d.hasUrls) return
            item.filesDropped(d.urls)
            dropAnim.restart()
            ShellState.haptic("success")
            d.accept(Qt.MoveAction)
        }
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
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressAndHold: item.menuRequested()
        onClicked: m => {
            if (m.button === Qt.RightButton) {
                item.menuRequested()
                return
            }
            if (item.builtinIcon !== "") {
                item.activated()
                return
            }
            if (m.button === Qt.MiddleButton || !item.isRunning) {
                const win = item.QsWindow.window
                if (win && win.screen)
                    ShellState.launchFrom(item, win.screen.x + (win.screen.width - win.width) / 2,
                                          win.screen.y + win.screen.height - win.height, Theme.dockIcon)
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
