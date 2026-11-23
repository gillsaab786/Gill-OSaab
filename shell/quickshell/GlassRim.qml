import QtQuick

// Liquid Glass edge: a thin light-catching rim (bright at the top, faint at the sides,
// a soft glint at the bottom) and a gloss across the top. Lay it over a glass panel.
Canvas {
    id: rim
    property real radius: 18
    property real strength: 1.0
    anchors.fill: parent
    antialiasing: true
    onRadiusChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d")
        c.reset()
        const w = width, h = height, r = Math.min(radius, h / 2, w / 2)
        const path = (inset) => {
            const x = inset, y = inset, ww = w - inset * 2, hh = h - inset * 2, rr = Math.max(0, r - inset)
            c.beginPath()
            c.moveTo(x + rr, y); c.arcTo(x + ww, y, x + ww, y + hh, rr); c.arcTo(x + ww, y + hh, x, y + hh, rr)
            c.arcTo(x, y + hh, x, y, rr); c.arcTo(x, y, x + ww, y, rr); c.closePath()
        }
        // gloss: light falling on the top of the glass
        const gloss = c.createLinearGradient(0, 0, 0, Math.min(h, 60))
        gloss.addColorStop(0, Qt.rgba(1, 1, 1, 0.10 * strength))
        gloss.addColorStop(1, Qt.rgba(1, 1, 1, 0))
        path(1); c.fillStyle = gloss; c.fill()
        // rim
        const g = c.createLinearGradient(0, 0, 0, h)
        g.addColorStop(0, Qt.rgba(1, 1, 1, 0.55 * strength))
        g.addColorStop(0.18, Qt.rgba(1, 1, 1, 0.14 * strength))
        g.addColorStop(0.75, Qt.rgba(1, 1, 1, 0.06 * strength))
        g.addColorStop(1, Qt.rgba(1, 1, 1, 0.24 * strength))
        path(0.75); c.lineWidth = 1.5; c.strokeStyle = g; c.stroke()
    }
}
