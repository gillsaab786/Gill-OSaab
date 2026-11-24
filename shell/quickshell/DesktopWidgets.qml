import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

// Desktop widgets, macOS Tahoe style: glass cards on the desktop, under your windows.
// Pick them in Settings > Appearance > Widgets (saved in appearance.json "widgets").
PanelWindow {
    id: desk
    property var modelData
    screen: modelData
    anchors { top: true; left: true }
    margins { top: Theme.barHeight + 18; left: 22 }
    implicitWidth: 362
    implicitHeight: Math.max(10, cards.implicitHeight)
    visible: cards.visibleChildren.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "gill-osaab-widgets"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // weather (Open-Meteo, refreshed every 30 minutes)
    property var weather: ({})
    readonly property string city: Theme.setting("city", "")
    onCityChanged: weatherProc.running = true
    Process {
        id: weatherProc
        command: [(Quickshell.env("GOSAAB_LIBEXEC") || "/usr/libexec/gill-osaab") + "/gosaab-weather", desk.city]
        stdout: StdioCollector { onStreamFinished: { try { desk.weather = JSON.parse(text) } catch (e) {} } }
    }
    Timer { interval: 30 * 60 * 1000; running: Theme.widgetOn("weather", true); repeat: true; triggeredOnStart: true
        onTriggered: weatherProc.running = true }
    function weatherIcon(code) {
        if (code === undefined) return "cloud"
        if (code <= 1) return desk.weather.day === false ? "moon" : "sun"
        if (code >= 95) return "storm"
        if ((code >= 71 && code <= 77) || code >= 85) return "snow"
        if (code >= 51) return "rain"
        return "cloud"
    }

    // CPU and memory, every 2 seconds
    property real cpu: 0
    property real mem: 0
    property var lastCpu: [0, 0]
    FileView { id: stat; path: "/proc/stat"; printErrors: false }
    FileView { id: meminfo; path: "/proc/meminfo"; printErrors: false }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: Theme.widgetOn("stats", false)
        onTriggered: {
            stat.reload(); meminfo.reload()
            const f = (stat.text().split("\n")[0] || "").trim().split(/\s+/).slice(1).map(Number)
            if (f.length > 4) {
                const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0)
                const dt = total - desk.lastCpu[0], di = idle - desk.lastCpu[1]
                if (desk.lastCpu[0] > 0 && dt > 0) desk.cpu = Math.max(0, Math.min(1, 1 - di / dt))
                desk.lastCpu = [total, idle]
            }
            const m = meminfo.text()
            const tot = parseInt((m.match(/MemTotal:\s+(\d+)/) || [0, 0])[1])
            const avail = parseInt((m.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1])
            if (tot > 0) desk.mem = 1 - avail / tot
        }
    }

    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property var battery: UPower.displayDevice

    component Card: Rectangle {
        default property alias content: inner.data
        property bool wide: false
        width: wide ? 362 : 175; height: 175
        radius: 26
        color: Theme.mix(Qt.rgba(1, 1, 1, 0.42), Qt.rgba(0.08, 0.09, 0.12, 0.42))
        GlassRim { radius: 26 }
        Item { id: inner; anchors { fill: parent; margins: 16 } }
    }
    component Label: Text { color: Theme.text; font.family: Theme.font }

    Flow {
        id: cards
        width: 362
        spacing: 12

        Card { // Clock
            visible: Theme.widgetOn("clock", true)
            Label { id: day; text: Qt.formatDate(clock.date, "dddd").toUpperCase(); color: Theme.red
                font { pixelSize: 12; weight: Font.Bold; letterSpacing: 0.6 } }
            Label { anchors { top: day.bottom; topMargin: 2 }
                text: Qt.formatDate(clock.date, "d MMMM"); color: Theme.subtext; font.pixelSize: 13 }
            Label { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: -6 }
                text: Qt.formatTime(clock.date, "h:mm"); font { pixelSize: 54; weight: Font.Light } }
        }
        Card { // Weather
            visible: Theme.widgetOn("weather", true)
            gradient: Gradient {
                GradientStop { position: 0; color: desk.weather.day === false ? Qt.rgba(0.10, 0.14, 0.32, 0.78) : Qt.rgba(0.20, 0.52, 0.95, 0.72) }
                GradientStop { position: 1; color: desk.weather.day === false ? Qt.rgba(0.05, 0.07, 0.18, 0.78) : Qt.rgba(0.36, 0.68, 1.0, 0.62) }
            }
            Label { id: place; width: parent.width; elide: Text.ElideRight; color: "white"
                text: desk.weather.city || "Weather"; font { pixelSize: 14; weight: Font.DemiBold } }
            Label { anchors.top: place.bottom; color: "white"; text: desk.weather.temp !== undefined ? desk.weather.temp + "°" : "—"
                font { pixelSize: 44; weight: Font.Light } }
            Icon { anchors { right: parent.right; top: parent.top; topMargin: 26 }
                width: 30; height: 30; color: "white"; name: desk.weatherIcon(desk.weather.code) }
            Label { anchors.bottom: parent.bottom; width: parent.width; color: "white"; wrapMode: Text.Wrap
                text: desk.weather.error ? desk.weather.error
                    : (desk.weather.text || "") + (desk.weather.high !== undefined ? "\nH:" + desk.weather.high + "°  L:" + desk.weather.low + "°" : "")
                font { pixelSize: 12; weight: Font.Medium } }
        }
        Card { // Calendar: this month, today circled
            id: cal
            visible: Theme.widgetOn("calendar", true)
            readonly property date now: clock.date
            readonly property int first: new Date(now.getFullYear(), now.getMonth(), 1).getDay()
            readonly property int days: new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
            Label { id: month; text: Qt.formatDate(clock.date, "MMMM").toUpperCase(); color: Theme.red
                font { pixelSize: 11; weight: Font.Bold; letterSpacing: 0.6 } }
            Grid {
                anchors { top: month.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                columns: 7; columnSpacing: 1; rowSpacing: 1
                Repeater {
                    model: 7
                    Label { required property int index; width: 19; height: 15; horizontalAlignment: Text.AlignHCenter
                        text: "SMTWTFS"[index]; color: Theme.subtext; font { pixelSize: 9; weight: Font.DemiBold } }
                }
                Repeater {
                    model: cal.first + cal.days
                    Item {
                        required property int index
                        readonly property int d: index - cal.first + 1
                        readonly property bool today: d === clock.date.getDate()
                        width: 19; height: 17
                        Rectangle { anchors.centerIn: parent; width: 17; height: 17; radius: 8.5; color: Theme.red; visible: parent.today }
                        Label { anchors.centerIn: parent; text: parent.d > 0 ? parent.d : ""; color: parent.today ? "white" : Theme.text
                            font { pixelSize: 10; weight: parent.today ? Font.Bold : Font.Normal } }
                    }
                }
            }
        }
        Card { // Battery
            visible: Theme.widgetOn("battery", true) && !!desk.battery && desk.battery.isLaptopBattery
            ProgressRing { anchors.centerIn: parent; anchors.verticalCenterOffset: -10; width: 92; height: 92
                value: desk.battery ? desk.battery.percentage * 100 : 0 }
            Label { anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                text: desk.battery && desk.battery.state === UPowerDeviceState.Charging ? "Charging" : "Battery"
                color: Theme.subtext; font { pixelSize: 12; weight: Font.Medium } }
        }
        Card { // Now playing (any app that shares its media: browsers, VLC, Spotify...)
            wide: true
            visible: Theme.widgetOn("nowPlaying", true) && !!desk.player
            Rectangle {
                id: art
                width: 110; height: 110; radius: 16; clip: true
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.15)
                Image { anchors.fill: parent; source: desk.player ? desk.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            Column {
                anchors { left: art.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3
                Label { width: parent.width; elide: Text.ElideRight; text: desk.player ? (desk.player.trackTitle || desk.player.identity) : ""
                    font { pixelSize: 15; weight: Font.DemiBold } }
                Label { width: parent.width; elide: Text.ElideRight; text: desk.player ? (desk.player.trackArtist || "") : ""
                    color: Theme.subtext; font.pixelSize: 13 }
                Row {
                    topPadding: 10; spacing: 22
                    Icon { width: 26; height: 26; name: desk.player && desk.player.isPlaying ? "pause" : "play"
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: desk.player.togglePlaying() } }
                    Icon { width: 26; height: 26; name: "next"
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: desk.player.next() } }
                }
            }
        }
        Card { // System: processor and memory use
            wide: true
            visible: Theme.widgetOn("stats", false)
            Column {
                anchors.fill: parent
                spacing: 14
                Repeater {
                    model: [{ t: "Processor", v: desk.cpu, c: Theme.accent }, { t: "Memory", v: desk.mem, c: Theme.green }]
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 6
                        Label { text: modelData.t + "  " + Math.round(modelData.v * 100) + "%"; font { pixelSize: 13; weight: Font.DemiBold } }
                        Rectangle { width: parent.width; height: 12; radius: 6; color: Qt.rgba(0.5, 0.5, 0.5, 0.25)
                            Rectangle { width: parent.width * modelData.v; height: 12; radius: 6; color: modelData.c
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "widgets"
        function shown(): string {
            return ["clock", "weather", "calendar", "battery", "nowPlaying", "stats"]
                .filter(n => Theme.widgetOn(n, n !== "stats")).join(",")
        }
    }
}
