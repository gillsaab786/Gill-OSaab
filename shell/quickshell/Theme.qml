pragma Singleton
import QtQuick
import Quickshell

// Gill-OSaab look: dark glass, Apple-style system colours, Inter type.
Singleton {
    property bool dark: true

    readonly property string font: "Inter"
    readonly property color accent: "#0a84ff"
    readonly property color green: "#30d158"
    readonly property color orange: "#ff9f0a"
    readonly property color red: "#ff453a"

    readonly property color bar: dark ? Qt.rgba(0.07, 0.07, 0.09, 0.42) : Qt.rgba(0.98, 0.98, 1.0, 0.55)
    readonly property color panel: dark ? Qt.rgba(0.11, 0.11, 0.13, 0.72) : Qt.rgba(0.96, 0.96, 0.98, 0.78)
    readonly property color panelBorder: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color tile: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color tileHover: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color text: dark ? "#f2f2f7" : "#1c1c1e"
    readonly property color subtext: dark ? Qt.rgba(0.92, 0.92, 0.96, 0.60) : Qt.rgba(0.1, 0.1, 0.12, 0.60)
    readonly property color dock: dark ? Qt.rgba(0.16, 0.16, 0.19, 0.48) : Qt.rgba(1, 1, 1, 0.45)

    readonly property int radius: 14
    readonly property int barHeight: 30
    readonly property int dockIcon: 52
    readonly property int dockMagnified: 78

    // Motion: quick, springy, never sluggish
    readonly property int fast: 140
    readonly property int normal: 240
}
