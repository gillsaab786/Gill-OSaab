import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Game Mode <-> Desktop, Nintendo Switch + macOS style: the screen frosts over, a glass card
// springs up with a chime, then fades to black (to Game Mode). Coming back, the desktop
// fades up from black behind a shrinking glass card while the Dock rises into place.
PanelWindow {
    id: tr
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gosaab-transition"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: curtain.opacity > 0.001 || tile.opacity > 0.001
    mask: Region {} // never takes clicks

    property string glyph: "gamepad"
    property string label: "Game Mode"
    readonly property string media: "/usr/share/gill-osaab/media/mode-switch.wav"
    function chime() { Quickshell.execDetached(["sh", "-c", "command -v pw-play >/dev/null && exec pw-play \"$1\"", "sh", media]) }

    // -> Game Mode
    function toGame() {
        glyph = "gamepad"; label = "Game Mode"
        intro.stop(); outro.restart()
        chime(); ShellState.haptic("success")
        ShellState.closeAll()
    }
    SequentialAnimation {
        id: outro
        ParallelAnimation {
            NumberAnimation { target: curtain; property: "opacity"; from: 0; to: 0.72; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: tile; property: "opacity"; from: 0; to: 1; duration: 180 }
            NumberAnimation { target: tile; property: "scale"; from: 0.55; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { target: ShellState; property: "intro"; to: 0; duration: 420; easing.type: Easing.InCubic }
        }
        PauseAnimation { duration: 140 }
        ParallelAnimation {
            NumberAnimation { target: curtain; property: "opacity"; to: 1; duration: 300; easing.type: Easing.InQuad }
            NumberAnimation { target: tile; property: "scale"; to: 1.35; duration: 300; easing.type: Easing.InQuad }
            NumberAnimation { target: tile; property: "opacity"; to: 0; duration: 300 }
        }
    }

    // <- arriving on the desktop (from Game Mode, or after signing in)
    SequentialAnimation {
        id: intro
        PropertyAction { target: curtain; property: "opacity"; value: 1 }
        PropertyAction { target: tile; property: "opacity"; value: tr.fromGame ? 1 : 0 }
        PropertyAction { target: tile; property: "scale"; value: 1.25 }
        PropertyAction { target: ShellState; property: "intro"; value: 0 }
        PauseAnimation { duration: 250 }
        ScriptAction { script: if (tr.fromGame) { tr.chime(); ShellState.haptic("success") } }
        ParallelAnimation {
            NumberAnimation { target: tile; property: "scale"; to: 0.8; duration: 650; easing.type: Easing.OutCubic }
            NumberAnimation { target: tile; property: "opacity"; to: 0; duration: 650; easing.type: Easing.InQuad }
            NumberAnimation { target: curtain; property: "opacity"; to: 0; duration: 750; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 180 }
                NumberAnimation { target: ShellState; property: "intro"; to: 1; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }
    }

    property bool fromGame: false
    FileView {
        id: arrive
        path: (Quickshell.env("HOME") || "/tmp") + "/.cache/gill-osaab/arrive"
        printErrors: false
        onLoaded: {
            tr.fromGame = text().trim() !== ""
            tr.glyph = "desktop"; tr.label = "Desktop"
            Quickshell.execDetached(["rm", "-f", arrive.path])
            intro.restart()
        }
        onLoadFailed: { tr.fromGame = false; intro.restart() }
    }

    Rectangle { // the frosted curtain (black at full opacity)
        id: curtain
        anchors.fill: parent
        opacity: 0
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0.02, 0.04, 0.12, 1) }
            GradientStop { position: 1; color: "black" }
        }
    }
    Item {
        id: tile
        anchors.centerIn: parent
        width: 220; height: 270
        opacity: 0
        Rectangle {
            id: glass
            width: 200; height: 200; radius: 52
            anchors.horizontalCenter: parent.horizontalCenter
            color: Qt.rgba(1, 1, 1, 0.14)
            GlassRim { radius: 52; strength: 1.4 }
            Rectangle { // soft blue glow behind the glass
                z: -1; anchors.centerIn: parent; width: parent.width + 60; height: width; radius: width / 2
                color: Qt.rgba(0.24, 0.55, 1, 0.22)
            }
            Icon { anchors.centerIn: parent; width: 110; height: 110; name: tr.glyph === "gamepad" ? "gamepad" : "apps"; color: "white" }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: glass.bottom; topMargin: 22 }
            text: tr.label; color: "white"
            font { family: Theme.font; pixelSize: 26; weight: Font.DemiBold }
        }
    }

    IpcHandler {
        target: "transition"
        function toGame(): void { tr.toGame() }
        function arrive(): void { tr.fromGame = true; tr.glyph = "desktop"; tr.label = "Desktop"; intro.restart() }
        function busy(): bool { return outro.running || intro.running }
    }
}
