//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Gill-OSaab shell: menu bar, Dock, notifications, Control Centre, Spotlight.
ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Component { TopBar {} }
    }
    Variants {
        model: Quickshell.screens
        delegate: Component { Dock {} }
    }

    // Click anywhere outside an open menu/panel to close it
    PanelWindow {
        visible: ShellState.anyPopup
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "gosaab-dismiss"
        MouseArea { anchors.fill: parent; onClicked: ShellState.closeAll() }
    }

    SystemMenu {}
    ControlCenter {}
    Notifications {}
    Spotlight {}
    Launchpad {}

    IpcHandler {
        target: "shell"
        function closeAll(): void { ShellState.closeAll() }
        function setDark(on: bool): void { Theme.dark = on }
        function ping(): string { return "gill-osaab shell ok" }
    }
}
