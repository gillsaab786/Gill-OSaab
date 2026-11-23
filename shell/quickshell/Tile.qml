import QtQuick

// A Control Centre toggle: round icon that lights up blue when on, with a label.
Rectangle {
    id: tile
    property string icon: "dot"
    property string label: ""
    property string detail: ""
    property bool on: false
    signal toggled()
    implicitHeight: 60
    radius: 30
    scale: mouse.pressed ? 0.95 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.002 } }
    color: mouse.containsMouse ? Theme.tileHover : Theme.tile
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Row {
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 9
        Rectangle {
            width: 34; height: 34; radius: 17
            color: tile.on ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: Theme.normal } }
            Icon { anchors.centerIn: parent; name: tile.icon; width: 18; height: 18; color: "white" }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: tile.label; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
            Text { visible: text !== ""; text: tile.detail; color: Theme.subtext; font { family: Theme.font; pixelSize: 11 } }
        }
    }
    GlassRim { radius: 30; strength: 0.6 }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: tile.toggled() }
}
