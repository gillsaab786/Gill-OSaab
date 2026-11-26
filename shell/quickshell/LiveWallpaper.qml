import QtQuick
import Quickshell
import Quickshell.Io
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

    // Where you are: from Wi-Fi (gosaab-location, BeaconDB) or the weather city; until then, a
    // guess from the time zone (right longitude, latitude unknown)
    FileView {
        id: locFile
        path: (Quickshell.env("HOME") || "") + "/.cache/gill-osaab/location.json"
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property var loc: { try { return JSON.parse(locFile.text()) } catch (e) { return null } }
    readonly property bool located: loc !== null && typeof loc.lat === "number"
    readonly property real lat: located ? loc.lat : 0
    readonly property real lon: located ? loc.lon : -now.getTimezoneOffset() / 4

    // The sun right now (a standard low-precision solar position: within a fraction of a degree)
    readonly property var sun: {
        const rad = Math.PI / 180
        const d = now.getTime() / 86400000 - 10957.5             // days since J2000
        const g = (357.529 + 0.98560028 * d) * rad
        const q = 280.459 + 0.98564736 * d
        const L = (q + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * rad
        const e = (23.439 - 0.00000036 * d) * rad
        const ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L))
        const dec = Math.asin(Math.sin(e) * Math.sin(L))
        const gmst = ((18.697374558 + 24.06570982441908 * d) % 24 + 24) % 24
        const H = (gmst * 15 + lon) * rad - ra                    // hour angle here
        const la = lat * rad
        const elev = Math.asin(Math.sin(la) * Math.sin(dec) + Math.cos(la) * Math.cos(dec) * Math.cos(H))
        const az = Math.atan2(-Math.sin(H), Math.tan(dec) * Math.cos(la) - Math.sin(la) * Math.cos(H))
        // subsolar longitude, for Earth's day and night
        let sub = (ra / rad - gmst * 15) % 360
        if (sub > 180) sub -= 360
        if (sub < -180) sub += 360
        return { elev: elev, az: az, dec: dec, sub: sub * rad }
    }

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
        property real sunLon: live.sun.sub
        property real sunLat: live.sun.dec
        property real viewLon: live.lon * Math.PI / 180
        property real viewLat: live.lat * Math.PI / 180
        // City, Lake, Shore, Dunes: the sun's height and which side of the view it's on (facing
        // the equator: east is on the left in the north, on the right in the south)
        property real sunElev: live.sun.elev
        property real sunX: Math.sin(live.sun.az) * (live.lat >= 0 ? -1 : 1)
        property real south: live.lat < 0 ? 1 : 0
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
