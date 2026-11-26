import QtQuick

// Gill(OS)'s Trash: a frosted glass bin with a ribbed side and a bright rim; crumpled paper
// shows over the top when there is something in it. Drawn in code, so it is sharp at any size.
Canvas {
    id: bin
    property bool full: false
    property real lift: 0 // papers rise a little when something is dropped in
    antialiasing: true
    onFullChanged: requestPaint()
    onLiftChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        const c = getContext("2d")
        c.reset()
        const s = width / 100
        c.scale(s, s)
        const top = 22, bottom = 92, l0 = 18, r0 = 82, l1 = 25, r1 = 75
        const body = () => {
            c.beginPath()
            c.moveTo(l0, top); c.lineTo(r0, top)
            c.lineTo(r1, bottom - 6); c.quadraticCurveTo(r1 - 1, bottom, r1 - 7, bottom)
            c.lineTo(l1 + 7, bottom); c.quadraticCurveTo(l1 + 1, bottom, l1, bottom - 6)
            c.closePath()
        }
        // papers behind the front glass
        if (full) {
            const lift = bin.lift
            const paper = (pts, shade) => {
                c.beginPath(); c.moveTo(pts[0], pts[1] - lift)
                for (let i = 2; i < pts.length; i += 2) c.lineTo(pts[i], pts[i + 1] - lift)
                c.closePath(); c.fillStyle = shade; c.fill()
                c.strokeStyle = "rgba(120,130,150,0.55)"; c.lineWidth = 0.8; c.stroke()
            }
            paper([24, 30, 30, 12, 44, 9, 50, 18, 46, 32], "#f4f6fa")
            paper([44, 30, 52, 6, 66, 10, 72, 22, 64, 32], "#e6ebf3")
            paper([34, 32, 40, 16, 58, 15, 62, 30], "#ffffff")
            paper([60, 31, 70, 14, 80, 20, 76, 33], "#dfe5ee")
        }
        // frosted glass body
        body()
        const g = c.createLinearGradient(l0, 0, r0, 0)
        g.addColorStop(0, "rgba(225,232,245,0.78)")
        g.addColorStop(0.45, "rgba(250,252,255,0.55)")
        g.addColorStop(1, "rgba(190,200,220,0.80)")
        c.fillStyle = g; c.fill()
        // ribs: the bin's mesh catching light
        c.save(); body(); c.clip()
        for (let i = 0; i <= 10; i++) {
            const t = i / 10
            const xt = l0 + (r0 - l0) * t, xb = l1 + (r1 - l1) * t
            c.beginPath(); c.moveTo(xt, top); c.lineTo(xb, bottom)
            c.strokeStyle = i % 2 ? "rgba(255,255,255,0.65)" : "rgba(130,145,170,0.35)"
            c.lineWidth = i % 2 ? 1.6 : 1.0; c.stroke()
        }
        const shade = c.createLinearGradient(0, top, 0, bottom)
        shade.addColorStop(0, "rgba(255,255,255,0.25)"); shade.addColorStop(1, "rgba(60,70,90,0.22)")
        c.fillStyle = shade; c.fillRect(0, 0, 100, 100)
        c.restore()
        body(); c.strokeStyle = "rgba(255,255,255,0.9)"; c.lineWidth = 1.2; c.stroke()
        // rim: a bright glass lip
        c.beginPath(); c.ellipse(l0 - 3, top - 5, (r0 - l0) + 6, 10)
        const rim = c.createLinearGradient(0, top - 5, 0, top + 5)
        rim.addColorStop(0, "rgba(255,255,255,0.98)"); rim.addColorStop(1, "rgba(170,185,210,0.95)")
        c.fillStyle = rim; c.fill()
        c.beginPath(); c.ellipse(l0 + 1, top - 2.5, (r0 - l0) - 2, 5)
        c.fillStyle = full ? "rgba(90,100,120,0.35)" : "rgba(70,80,100,0.45)"; c.fill()
    }
}
