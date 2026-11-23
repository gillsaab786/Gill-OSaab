import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Battery of every connected Bluetooth device (headphones, controllers, mice...): shown in the
// menu bar, with a reminder at 20% and again at 10%.
Scope {
    id: root
    readonly property var devices: Bluetooth.devices.values.filter(d => d.connected && d.batteryAvailable)
    property var warned: ({}) // device address -> lowest threshold already announced

    function percent(d) { return Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) }

    function check() {
        const w = Object.assign({}, root.warned)
        for (const d of root.devices) {
            const key = d.address || d.name
            const p = percent(d)
            if (p > 25) { delete w[key]; continue } // charged again: remind next time
            for (const level of [10, 20]) {
                if (p <= level && (w[key] === undefined || w[key] > level)) {
                    w[key] = level
                    Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", "battery-caution",
                        "-u", level === 10 ? "critical" : "normal", "-h", "int:value:" + p,
                        (d.name || d.deviceName) + " battery is low",
                        p + "% left" + (level === 10 ? ". Charge it soon." : ".")])
                    break
                }
            }
        }
        root.warned = w
    }

    Instantiator {
        model: root.devices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onBatteryChanged() { root.check() }
        }
    }
    onDevicesChanged: check()
}
