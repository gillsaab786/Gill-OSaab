import QtQuick

// A wide macOS-style slider with an icon inside the track.
Item {
    id: row
    property string label: ""
    property string icon: "sun"
    property real value: 0.5
    signal moved(real v)
    implicitHeight: 60
    Text { id: title; text: row.label; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        // grows a little while you hold it, like iOS
        height: drag.pressed ? 38 : 32; radius: height / 2
        Behavior on height { SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.2 } }
        color: Qt.rgba(1, 1, 1, 0.12)
        clip: true
        Rectangle {
            width: Math.max(track.height, track.width * row.value); height: parent.height; radius: track.radius
            color: "white"; opacity: 0.92
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Theme.fast } }
        }
        Icon { anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter } name: row.icon; level: row.value; width: 15; height: 15; color: "#3a3a3c" }
        MouseArea {
            id: drag
            anchors.fill: parent
            property int lastStep: -1
            function set(x) {
                row.value = Math.max(0, Math.min(1, x / width))
                const step = Math.round(row.value * 10) // a tick every 10 %, a firmer one at the ends
                if (step !== lastStep) {
                    ShellState.haptic(step === 0 || step === 10 ? "toggle" : "tick")
                    lastStep = step
                }
                row.moved(row.value)
            }
            onPressed: m => set(m.x)
            onPositionChanged: m => { if (pressed) set(m.x) }
        }
    }
}
