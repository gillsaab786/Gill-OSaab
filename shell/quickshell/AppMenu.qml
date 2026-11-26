import QtQuick
import Quickshell
import Quickshell.Wayland

// The app menu: right-click (or hold with a finger) an app in the Dock or Launchpad.
// Open, Quit, Keep in Dock, Hide, App Info.
PanelWindow {
    id: menu
    screen: ShellState.menuScreen || Quickshell.screens[0]
    visible: ShellState.menuApp !== null || card.opacity > 0.01
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gosaab-appmenu"
    WlrLayershell.keyboardFocus: ShellState.menuApp ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var app: null
    Connections { target: ShellState; function onMenuAppChanged() { if (ShellState.menuApp) menu.app = ShellState.menuApp } }
    readonly property var windows: !app ? [] : ToplevelManager.toplevels.values.filter(w => {
        const e = DesktopEntries.heuristicLookup(w.appId)
        return e && e.id === app.id
    })
    readonly property var items: !app ? [] : [
        { t: windows.length ? "New Window" : "Open", f: () => app.execute() },
        windows.length ? { t: "Quit", f: () => { for (const w of windows) w.close() } } : null,
        { sep: true },
        { t: Theme.inDock(app.id) ? "Remove from Dock" : "Keep in Dock", f: () => Theme.setInDock(app.id, !Theme.inDock(app.id)) },
        { t: Theme.isHidden(app.id) ? "Unhide App" : "Hide App", f: () => Theme.setHidden(app.id, !Theme.isHidden(app.id)) },
        { sep: true },
        { t: "App Info…", f: () => { ShellState.infoApp = app } }
    ].filter(x => x)

    function pick(item) {
        ShellState.menuApp = null
        ShellState.haptic("toggle")
        item.f()
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: ShellState.menuApp = null }
    Item { focus: true; Keys.onEscapePressed: ShellState.menuApp = null }

    Rectangle {
        id: card
        readonly property bool fromDock: ShellState.menuFrom === "dock"
        width: 230
        height: col.implicitHeight + 12
        x: Math.max(8, Math.min(menu.width - width - 8, ShellState.menuAt.x - width / 2))
        y: fromDock ? ShellState.menuAt.y - height - 14 : Math.min(menu.height - height - 8, ShellState.menuAt.y + 40)
        radius: 16
        color: Theme.panel
        GlassRim { radius: 16 }
        opacity: ShellState.menuApp ? 1 : 0
        scale: ShellState.menuApp ? 1 : 0.92
        transformOrigin: fromDock ? Item.Bottom : Item.Top
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.002 } }
        MouseArea { anchors.fill: parent } // clicks inside don't close it

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            Text {
                width: parent.width; leftPadding: 12; topPadding: 6; bottomPadding: 6
                text: menu.app ? Theme.displayName(menu.app) : ""
                elide: Text.ElideRight
                color: Theme.subtext; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
            }
            Repeater {
                model: menu.items
                Item {
                    required property var modelData
                    width: col.width
                    height: modelData.sep ? 9 : 38
                    Rectangle { visible: !!modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Qt.rgba(0.5, 0.5, 0.5, 0.25) }
                    Rectangle {
                        visible: !modelData.sep
                        anchors.fill: parent; radius: 10
                        color: row.containsMouse ? Theme.accent : "transparent"
                        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: modelData.t || ""; color: row.containsMouse ? "white" : Theme.text
                            font { family: Theme.font; pixelSize: 14 } }
                        MouseArea { id: row; anchors.fill: parent; hoverEnabled: true; onClicked: menu.pick(modelData) }
                    }
                }
            }
        }
    }
}
