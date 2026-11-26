import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification server + banners (top right). Banners with a progress value stay until done.
Scope {
    id: root
    property var banners: []
    readonly property var all: server.trackedNotifications.values

    function progressOf(n) {
        if (!n || !n.hints) return -1
        const v = n.hints["value"]
        return (v === undefined || v === null) ? -1 : Math.max(0, Math.min(100, Number(v)))
    }
    function dropBanner(n) {
        banners = banners.filter(b => b !== n)
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        extraHints: ["value"]
        onNotification: n => {
            n.tracked = true
            if (!ShellState.doNotDisturb && root.banners.indexOf(n) < 0)
                root.banners = [n].concat(root.banners).slice(0, 4)
            n.closed.connect(() => root.dropBanner(n))
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { ShellState.toggle("notificationCenter") }
        function clear(): void { for (const n of root.all.slice()) n.dismiss() }
        function count(): int { return root.all.length }
    }

    PanelWindow {
        id: bannerWindow
        anchors { top: true; right: true }
        margins { top: 8; right: 8 }
        // 3D glasses (side by side): banners show once for each eye
        readonly property real eyeShift: ShellState.stereo && screen ? screen.width / 2 : 0
        implicitWidth: 372 + eyeShift
        mask: Region { item: column }
        implicitHeight: Math.max(1, column.height + 4)
        // banners step aside (fade) when Control Centre or Notification Centre opens
        readonly property bool show: root.banners.length > 0 && !ShellState.notificationCenter && !ShellState.controlCenter
        visible: show || column.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "gosaab-notifications:r24"
        WlrLayershell.layer: WlrLayer.Overlay

        ShaderEffectSource { // the second eye's copy
            visible: bannerWindow.eyeShift > 0
            sourceItem: bannerWindow.eyeShift > 0 ? column : null
            x: column.x + bannerWindow.eyeShift
            width: column.width; height: column.height
            opacity: column.opacity
            live: true
        }
        Column {
            id: column
            width: 372
            opacity: bannerWindow.show ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
            spacing: 8
            Repeater {
                model: root.banners
                NotificationCard {
                    required property var modelData
                    notification: modelData
                    progress: root.progressOf(modelData)
                    width: column.width
                    banner: true
                    onTimedOut: root.dropBanner(modelData)
                }
            }
        }
    }

    // Notification Centre: everything that arrived, newest first
    Popup {
        open: ShellState.notificationCenter
        panelWidth: 380
        Row {
            width: parent.width
            Text { width: parent.width - clearBtn.width; text: "Notifications"; color: Theme.text
                font { family: Theme.font; pixelSize: 15; weight: Font.Bold } }
            Text { id: clearBtn; text: root.all.length ? "Clear" : ""; color: Theme.accent
                font { family: Theme.font; pixelSize: 13 }
                MouseArea { anchors.fill: parent; onClicked: { for (const n of root.all.slice()) n.dismiss() } } }
        }
        Text {
            visible: root.all.length === 0
            width: parent.width; height: 60
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: ShellState.doNotDisturb ? "Do Not Disturb is on" : "No new notifications"
            color: Theme.subtext; font { family: Theme.font; pixelSize: 13 }
        }
        Repeater {
            model: root.all.slice().reverse().slice(0, 8)
            NotificationCard {
                required property var modelData
                notification: modelData
                progress: root.progressOf(modelData)
                width: parent ? parent.width : 340
            }
        }
    }
}
