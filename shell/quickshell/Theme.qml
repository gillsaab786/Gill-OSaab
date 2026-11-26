pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Gill(OS) look: dark glass, Apple-style system colours, Inter type.
// Appearance choices live in ~/.config/gill-osaab/appearance.json, shared with Settings:
//   mode auto|light|dark, accent "#rrggbb", iconStyle default|dark|clear|tinted, glass clear|tinted,
//   menuBar transparent|glass, wallpaper tide|tide-light|tide-dark|classic|/path, widgets {...}, city
Singleton {
    id: theme
    property var cfg: ({})
    readonly property string configPath: (Quickshell.env("HOME") || "/tmp") + "/.config/gill-osaab/appearance.json"
    FileView {
        id: appearanceFile
        path: theme.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { theme.cfg = JSON.parse(text()) || {} } catch (e) { theme.cfg = {} } }
        onLoadFailed: theme.cfg = {}
    }
    function setting(key, fallback) { return cfg[key] !== undefined ? cfg[key] : fallback }
    // Change one appearance setting and save it (Settings sees it at once, and so does the shell)
    function set(key, value) {
        const c = JSON.parse(JSON.stringify(cfg))
        c[key] = value
        cfg = c
        Quickshell.execDetached(["mkdir", "-p", configPath.substring(0, configPath.lastIndexOf("/"))])
        appearanceFile.setText(JSON.stringify(c, null, 2) + "\n")
    }
    function widgetOn(name, fallback) {
        const w = cfg.widgets || {}
        return w[name] !== undefined ? !!w[name] : fallback
    }

    // Auto: dark from 7 pm to 7 am
    property int hour: new Date().getHours()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: theme.hour = new Date().getHours() }
    readonly property string mode: setting("mode", "dark")
    property bool dark: mode === "light" ? false : mode === "auto" ? (hour >= 19 || hour < 7) : true
    // apps follow along (GTK/libadwaita and Qt apps that read the portal setting)
    onDarkChanged: Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme",
                                            dark ? "prefer-dark" : "default"])
    // 0 = light, 1 = dark; animates so switching Dark Mode cross-fades every colour
    property real darkness: dark ? 1 : 0
    Behavior on darkness { NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
    function mix(light, darkCol) {
        const a = Qt.color(light), b = Qt.color(darkCol), t = darkness
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    readonly property string font: "Inter"
    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(setting("accent", "")) ? setting("accent", "") : "#0a84ff"
    // text and symbols on the accent colour: dark on light accents (Mint, Yellow), else white
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.67 ? "#0b1a12" : "white"
    readonly property string iconStyle: setting("iconStyle", "default") // default | dark | clear | tinted
    readonly property bool tintedGlass: setting("glass", "clear") === "tinted"
    readonly property bool clearMenuBar: setting("menuBar", "transparent") === "transparent"
    readonly property color green: "#30d158"
    readonly property color orange: "#ff9f0a"
    readonly property color red: "#ff453a"

    // Liquid Glass: clear, lightly tinted glass; the blur behind does the work.
    // "Tinted" glass is frostier, for people who find clear glass hard to read.
    readonly property real glassBoost: tintedGlass ? 0.25 : 0
    // AMOLED black (Settings > Appearance, with Dark): black glass. Panels are near-opaque black so
    // those pixels stay off; edges keep their bright Liquid Glass rim, and the wallpaper is Tide Black.
    readonly property bool amoled: dark && setting("amoled", false) === true
    readonly property color bar: amoled ? (clearMenuBar ? "transparent" : "black") : clearMenuBar ? "transparent"
        : mix(Qt.rgba(1, 1, 1, 0.30 + glassBoost), Qt.rgba(0.06, 0.06, 0.08, 0.30 + glassBoost))
    readonly property color panel: amoled ? Qt.rgba(0, 0, 0, 0.86 + glassBoost * 0.4) : mix(Qt.rgba(1, 1, 1, 0.45 + glassBoost), Qt.rgba(0.10, 0.10, 0.13, 0.42 + glassBoost))
    readonly property color panelBorder: "transparent" // the GlassRim draws the edge
    readonly property color tile: amoled ? Qt.rgba(1, 1, 1, 0.08) : mix(Qt.rgba(1, 1, 1, 0.35), Qt.rgba(1, 1, 1, 0.10))
    readonly property color tileHover: amoled ? Qt.rgba(1, 1, 1, 0.15) : mix(Qt.rgba(1, 1, 1, 0.55), Qt.rgba(1, 1, 1, 0.18))
    readonly property color text: mix("#1c1c1e", "#f2f2f7")
    readonly property color subtext: mix(Qt.rgba(0.1, 0.1, 0.12, 0.60), Qt.rgba(0.92, 0.92, 0.96, 0.60))
    readonly property color dock: amoled ? Qt.rgba(0, 0, 0, 0.70 + glassBoost * 0.4) : mix(Qt.rgba(1, 1, 1, 0.22 + glassBoost), Qt.rgba(0.14, 0.14, 0.18, 0.18 + glassBoost))

    // Wallpaper: "tide" follows Light/Dark (cross-fading), the others are fixed pictures
    readonly property string wallpaperDir: {
        const env = Quickshell.env("GOSAAB_WALLPAPER") || ""
        return env !== "" ? env.replace(/\/contents\/.*$/, "") : "/usr/share/wallpapers/GillOSaab"
    }
    readonly property string wallpaperChoice: setting("wallpaper", "tide")
    // Live wallpapers (shaders/*.frag): "live:earth", "live:moon", "live:dunes", "live:flow".
    // The lock screen and previews use a still picture of each.
    readonly property string liveWallpaper: /^live:(earth|moon|dunes|flow|pluto|bubbles|shapes|city|lake|shore)$/.test(wallpaperChoice) ? wallpaperChoice.substring(5) : ""
    readonly property bool liveMotion: setting("liveMotion", true) !== false
    function liveStill(name, isDark) {
        const dir = wallpaperDir + "-Live/contents/"
        const lightToo = name === "flow" || name === "bubbles" || name === "shapes"
        return dir + (lightToo && !isDark ? name + "-light" : name) + ".jpg"
    }
    function wallpaperFor(isDark) {
        const w = wallpaperChoice
        if (liveWallpaper !== "") return liveStill(liveWallpaper, isDark)
        if (w.startsWith("/")) return w
        const dir = w.startsWith("classic") ? wallpaperDir + "-Classic" : wallpaperDir
        const d = w.endsWith("-light") ? false : w.endsWith("-dark") ? true : isDark
        // AMOLED: Tide's dark picture becomes Tide Black (true black with glowing edges)
        const black = w.endsWith("-black") || (d && amoled && !w.startsWith("classic"))
        return dir + "/contents/" + (black ? "images_black" : d ? "images_dark" : "images") + "/3840x2160.png"
    }
    readonly property bool dynamicWallpaper: !wallpaperChoice.startsWith("/") && liveWallpaper === "" && !/-(light|dark|black)$/.test(wallpaperChoice)
    readonly property string wallpaper: wallpaperFor(dark)

    readonly property int radius: 22
    readonly property int barHeight: 38
    readonly property int dockIcon: 60
    readonly property int dockMagnified: Math.round(dockIcon * dockZoom)

    // An icon path that exists, trying each name in turn ("" if none do)
    function icon() {
        for (let i = 0; i < arguments.length; i++) {
            const n = arguments[i]
            if (!n) continue
            const name = n.startsWith("image://icon/") ? n.substring(13) : n
            if (name.startsWith("/")) return "file://" + name // an app's own picture file
            if (name.startsWith("file:") || name.startsWith("image:")) return name
            const p = Quickshell.iconPath(name, true)
            if (p !== "") return p
        }
        return ""
    }

    // Helper entries apps ship that people never launch themselves
    readonly property var hiddenApps: ["footclient", "foot-server", "gosaab-open", "org.freedesktop.IBus.Setup",
        "nm-connection-editor", "lxqt-policykit-agent", "xdg-desktop-portal-gtk"]
    // apps a system helper, never shown (Wine's Notepad, Regedit...; Wine Configuration stays in)
    function helperApp(e) {
        return e.noDisplay || hiddenApps.indexOf(e.id) >= 0
            || /^wine-(notepad|regedit|winemine|wordpad|winhelp|oleview|uninstaller|wineboot|taskmgr|control|cmd|iexplore|explorer|winefile|mime-msi|mime-.*)$/.test(e.id)
    }
    // apps you hid yourself (Launchpad: right-click or hold > Hide); kept in appearance.json "hiddenApps"
    readonly property var userHidden: Array.isArray(cfg.hiddenApps) ? cfg.hiddenApps : []
    function isHidden(id) { return userHidden.indexOf(id) >= 0 }
    function setHidden(id, hide) {
        const list = userHidden.filter(x => x !== id)
        if (hide) list.push(id)
        set("hiddenApps", list)
    }
    function listed(e) { return !helperApp(e) && !isHidden(e.id) }

    // Apps kept in the Dock (right-click > Keep in Dock / Remove from Dock)
    readonly property var defaultDock: ["org.gnome.Nautilus", "org.kde.dolphin", "brave-browser", "com.brave.Browser",
        "io.github.kolunmi.Bazaar", "waydroid.com.android.vending", "steam", "gosaab-emudeck", "gosaab-settings",
        "org.kde.konsole", "foot", "vlc", "org.videolan.VLC"]
    readonly property var dockApps: Array.isArray(cfg.dockApps) ? cfg.dockApps : defaultDock
    function inDock(id) { return dockApps.indexOf(id) >= 0 }
    function setInDock(id, keep) {
        const list = dockApps.filter(x => x !== id)
        if (keep) list.push(id)
        set("dockApps", list)
    }

    // Dock magnification (Settings > Appearance): how big icons grow under the pointer
    readonly property real dockZoom: ({ off: 1.0, small: 1.35, medium: 1.7, large: 2.0 })[setting("dockMagnification", "medium")] || 1.7

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
