pragma Singleton
import QtQuick
import Quickshell

// Gill-OSaab look: dark glass, Apple-style system colours, Inter type.
Singleton {
    property bool dark: true
    // 0 = light, 1 = dark; animates so switching Dark Mode cross-fades every colour
    property real darkness: dark ? 1 : 0
    Behavior on darkness { NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
    function mix(light, darkCol) {
        const a = Qt.color(light), b = Qt.color(darkCol), t = darkness
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    readonly property string font: "Inter"
    readonly property color accent: "#0a84ff"
    readonly property color green: "#30d158"
    readonly property color orange: "#ff9f0a"
    readonly property color red: "#ff453a"

    // Liquid Glass: clear, lightly tinted glass; the blur behind does the work
    readonly property color bar: mix(Qt.rgba(1, 1, 1, 0.18), Qt.rgba(0.06, 0.06, 0.08, 0.12))
    readonly property color panel: mix(Qt.rgba(1, 1, 1, 0.45), Qt.rgba(0.10, 0.10, 0.13, 0.42))
    readonly property color panelBorder: "transparent" // the GlassRim draws the edge
    readonly property color tile: mix(Qt.rgba(1, 1, 1, 0.35), Qt.rgba(1, 1, 1, 0.10))
    readonly property color tileHover: mix(Qt.rgba(1, 1, 1, 0.55), Qt.rgba(1, 1, 1, 0.18))
    readonly property color text: mix("#1c1c1e", "#f2f2f7")
    readonly property color subtext: mix(Qt.rgba(0.1, 0.1, 0.12, 0.60), Qt.rgba(0.92, 0.92, 0.96, 0.60))
    readonly property color dock: mix(Qt.rgba(1, 1, 1, 0.35), Qt.rgba(0.14, 0.14, 0.18, 0.30))

    readonly property string wallpaper: Quickshell.env("GOSAAB_WALLPAPER")
        || "/usr/share/wallpapers/GillOSaab/contents/images_dark/3840x2160.png"

    readonly property int radius: 22
    readonly property int barHeight: 38
    readonly property int dockIcon: 60
    readonly property int dockMagnified: 86

    // An icon path that exists, trying each name in turn ("" if none do)
    function icon() {
        for (let i = 0; i < arguments.length; i++) {
            const n = arguments[i]
            if (!n) continue
            const name = n.startsWith("image://icon/") ? n.substring(13) : n
            if (name.startsWith("/") || name.startsWith("file:") || name.startsWith("image:")) return name
            const p = Quickshell.iconPath(name, true)
            if (p !== "") return p
        }
        return ""
    }

    // Helper entries apps ship that people never launch themselves
    readonly property var hiddenApps: ["footclient", "foot-server", "gosaab-open", "org.freedesktop.IBus.Setup",
        "nm-connection-editor", "lxqt-policykit-agent", "xdg-desktop-portal-gtk"]
    function listed(e) {
        // Wine's own helper apps (Notepad, Regedit, WineMine...) stay out; Wine Configuration stays in
        if (/^wine-(notepad|regedit|winemine|wordpad|winhelp|oleview|uninstaller|wineboot|taskmgr|control|cmd|iexplore|explorer|winefile|mime-msi|mime-.*)$/.test(e.id)) return false
        return !e.noDisplay && hiddenApps.indexOf(e.id) < 0
    }

    // Which system an app comes from: Android (Waydroid), Windows (Wine) or Linux
    function platformOf(e) {
        if (!e) return "Linux"
        if (e.id.startsWith("waydroid.") || (e.execString || "").includes("waydroid app launch")) return "Android"
        if ((e.execString || "").match(/\bwine(64)?\b|--wine-run|\.exe\b/i) || (e.categories || []).indexOf("Wine") >= 0) return "Windows"
        return "Linux"
    }
    function baseName(name) { return (name || "").trim().toLowerCase() }
    // names that exist for more than one system, e.g. YouTube for Android and for Windows
    readonly property var sharedNames: {
        const seen = {}
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue
            const key = baseName(e.name)
            const p = platformOf(e)
            seen[key] = seen[key] || {}
            seen[key][p] = true
        }
        const shared = {}
        for (const k in seen) if (Object.keys(seen[k]).length > 1) shared[k] = true
        return shared
    }
    // "YouTube" normally; "Android-YouTube" / "Windows-YouTube" / "Linux-YouTube" only when you have
    // the same app from two systems
    function displayName(e) {
        if (!e) return ""
        return sharedNames[baseName(e.name)] ? platformOf(e) + "-" + e.name : e.name
    }

    // Motion: quick, springy, never sluggish
    readonly property int fast: 140
    readonly property int normal: 240
}
