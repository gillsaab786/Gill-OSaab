//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Gill-OSaab shell: menu bar, Dock, notifications, Control Centre, Spotlight.
ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Component { Wallpaper {} }
    }
    Variants {
        model: Quickshell.screens
        delegate: Component { DesktopWidgets {} }
    }
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
    Switcher {}
    OSD {}
    LockScreen {}
    GlassesProfiles {}
    BluetoothBatteries {}

    IpcHandler {
        target: "shell"
        function closeAll(): void { ShellState.closeAll() }
        function setDark(on: bool): void { Theme.set("mode", on ? "dark" : "light") }
        function appearance(key: string, value: string): void { Theme.set(key, value) }
        function iconStyle(): string { return Theme.iconStyle }
        function wallpaper(): string { return Theme.wallpaper }
        function ping(): string { return "gill-osaab shell ok" }
        function keyboard(): void { ShellState.toggleKeyboard() }
        function dockPopup(name: string): void { ShellState.dockPopup = name }
    }
}
