import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Control Centre: quick toggles and sliders, like macOS/iOS.
Popup {
    id: cc
    open: ShellState.controlCenter
    panelWidth: 380

    property bool wifiOn: true
    property bool btOn: false
    property bool vpnOn: false
    property real brightness: 0.7
    readonly property var sink: Pipewire.defaultAudioSink

    PwObjectTracker { objects: cc.sink ? [cc.sink] : [] }

    // Read the current state whenever Control Centre opens
    onOpenChanged: if (open) { wifiState.running = true; btState.running = true; vpnState.running = true; lightState.running = true }
    Process { id: wifiState; command: ["sh", "-c", "nmcli -t radio wifi 2>/dev/null || echo enabled"]
        stdout: StdioCollector { onStreamFinished: cc.wifiOn = text.trim() !== "disabled" } }
    Process { id: btState; command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: cc.btOn = text.trim() === "on" } }
    // VPN tile only when VPN is turned on in Settings; it connects your first VPN
    property bool vpnEnabled: false
    property string vpnName: ""
    Process { id: vpnState; command: ["sh", "-c", "grep -qx 'vpn=on' /etc/gill-osaab/features.conf 2>/dev/null || exit 0; " +
            "echo enabled; nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null | grep -E ':(wireguard|vpn):' | head -1"]
        stdout: StdioCollector { onStreamFinished: {
            const lines = text.trim().split("\n")
            cc.vpnEnabled = lines[0] === "enabled"
            const f = (lines[1] || "").split(":")
            cc.vpnName = f[0] || ""
            cc.vpnOn = f[2] === "yes"
        } } }
    Process { id: lightState; command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d %"]
        stdout: StdioCollector { onStreamFinished: { const v = parseInt(text); if (!isNaN(v)) cc.brightness = v / 100 } } }

    Grid {
        width: parent.width
        columns: 2
        spacing: 10
        Tile { width: (parent.width - 10) / 2; icon: "wifi"; label: "Wi-Fi"; detail: cc.wifiOn ? "On" : "Off"; on: cc.wifiOn
            onToggled: { cc.wifiOn = !cc.wifiOn; ShellState.run("nmcli radio wifi " + (cc.wifiOn ? "on" : "off")) } }
        Tile { width: (parent.width - 10) / 2; icon: "bluetooth"; label: "Bluetooth"; detail: cc.btOn ? "On" : "Off"; on: cc.btOn
            onToggled: { cc.btOn = !cc.btOn; ShellState.run("bluetoothctl power " + (cc.btOn ? "on" : "off")) } }
        Tile { width: (parent.width - 10) / 2; icon: "moon"; label: "Focus"; detail: ShellState.doNotDisturb ? "Do Not Disturb" : "Off"
            on: ShellState.doNotDisturb; onToggled: ShellState.doNotDisturb = !ShellState.doNotDisturb }
        Tile { width: (parent.width - 10) / 2; icon: "darkmode"; label: "Dark Mode"; detail: Theme.dark ? "On" : "Off"; on: Theme.dark
            onToggled: { Theme.dark = !Theme.dark; ShellState.run("gsettings set org.gnome.desktop.interface color-scheme " + (Theme.dark ? "prefer-dark" : "default")) } }
        Tile { width: (parent.width - 10) / 2; icon: "gamepad"; label: "Game Mode"; detail: "Switch now"
            onToggled: { ShellState.closeAll(); ShellState.run("gosaab-game-mode || steamos-session-select gamescope") } }
        Tile { width: (parent.width - 10) / 2; icon: "shield"; label: "VPN"; visible: cc.vpnEnabled
            detail: cc.vpnName === "" ? "Add one in Settings" : (cc.vpnOn ? cc.vpnName : "Off"); on: cc.vpnOn
            onToggled: {
                if (cc.vpnName === "") { ShellState.closeAll(); ShellState.run("gosaab-settings vpn"); return }
                cc.vpnOn = !cc.vpnOn
                Quickshell.execDetached(["nmcli", "connection", cc.vpnOn ? "up" : "down", "id", cc.vpnName]) // no shell: names can't run commands
            } }
        Tile { width: (parent.width - 10) / 2; icon: "screenoff"; label: "Screen Off"; detail: "Wakes when done"
            onToggled: { ShellState.closeAll(); ShellState.run("gosaab-screen-off") } }
        Tile { width: (parent.width - 10) / 2; icon: "keyboard"; label: "Keyboard"; detail: "Type with touch"
            onToggled: { ShellState.closeAll(); ShellState.toggleKeyboard() } }
        Tile { width: (parent.width - 10) / 2; icon: "glasses"; label: "Glasses"; detail: "XREAL mode"
            onToggled: { ShellState.closeAll(); ShellState.run("gosaab-settings glasses") } }
    }

    Rectangle {
        width: parent.width; height: sliders.implicitHeight + 20; radius: 24
        color: Theme.tile
        Column {
            id: sliders
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 8
            SliderRow { width: parent.width; label: "Display"; icon: "sun"; value: cc.brightness
                onMoved: v => ShellState.run("brightnessctl -q set " + Math.max(1, Math.round(v * 100)) + "%") }
            SliderRow { width: parent.width; label: "Sound"; icon: "volume"
                value: cc.sink && cc.sink.audio ? cc.sink.audio.volume : 0.5
                onMoved: v => { if (cc.sink && cc.sink.audio) cc.sink.audio.volume = v } }
        }
    }

    Rectangle {
        width: parent.width; height: 44; radius: 22
        color: settingsMouse.containsMouse ? Theme.tileHover : Theme.tile
        Text { anchors.centerIn: parent; text: "Gill-OSaab Settings…"; color: Theme.text; font { family: Theme.font; pixelSize: 13 } }
        MouseArea { id: settingsMouse; anchors.fill: parent; hoverEnabled: true
            onClicked: { ShellState.closeAll(); ShellState.run("gosaab-settings") } }
    }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { ShellState.toggle("controlCenter") }
    }
}
