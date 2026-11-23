import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower

// The menu bar across the top of the screen, macOS style.
PanelWindow {
    id: bar
    property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "gosaab-bar"
    WlrLayershell.layer: WlrLayer.Top

    readonly property var active: ToplevelManager.activeToplevel
    readonly property string appName: {
        if (!active) return "Desktop"
        const e = DesktopEntries.heuristicLookup(active.appId)
        return e ? e.name : (active.appId || active.title || "")
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Rectangle {
        anchors.fill: parent
        color: Theme.bar

    }

    Row {
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 4
        BarButton {
            active: ShellState.systemMenu
            onClicked: ShellState.toggle("systemMenu")
            Icon { name: "logo"; width: 17; height: 17; color: Theme.text }
        }
        BarButton {
            Text { text: bar.appName; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.Bold } }
        }
    }

    Row {
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 2
        BarButton {
            visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
            readonly property real pct: UPower.displayDevice ? UPower.displayDevice.percentage : 1
            Text {
                text: Math.round(parent.parent.pct * 100) + "%"
                color: Theme.text; font { family: Theme.font; pixelSize: 12 }
                anchors.verticalCenter: parent.verticalCenter
            }
            Icon { name: "battery"; level: parent.parent.pct; width: 22; height: 22; color: Theme.text }
        }
        BarButton {
            onClicked: ShellState.toggle("controlCenter")
            Icon { name: "wifi"; level: 1; width: 16; height: 16 }
        }
        BarButton {
            onClicked: ShellState.toggle("spotlight")
            Icon { name: "search"; width: 15; height: 15 }
        }
        BarButton {
            active: ShellState.controlCenter
            onClicked: ShellState.toggle("controlCenter")
            Icon { name: "controls"; width: 16; height: 16 }
        }
        BarButton {
            active: ShellState.notificationCenter
            onClicked: ShellState.toggle("notificationCenter")
            Text {
                text: Qt.formatDateTime(clock.date, "ddd d MMM  h:mm AP")
                color: Theme.text
                font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
            }
        }
    }
}
