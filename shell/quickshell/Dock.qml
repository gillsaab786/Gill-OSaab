import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// The Dock: pinned + running apps, magnifies under the pointer, bounces on launch.
PanelWindow {
    id: dock
    property var modelData
    screen: modelData
    anchors.bottom: true
    implicitWidth: Math.max(400, shelf.width + 160)
    implicitHeight: Theme.dockMagnified + 36
    exclusiveZone: Theme.dockIcon + 22
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "gosaab-dock:r28"
    WlrLayershell.layer: WlrLayer.Top
    mask: Region { item: hitArea }

    // Pinned apps (shown if installed); everything running is added after a divider.
    readonly property var pinnedIds: ["org.gnome.Nautilus", "org.kde.dolphin", "firefox", "org.mozilla.firefox",
        "steam", "gosaab-settings", "org.kde.konsole", "foot", "vlc", "org.videolan.VLC"]
    readonly property var pinned: {
        const apps = DesktopEntries.applications.values // re-evaluates once app scanning finishes
        return pinnedIds.map(id => apps.find(e => e.id === id)).filter(e => e)
    }
    readonly property var windows: ToplevelManager.toplevels.values
    readonly property var running: {
        const seen = {}
        const out = []
        for (const w of windows) {
            const e = DesktopEntries.heuristicLookup(w.appId)
            const key = e ? e.id : w.appId
            if (seen[key] || pinned.some(p => p.id === key)) continue
            seen[key] = true
            out.push({ entry: e, appId: w.appId })
        }
        return out
    }
    function windowsFor(entry, appId) {
        return windows.filter(w => {
            const e = DesktopEntries.heuristicLookup(w.appId)
            return entry ? (e && e.id === entry.id) : w.appId === appId
        })
    }

    property real mouseX: -1000

    Item { // where the Dock takes clicks: the shelf plus room for magnified icons
        id: hitArea
        x: shelf.x; width: shelf.width
        y: shelf.y - (Theme.dockMagnified - Theme.dockIcon); height: shelf.height + (Theme.dockMagnified - Theme.dockIcon)
    }

    Rectangle {
        id: shelf
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
        width: items.width + 16
        height: Theme.dockIcon + 14
        radius: 28
        color: Theme.dock
        GlassRim { radius: 28 }
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        MouseArea {
            id: hover
            anchors.fill: parent
            anchors.topMargin: -(Theme.dockMagnified - Theme.dockIcon)
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: m => dock.mouseX = mapToItem(items, m.x, m.y).x
            onExited: dock.mouseX = -1000
        }

        Row {
            id: items
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 7 }
            spacing: 6
            DockItem { // Launchpad: every app, iPad style
                builtinIcon: "launchpad"
                label: "Launchpad"
                pointerX: dock.mouseX
                onActivated: ShellState.toggle("launchpad")
            }
            Repeater {
                model: dock.pinned
                DockItem {
                    entry: modelData
                    dockWindow: dock
                    windows: dock.windowsFor(modelData, "")
                    pointerX: dock.mouseX
                }
            }
            Rectangle {
                width: 1; height: Theme.dockIcon - 10
                anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                color: Qt.rgba(1, 1, 1, 0.25)
            }
            Repeater {
                model: dock.running
                DockItem {
                    entry: modelData.entry
                    appId: modelData.appId
                    dockWindow: dock
                    windows: dock.windowsFor(modelData.entry, modelData.appId)
                    pointerX: dock.mouseX
                }
            }
            DockItem { // Trash, always last
                builtinIcon: "trash"
                label: "Trash"
                pointerX: dock.mouseX
                onActivated: ShellState.run("gio open trash:/// || xdg-open trash:///")
            }
        }
    }
}
