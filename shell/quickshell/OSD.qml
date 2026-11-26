import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Volume / brightness, like macOS Tahoe: a glass pill drops in at the top right with the sound
// output's name and a slider you can drag; it slides away after a moment. Shown for the volume and
// brightness keys (the compositor calls `osd volume up` etc.) and handhelds' volume rocker.
PanelWindow {
    id: osd
    property string kind: "volume"
    property real level: 0.5
    property bool muted: false
    property bool shown: false
    property string device: ""

    anchors { top: true; right: true }
    margins { top: 6; right: 10 }
    // 3D glasses (side by side): the pill shows once for each eye, so it reads as one in 3D
    readonly property real eyeShift: ShellState.stereo && screen ? screen.width / 2 : 0
    implicitWidth: 330 + eyeShift
    implicitHeight: 96
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: shown || box.opacity > 0.01
    WlrLayershell.namespace: "gosaab-osd:r30"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: osd.shown ? box : null } // the slider can be dragged while it shows

    Timer { id: hide; interval: 1800; onTriggered: if (!drag.pressed) osd.shown = false }

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
            const d = out.match(/^name=(.*)$/m)
            device = d ? d[1] : "Speakers"
        } else {
            device = "Display"
            const p = out.trim().split(",") // brightnessctl -m: name,class,current,percent,max
            if (p.length >= 4) level = parseInt(p[3]) / 100
        }
    }

    function change(what, dir) {
        kind = what
        if (what === "volume") {
            runner.command = dir === "mute" ? ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
                : ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", dir === "up" ? "5%+" : "5%-"]
            reader.command = ["sh", "-c", "sleep 0.05; wpctl get-volume @DEFAULT_AUDIO_SINK@; "
                + "wpctl inspect @DEFAULT_AUDIO_SINK@ | sed -n 's/.*node.description = \"\\(.*\\)\"/name=\\1/p' | head -1"]
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

    // dragging the slider sets the level directly
    function setLevel(v) {
        level = Math.max(0, Math.min(1, v))
        runner.command = kind === "volume" ? ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", level.toFixed(2)]
            : ["brightnessctl", "-q", "set", Math.max(1, Math.round(level * 100)) + "%"]
        runner.running = true
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
        anchors { left: parent.left; top: parent.top; leftMargin: osd.width - 330 - osd.eyeShift + 10 }
        width: 320; height: 84; radius: 26
        color: Theme.panel
        opacity: osd.shown ? 1 : 0
        transform: Translate { y: osd.shown ? 0 : -30; Behavior on y { SpringAnimation { spring: 4.5; damping: 0.4; epsilon: 0.2 } } }
        scale: osd.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: osd.shown ? 140 : 360; easing.type: Easing.OutCubic } }
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
        GlassRim { radius: 26 }
        Text {
            anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 13; right: parent.right; rightMargin: 18 }
            text: osd.kind === "volume" ? (osd.device || "Sound") : "Display"
            elide: Text.ElideRight
            color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Item { // slider: a glass track that fills; its knob grows while you drag
            id: track
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 14 }
            height: 30
            Rectangle {
                id: groove
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: drag.pressed ? 26 : 22; radius: height / 2
                Behavior on height { NumberAnimation { duration: Theme.fast } }
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                Rectangle {
                    width: Math.max(parent.height, parent.width * Math.min(1, osd.muted ? 0 : osd.level))
                    height: parent.height; radius: height / 2
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.92) : "white"
                    Behavior on width { NumberAnimation { duration: drag.pressed ? 0 : 120; easing.type: Easing.OutCubic } }
                }
                Icon {
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 16; height: 16
                    name: osd.kind === "volume" ? "volume" : "sun"
                    level: osd.muted ? 0 : osd.level
                    color: "#3a3a3c"
                }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                onPressed: m => osd.setLevel(m.x / width)
                onPositionChanged: m => { if (pressed) osd.setLevel(m.x / width) }
                onReleased: ShellState.haptic("tick")
            }
        }
    }
    ShaderEffectSource { // the second eye's copy
        visible: osd.eyeShift > 0
        sourceItem: osd.eyeShift > 0 ? box : null
        x: box.x + osd.eyeShift; y: box.y
        width: box.width; height: box.height
        opacity: box.opacity
        live: true
    }
}
