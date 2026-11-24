import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Volume / brightness bezel, like macOS: a glass square near the bottom with the icon and a level
// bar; fades away after a moment. Shown for the volume and brightness keys (the compositor calls
// `osd volume up` etc.) and handhelds' volume rocker.
PanelWindow {
    id: osd
    property string kind: "volume"
    property real level: 0.5
    property bool muted: false
    property bool shown: false

    anchors { bottom: true }
    margins { bottom: 120 }
    implicitWidth: 220
    implicitHeight: 220
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: shown || box.opacity > 0.01
    WlrLayershell.namespace: "gosaab-osd:r30"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {} // clicks go through

    Timer { id: hide; interval: 1400; onTriggered: osd.shown = false }

    Process { id: runner }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: osd.parse(text) }
    }

    function parse(out) {
        if (kind === "volume") {
            const m = out.match(/Volume:\s*([0-9.]+)/)
            if (m) level = Math.min(1.5, parseFloat(m[1]))
            muted = out.indexOf("MUTED") >= 0
        } else {
            const p = out.trim().split(",") // brightnessctl -m: name,class,current,percent,max
            if (p.length >= 4) level = parseInt(p[3]) / 100
        }
    }

    function change(what, dir) {
        kind = what
        if (what === "volume") {
            runner.command = dir === "mute" ? ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
                : ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", dir === "up" ? "5%+" : "5%-"]
            reader.command = ["sh", "-c", "sleep 0.05; wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        } else {
            runner.command = ["brightnessctl", "-q", "set", dir === "up" ? "+5%" : "5%-"]
            reader.command = ["sh", "-c", "sleep 0.05; brightnessctl -m"]
        }
        runner.running = true
        reader.running = true
        ShellState.haptic("tick")
        shown = true
        hide.restart()
    }

    IpcHandler {
        target: "osd"
        function volume(dir: string): void { osd.change("volume", dir) }
        function brightness(dir: string): void { osd.change("brightness", dir) }
        function isShown(): bool { return osd.shown }
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: 190; height: 190; radius: 36
        color: Theme.panel
        border { color: Theme.panelBorder; width: 1 }
        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: osd.shown ? 120 : 380; easing.type: Easing.OutCubic } }
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
        GlassRim { radius: 36 }
        Icon {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 38 }
            width: 72; height: 72
            name: osd.kind === "volume" ? "volume" : "sun"
            level: osd.muted ? 0 : osd.level
            color: Theme.text
        }
        Rectangle { // level bar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
            height: 8; radius: 4
            color: Qt.rgba(1, 1, 1, 0.16)
            Rectangle {
                width: parent.width * Math.min(1, osd.muted ? 0 : osd.level); height: parent.height; radius: 4
                color: Theme.text
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }
    }
}
