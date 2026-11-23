import QtQuick

// Liquid Glass progress ring with the percentage inside (downloads, installs, updates).
Item {
    id: ring
    property real value: 0          // 0..100
    property real thickness: Math.max(3, width * 0.075)
    property bool showText: true
    implicitWidth: 48
    implicitHeight: 48

    property real shown: value
    Behavior on shown { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    onShownChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            c.reset()
            const r = Math.min(width, height) / 2 - ring.thickness / 2 - 1
            const x = width / 2, y = height / 2
            // glass disc + rim
            c.beginPath(); c.arc(x, y, r + ring.thickness / 2, 0, Math.PI * 2)
            c.fillStyle = Qt.rgba(1, 1, 1, 0.05); c.fill()
            c.lineWidth = 1; c.strokeStyle = Qt.rgba(1, 1, 1, 0.18); c.stroke()
            // track
            c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2)
            c.lineWidth = ring.thickness; c.strokeStyle = "#2c2c2e"; c.stroke()
            // progress arc, mint gradient, round ends
            const p = Math.max(0, Math.min(100, ring.shown)) / 100
            if (p > 0) {
                const g = c.createLinearGradient(x, y - r, x, y + r)
                g.addColorStop(0, "#a8f0d0"); g.addColorStop(1, "#5fe0a8")
                c.beginPath(); c.arc(x, y, r, -Math.PI / 2, -Math.PI / 2 + p * Math.PI * 2)
                c.lineCap = "round"; c.lineWidth = ring.thickness; c.strokeStyle = g; c.stroke()
            }
        }
    }
    Row {
        visible: ring.showText
        anchors.centerIn: parent
        Text { text: Math.round(ring.shown); color: "white"; font { family: Theme.font; pixelSize: ring.width * 0.30; weight: Font.Bold } }
        Text { text: "%"; color: "#5fe0a8"; anchors.baseline: parent.children[0].baseline
            font { family: Theme.font; pixelSize: ring.width * 0.15; weight: Font.Bold } }
    }
}
