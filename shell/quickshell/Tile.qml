import QtQuick

// A Control Centre toggle: round icon that lights up blue when on, with a label.
Rectangle {
    id: tile
    property string icon: "dot"
    property string label: ""
    property string detail: ""
    property bool on: false
    signal toggled()
    implicitHeight: 68
    radius: 34
    scale: mouse.pressed ? 0.95 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
    color: mouse.containsMouse ? Theme.tileHover : Theme.tile
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Row {
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 9
        Rectangle {
            width: 40; height: 40; radius: 20
            color: tile.on ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: Theme.normal } }
            Icon { anchors.centerIn: parent; name: tile.icon; width: 21; height: 21; color: "white" }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: tile.label; color: Theme.text; font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
            Text { visible: text !== ""; text: tile.detail; color: Theme.subtext; font { family: Theme.font; pixelSize: 12 } }
        }
    }
    GlassRim { radius: 34; strength: 0.6 }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: tile.toggled() }
}
