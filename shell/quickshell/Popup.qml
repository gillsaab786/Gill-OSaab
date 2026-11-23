import QtQuick
import Quickshell
import Quickshell.Wayland

// A glass panel that drops down from the top bar with a quick spring (Control Centre, menus...).
PanelWindow {
    id: popup
    property bool open: false
    property int panelWidth: 340
    property bool alignLeft: false
    default property alias content: inner.data

    anchors { top: true; left: alignLeft; right: !alignLeft }
    margins { top: 6; left: 8; right: 8 }
    implicitWidth: panelWidth
    implicitHeight: Math.max(1, inner.implicitHeight + 28)
    color: "transparent"
    visible: open || panel.opacity > 0.01
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gosaab-popup:r18"
    WlrLayershell.layer: WlrLayer.Overlay

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 18
        color: Theme.panel
        border { color: Theme.panelBorder; width: 1 }
        opacity: popup.open ? 1 : 0
        scale: popup.open ? 1 : 0.94
        transformOrigin: popup.alignLeft ? Item.TopLeft : Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.38; epsilon: 0.002 } }
        Column {
            id: inner
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10
        }
    }
}
