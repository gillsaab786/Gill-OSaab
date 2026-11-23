import QtQuick

// A rounded, softly highlighted button for the top bar.
Rectangle {
    id: btn
    property bool active: false
    signal clicked()
    default property alias content: row.data
    implicitWidth: row.implicitWidth + 16
    implicitHeight: 24
    radius: 6
    color: active ? Qt.rgba(1, 1, 1, 0.20) : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: btn.clicked()
    }
}
