import QtQuick

// Crisp vector icons drawn in code (no icon font needed). 24x24 design grid.
Canvas {
    id: icon
    property string name: "dot"
    property color color: Theme.text
    property real level: 1.0 // battery / volume / wifi strength 0..1
    implicitWidth: 16
    implicitHeight: 16
    antialiasing: true
    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onLevelChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const c = getContext("2d")
        c.reset()
        const s = width / 24
        c.scale(s, s)
        c.strokeStyle = icon.color
        c.fillStyle = icon.color
        c.lineWidth = 2
        c.lineCap = "round"
        c.lineJoin = "round"
        const arc = (x, y, r, a0, a1) => { c.beginPath(); c.arc(x, y, r, a0, a1); c.stroke() }
        const line = (pts) => { c.beginPath(); c.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) c.lineTo(pts[i], pts[i + 1]); c.stroke() }
        const dot = (x, y, r) => { c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill() }
        const rrect = (x, y, w, h, r) => { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
        const up = -Math.PI / 2
        switch (name) {
        case "logo": // Gill-OSaab mark: a "G" ring with a spark
            c.lineWidth = 2.6
            arc(12, 12, 8.5, -0.25 * Math.PI, 1.6 * Math.PI)
            line([12.5, 12, 20, 12])
            dot(19, 5, 1.6)
            break
        case "wifi":
            for (let i = 0; i < 3; i++) {
                c.globalAlpha = (i / 3) < level ? 1 : 0.3
                arc(12, 19, 4 + i * 4.5, up - 0.75, up + 0.75)
            }
            c.globalAlpha = 1
            dot(12, 19, 1.8)
            break
        case "bluetooth":
            line([7, 7.5, 17, 16.5, 12, 21, 12, 3, 17, 7.5, 7, 16.5])
            break
        case "volume":
            c.beginPath(); c.moveTo(3, 9); c.lineTo(7, 9); c.lineTo(12, 4.5); c.lineTo(12, 19.5); c.lineTo(7, 15); c.lineTo(3, 15); c.closePath(); c.fill()
            if (level > 0.01) arc(13, 12, 4, -0.9, 0.9)
            if (level > 0.5) arc(13, 12, 8, -0.9, 0.9)
            if (level <= 0.01) line([16, 9, 22, 15, 22, 9, 16, 15])
            break
        case "battery":
            c.lineWidth = 1.5
            rrect(2, 7, 18, 10, 3); c.stroke()
            rrect(21, 10, 1.6, 4, 0.8); c.fill()
            rrect(4, 9, Math.max(1, 14 * level), 6, 1.5); c.fill()
            break
        case "search":
            arc(10.5, 10.5, 6.5, 0, Math.PI * 2)
            line([15.5, 15.5, 21, 21])
            break
        case "controls": // two toggles, like macOS Control Centre
            c.lineWidth = 1.6
            rrect(2.5, 4, 19, 7, 3.5); c.stroke(); dot(18, 7.5, 2.2)
            rrect(2.5, 13, 19, 7, 3.5); c.stroke(); dot(6, 16.5, 2.2)
            break
        case "moon":
            c.beginPath(); c.arc(12, 12, 8.5, 0, Math.PI * 2); c.fill()
            c.globalCompositeOperation = "destination-out"
            c.beginPath(); c.arc(17, 8, 7.5, 0, Math.PI * 2); c.fill()
            c.globalCompositeOperation = "source-over"
            break
        case "sun":
            dot(12, 12, 4.2)
            for (let i = 0; i < 8; i++) {
                const a = i * Math.PI / 4
                line([12 + Math.cos(a) * 7, 12 + Math.sin(a) * 7, 12 + Math.cos(a) * 9.5, 12 + Math.sin(a) * 9.5])
            }
            break
        case "darkmode":
            arc(12, 12, 8.5, 0, Math.PI * 2)
            c.beginPath(); c.arc(12, 12, 8.5, -Math.PI / 2, Math.PI / 2); c.closePath(); c.fill()
            break
        case "gamepad":
            c.lineWidth = 1.8
            rrect(2.5, 7, 19, 11, 5.5); c.stroke()
            line([6.5, 12.5, 10.5, 12.5]); line([8.5, 10.5, 8.5, 14.5])
            dot(15.5, 11.2, 1.3); dot(18, 13.8, 1.3)
            break
        case "shield": // VPN
            c.beginPath(); c.moveTo(12, 2.5); c.lineTo(20, 5.5); c.lineTo(20, 11); c.quadraticCurveTo(20, 18, 12, 21.5); c.quadraticCurveTo(4, 18, 4, 11); c.lineTo(4, 5.5); c.closePath(); c.stroke()
            break
        case "bell":
            c.beginPath(); c.moveTo(5, 17); c.lineTo(19, 17); c.lineTo(17.5, 14.5); c.lineTo(17.5, 10); c.quadraticCurveTo(17.5, 4, 12, 4); c.quadraticCurveTo(6.5, 4, 6.5, 10); c.lineTo(6.5, 14.5); c.closePath(); c.stroke()
            line([10, 20, 14, 20])
            break
        case "screenoff":
            c.lineWidth = 1.8
            rrect(2.5, 4, 19, 13, 2); c.stroke()
            line([8, 20.5, 16, 20.5])
            line([9, 8, 15, 13]); line([15, 8, 9, 13])
            break
        case "power":
            arc(12, 13, 7.5, up + 0.6, up + 2 * Math.PI - 0.6)
            line([12, 3, 12, 11])
            break
        case "glasses": // XREAL
            c.lineWidth = 1.7
            rrect(2, 9, 8.5, 6.5, 3); c.stroke()
            rrect(13.5, 9, 8.5, 6.5, 3); c.stroke()
            line([10.5, 11, 13.5, 11])
            break
        case "airplane":
            c.beginPath(); c.moveTo(12, 2); c.lineTo(13.5, 9); c.lineTo(21, 13); c.lineTo(21, 15); c.lineTo(13.5, 12.5); c.lineTo(13, 18); c.lineTo(15.5, 20); c.lineTo(15.5, 21.5); c.lineTo(12, 20.5); c.lineTo(8.5, 21.5); c.lineTo(8.5, 20); c.lineTo(11, 18); c.lineTo(10.5, 12.5); c.lineTo(3, 15); c.lineTo(3, 13); c.lineTo(10.5, 9); c.closePath(); c.fill()
            break
        case "close":
            line([6, 6, 18, 18]); line([18, 6, 6, 18])
            break
        default:
            dot(12, 12, 4)
        }
    }
}
