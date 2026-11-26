import QtQuick
import Quickshell

// The menu under the Gill(OS) logo (like the Apple menu).
Popup {
    id: menu
    open: ShellState.systemMenu
    alignLeft: true
    panelWidth: 300

    component Item_: Rectangle {
        property string label
        property string command
        property bool separatorAfter: false
        width: parent ? parent.width : 0
        height: 42; radius: 14
        color: m.containsMouse ? Theme.accent : "transparent"
        Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: parent.label; color: m.containsMouse ? "white" : Theme.text; font { family: Theme.font; pixelSize: 15 } }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true
            onClicked: { ShellState.closeAll(); ShellState.run(parent.command) } }
    }
    component Separator: Rectangle { width: parent ? parent.width : 0; height: 1; color: Theme.panelBorder }

    Item_ { label: "About Gill(OS)"; command: "gosaab-settings about" }
    Separator {}
    Item_ { label: "System Settings…"; command: "gosaab-settings" }
    Item_ { label: "Software Update…"; command: "gosaab-updates" }
    Item_ { label: "Switch to Game Mode"; command: "gosaab-game-mode || steamos-session-select gamescope" }
    Separator {}
    Item_ { label: "Sleep"; command: "systemctl suspend" }
    Item_ { label: "Restart…"; command: "systemctl reboot" }
    Item_ { label: "Shut Down…"; command: "systemctl poweroff" }
    Separator {}
    Item_ { label: "Lock Screen"; command: "qs -c gill-osaab ipc call lock lock" }
    Item_ { label: "Log Out"; command: "loginctl terminate-session \"$XDG_SESSION_ID\"" }
}
