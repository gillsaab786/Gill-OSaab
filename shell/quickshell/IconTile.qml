import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// An app icon drawn in the chosen "Icon & widget style" (Settings > Appearance), like macOS Tahoe:
//   default - the app's own colourful icon
//   dark    - the icon on a dark glass squircle, a touch dimmer
//   clear   - frosted clear glass with a white, see-through version of the icon
//   tinted  - glass washed with the accent colour, the icon in that colour
// The glass styles need GPU effects; with software rendering they fall back to the default look.
Item {
    id: tile
    property string source: ""
    property string style: Theme.iconStyle
    readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software && style !== "default"

    Rectangle { // the glass squircle behind restyled icons
        id: plate
        visible: tile.effects
        anchors.fill: parent
        anchors.margins: parent.width * 0.04
        radius: width * 0.26
        color: tile.style === "dark" ? Qt.rgba(0.11, 0.11, 0.13, 0.92)
             : tile.style === "tinted" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.38)
             : Qt.rgba(1, 1, 1, 0.16)
        GlassRim { radius: plate.radius; strength: tile.style === "dark" ? 0.6 : 1.0 }
    }
    IconImage {
        id: img
        anchors.fill: parent
        anchors.margins: tile.effects ? parent.width * 0.17 : 0
        source: tile.source
        asynchronous: true
        visible: !tile.effects
    }
    MultiEffect {
        visible: tile.effects
        anchors.fill: img
        source: img
        saturation: tile.style === "clear" || tile.style === "tinted" ? -1 : 0.1
        brightness: tile.style === "clear" ? 0.55 : tile.style === "tinted" ? 0.35 : -0.05
        colorization: tile.style === "tinted" ? 0.85 : 0
        colorizationColor: Qt.lighter(Theme.accent, 1.35)
        opacity: tile.style === "clear" ? 0.92 : 1
    }
}
