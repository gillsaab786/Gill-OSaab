import QtQuick
import Quickshell
import Quickshell.Services.UPower

// A live wallpaper: a shader (shaders/<name>.frag, compiled to .frag.qsb when the image is built)
// that moves slowly and follows the real world: Earth's day and night from the clock and your
// time zone, tonight's moon phase, the desert sky through the day. Drawn at half resolution and
// scaled up (the pictures are soft), 30 frames a second, 15 on battery, still when Motion is off.
Item {
    id: live
    property string name: "flow"
    readonly property real res: 0.5
    property real t: 0
    property date now: new Date()
    readonly property bool moving: Theme.liveMotion && visible
    readonly property bool onBattery: UPower.onBattery

    // the still picture shows until the shader is ready (or if it can't load)
    Image {
        anchors.fill: parent
        source: "file://" + Theme.liveStill(live.name, Theme.dark)
        sourceSize: Qt.size(live.width, live.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: fx.status !== ShaderEffect.Compiled
    }
    ShaderEffect {
        id: fx
        width: Math.ceil(live.width * live.res)
        height: Math.ceil(live.height * live.res)
        scale: 1 / live.res
        transformOrigin: Item.TopLeft
        smooth: true
        fragmentShader: Qt.resolvedUrl("shaders/" + live.name + ".frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("live wallpaper", live.name, "failed:", log)

        property real time: live.t
        property real aspect: live.width / Math.max(1, live.height)
        property real dark: Theme.darkness
        // Earth: where the sun is overhead now, and which side of the world faces you
        readonly property real days: (live.now.getTime() - Date.UTC(live.now.getUTCFullYear(), 0, 1)) / 86400000
        readonly property real utcHours: live.now.getUTCHours() + live.now.getUTCMinutes() / 60
        property real sunLon: (12 - utcHours) * 15 * Math.PI / 180
        property real sunLat: -23.44 * Math.cos(2 * Math.PI * (days + 10) / 365.25) * Math.PI / 180
        property real viewLon: -live.now.getTimezoneOffset() / 4 * Math.PI / 180
        // Moon: tonight's phase (0 new, pi full)
        property real phase: {
            const synodic = 29.530588853
            const age = (live.now.getTime() - Date.UTC(2000, 0, 6, 18, 14)) / 86400000 / synodic
            return (age - Math.floor(age)) * 2 * Math.PI
        }
        // Dunes: how far through your day it is
        property real daytime: (live.now.getHours() + live.now.getMinutes() / 60) / 24
        // Flow: tinted towards the accent colour (blue = as designed)
        property real hue: Theme.accent.hslSaturation < 0.1 ? 0 : Theme.accent.hslHue - 0.585
    }
    Timer {
        interval: live.onBattery ? 66 : 33
        running: live.moving
        repeat: true
        onTriggered: { live.t += interval / 1000; ShellState.liveTime = live.t }
    }
    Timer { // the real-world parts change slowly: once a minute is plenty
        interval: 60000
        running: live.visible
        repeat: true
        onTriggered: live.now = new Date()
    }
}
