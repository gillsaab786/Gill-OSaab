import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// App Info, like Android: what the app is (Android, Windows or Linux), its version, and buttons to
// Force close, Clear cache, Clear data, Uninstall and Hide. The work is done by gosaab-appinfo.
PanelWindow {
    id: info
    screen: ShellState.menuScreen || Quickshell.screens[0]
    visible: ShellState.infoApp !== null || card.opacity > 0.01
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gosaab-appinfo"
    WlrLayershell.keyboardFocus: ShellState.infoApp ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var app: null
    property var appData: ({})
    property bool busy: false
    property string message: ""
    property string confirm: "" // action waiting for a second tap
    readonly property string helper: (Quickshell.env("GOSAAB_LIBEXEC") || "/usr/libexec/gill-osaab") + "/gosaab-appinfo"

    Connections {
        target: ShellState
        function onInfoAppChanged() {
            if (!ShellState.infoApp) return
            info.app = ShellState.infoApp
            info.appData = ({})
            info.message = ""
            info.confirm = ""
            info.refresh()
        }
    }
    function refresh() {
        query.command = [helper, "info", app.id]
        query.running = true
    }
    function act(action, label) {
        if (["clear-data", "uninstall"].indexOf(action) >= 0 && confirm !== action) {
            confirm = action
            confirmTimer.restart()
            ShellState.haptic("tick")
            return
        }
        confirm = ""
        busy = true
        message = label + "…"
        doer.command = [helper, action, app.id]
        doer.running = true
    }
    Timer { id: confirmTimer; interval: 3500; onTriggered: info.confirm = "" }
    Process {
        id: query
        stdout: StdioCollector { onStreamFinished: { try { info.appData = JSON.parse(text) } catch (e) { info.appData = { ok: false } } } }
    }
    Process {
        id: doer
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}
                try { r = JSON.parse(text) } catch (e) {}
                info.busy = false
                info.message = r.ok ? (r.message || "Done") : (r.message || "That didn't work")
                ShellState.haptic(r.ok ? "success" : "error")
                if (doer.command[1] === "uninstall" && r.ok) ShellState.infoApp = null
                else info.refresh()
            }
        }
    }
    function size(b) {
        if (b === undefined) return "…"
        if (b < 1024) return b + " B"
        const u = ["KB", "MB", "GB", "TB"]
        let i = -1
        do { b /= 1024; i++ } while (b >= 1024 && i < u.length - 1)
        return (b < 10 ? b.toFixed(1) : Math.round(b)) + " " + u[i]
    }
    readonly property color kindColour: appData.kind === "Android" ? Theme.green : appData.kind === "Windows" ? Theme.accent : "#ff9f0a"

    MouseArea { anchors.fill: parent; onClicked: ShellState.infoApp = null }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35); opacity: card.opacity }
    Item { focus: true; Keys.onEscapePressed: ShellState.infoApp = null }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 480
        height: body.implicitHeight + 48
        radius: 30
        color: Theme.panel
        GlassRim { radius: 30 }
        opacity: ShellState.infoApp ? 1 : 0
        scale: ShellState.infoApp ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.4; epsilon: 0.002 } }
        MouseArea { anchors.fill: parent }

        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 16

            Row {
                spacing: 16
                IconTile { width: 72; height: 72; source: info.app ? Theme.icon(info.app.icon, "application-x-executable") : ""; label: info.app ? Theme.displayName(info.app) : "" }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text { text: info.app ? Theme.displayName(info.app) : ""; color: Theme.text
                        font { family: Theme.font; pixelSize: 22; weight: Font.DemiBold } }
                    Row {
                        spacing: 8
                        Rectangle { // Android / Windows / Linux badge
                            visible: !!info.appData.kind
                            width: kindText.implicitWidth + 16; height: 22; radius: 11; color: info.kindColour
                            Text { id: kindText; anchors.centerIn: parent; text: (info.appData.kind || "") + " app"; color: "white"
                                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: info.appData.sourceLabel || "Checking…"
                            color: Theme.subtext; font { family: Theme.font; pixelSize: 12 } }
                    }
                }
            }

            Rectangle { // details
                width: parent.width; height: details.implicitHeight + 16; radius: 16
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                Column {
                    id: details
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    Repeater {
                        model: [["Version", info.appData.version || (info.appData.ok === undefined ? "…" : "Not shown by this app")],
                                ["App ID", info.appData.package || (info.app ? info.app.id : "")],
                                ["Status", info.appData.running ? "Running" : "Not running"],
                                ["Cache", info.size(info.appData.cacheBytes)],
                                ["App data", info.size(info.appData.dataBytes)]]
                        Item {
                            required property var modelData
                            width: details.width; height: 32
                            Text { anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                text: modelData[0]; color: Theme.subtext; font { family: Theme.font; pixelSize: 13 } }
                            Text { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                width: Math.min(implicitWidth, parent.width * 0.62); elide: Text.ElideMiddle; horizontalAlignment: Text.AlignRight
                                text: modelData[1]; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.Medium } }
                        }
                    }
                }
            }

            Grid { // actions
                columns: 2
                spacing: 10
                readonly property real cellW: (body.width - 10) / 2
                Repeater {
                    model: [
                        { a: "open", t: "Open", on: true },
                        { a: "force-close", t: "Force Close", on: !!info.appData.running },
                        { a: "clear-cache", t: "Clear Cache", on: info.appData.canClear !== false },
                        { a: "clear-data", t: info.confirm === "clear-data" ? "Tap again: erase data" : "Clear Data", on: info.appData.canClear !== false, danger: true },
                        { a: "hide", t: info.app && Theme.isHidden(info.app.id) ? "Unhide" : "Hide", on: true },
                        { a: "uninstall", t: info.confirm === "uninstall" ? "Tap again to uninstall" : "Uninstall", on: !!info.appData.canUninstall, danger: true }
                    ]
                    Rectangle {
                        required property var modelData
                        width: parent.cellW; height: 46; radius: 23
                        opacity: modelData.on && !info.busy ? 1 : 0.4
                        color: modelData.danger && info.confirm === modelData.a ? Theme.red
                             : b.containsMouse && modelData.on ? Theme.tileHover : Theme.tile
                        scale: b.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.fast } }
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        Text { anchors.centerIn: parent; text: modelData.t
                            color: modelData.danger ? (info.confirm === modelData.a ? "white" : Theme.red) : Theme.text
                            font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
                        MouseArea {
                            id: b
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: modelData.on && !info.busy
                            onClicked: {
                                if (modelData.a === "open") { info.app.execute(); ShellState.infoApp = null; ShellState.launchpad = false }
                                else if (modelData.a === "hide") Theme.setHidden(info.app.id, !Theme.isHidden(info.app.id))
                                else info.act(modelData.a, modelData.t)
                            }
                        }
                    }
                }
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
                text: info.message || info.appData.uninstallNote || ""
                color: Theme.subtext; font { family: Theme.font; pixelSize: 12 }
            }
        }
    }

    IpcHandler {
        target: "appinfo"
        function open(id: string): void {
            const e = DesktopEntries.applications.values.find(x => x.id === id)
            if (e) ShellState.infoApp = e
        }
        function close(): void { ShellState.infoApp = null }
        function kind(): string { return info.appData.kind || "" }
        function openMenu(id: string): string {
            const e = DesktopEntries.applications.values.find(x => x.id === id)
            if (!e) return ""
            ShellState.menuScreen = Quickshell.screens[0]
            ShellState.menuAt = Qt.point(600, 300)
            ShellState.menuFrom = "launchpad"
            ShellState.menuApp = e
            return "ok"
        }
    }
}
