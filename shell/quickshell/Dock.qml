import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Qt.labs.folderlistmodel

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
    readonly property var pinnedIds: ["org.gnome.Nautilus", "org.kde.dolphin", "brave-browser", "com.brave.Browser",
        "io.github.kolunmi.Bazaar", "waydroid.com.android.vending", "steam", "gosaab-emudeck", "gosaab-settings", "org.kde.konsole", "foot", "vlc", "org.videolan.VLC"]
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
            Repeater { // recently opened apps that aren't kept in the Dock
                model: dock.running
                DockItem {
                    entry: modelData.entry
                    appId: modelData.appId
                    dockWindow: dock
                    windows: dock.windowsFor(modelData.entry, modelData.appId)
                    pointerX: dock.mouseX
                }
            }
            Rectangle { // macOS-style divider before Downloads and Trash
                width: 1; height: Theme.dockIcon - 14
                anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.18)
            }
            DockItem { // Downloads: click for a fan of the newest files
                id: downloadsItem
                builtinIcon: "downloads"
                label: "Downloads"
                pointerX: dock.mouseX
                onActivated: ShellState.dockPopup = ShellState.dockPopup === "downloads" ? "" : "downloads"
                onMenuRequested: ShellState.run("xdg-open \"$HOME/Downloads\"")
            }
            DockItem { // Trash, always last: drop files on it; right-click to empty
                id: trashItem
                builtinIcon: "trash"
                label: "Trash"
                pointerX: dock.mouseX
                trashFull: trashFolder.count > 0
                onActivated: ShellState.run("gio open trash:/// || xdg-open trash:///")
                onMenuRequested: ShellState.dockPopup = ShellState.dockPopup === "trash" ? "" : "trash"
                onFilesDropped: urls => Quickshell.execDetached(["gio", "trash"].concat(urls.map(u => u.toString())))
            }
        }
    }

    readonly property string home: Quickshell.env("HOME") || "/tmp"
    FolderListModel {
        id: trashFolder
        folder: "file://" + dock.home + "/.local/share/Trash/files"
        showHidden: true
        showDotAndDotDot: false
    }
    FolderListModel {
        id: downloads
        folder: "file://" + dock.home + "/Downloads"
        sortField: FolderListModel.Time
        showDotAndDotDot: false
    }
    function fileIcon(name, isDir) {
        if (isDir) return Theme.icon("folder-download", "folder")
        const ext = (name.split(".").pop() || "").toLowerCase()
        const byExt = { pdf: "application-pdf", zip: "package-x-generic", gz: "package-x-generic", xz: "package-x-generic",
            "7z": "package-x-generic", exe: "application-x-ms-dos-executable", msi: "application-x-msi",
            apk: "application-vnd.android.package-archive", png: "image-x-generic", jpg: "image-x-generic",
            jpeg: "image-x-generic", webp: "image-x-generic", gif: "image-x-generic", mp4: "video-x-generic",
            mkv: "video-x-generic", webm: "video-x-generic", mp3: "audio-x-generic", flac: "audio-x-generic",
            iso: "application-x-cd-image", txt: "text-x-generic", doc: "x-office-document", docx: "x-office-document",
            xlsx: "x-office-spreadsheet", pptx: "x-office-presentation" }
        return Theme.icon(byExt[ext] || "text-x-generic", "text-x-generic")
    }

    // The Downloads fan and the Trash menu float above everything (so the click-away layer
    // doesn't cover them)
    PanelWindow {
        id: pop
        screen: dock.modelData
        visible: ShellState.dockPopup !== "" || card.opacity > 0.01
        anchors { bottom: true; left: true }
        readonly property Item anchorItem: ShellState.dockPopup === "trash" ? trashItem : downloadsItem
        readonly property real anchorX: {
            const sw = dock.modelData ? dock.modelData.width : 1920
            const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0)
            return (sw - dock.width) / 2 + p.x
        }
        margins { bottom: Theme.dockIcon + 26; left: Math.max(8, anchorX - implicitWidth / 2) }
        implicitWidth: ShellState.dockPopup === "trash" ? 200 : 340
        implicitHeight: 8 * 60 + 64
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gosaab-dockpopup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item {
            id: card
            anchors.fill: parent
            opacity: ShellState.dockPopup !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            MouseArea { anchors.fill: parent; onClicked: ShellState.dockPopup = "" } // empty space closes it

            // Trash menu
            Rectangle {
                visible: ShellState.dockPopup === "trash"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 104
                radius: 16
                color: Theme.panel
                GlassRim { radius: 16 }
                Column {
                    anchors { fill: parent; margins: 6 }
                    Repeater {
                        model: [{ t: "Open", c: "gio open trash:/// || xdg-open trash:///" },
                                { t: trashFolder.count > 0 ? "Empty Trash" : "Trash is empty", c: "gio trash --empty" }]
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 46; radius: 11
                            color: m.containsMouse && enabled ? Theme.accent : "transparent"
                            enabled: index === 0 || trashFolder.count > 0
                            Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                text: modelData.t; font { family: Theme.font; pixelSize: 14 }
                                color: m.containsMouse && parent.enabled ? "white" : parent.enabled ? Theme.text : Theme.subtext }
                            MouseArea { id: m; anchors.fill: parent; hoverEnabled: true
                                onClicked: { ShellState.run(modelData.c); ShellState.haptic("toggle"); ShellState.dockPopup = "" } }
                        }
                    }
                }
            }

            // Downloads fan: newest file nearest the Dock, rising in a gentle arc
            Item {
                visible: ShellState.dockPopup === "downloads"
                anchors.fill: parent
                Repeater {
                    id: fan
                    model: downloads
                    delegate: Item {
                        id: fanItem
                        required property int index
                        required property string fileName
                        required property url fileUrl
                        required property bool fileIsDir
                        visible: index < 8
                        readonly property real t: index / 7
                        width: card.width; height: 56
                        x: (ShellState.dockPopup === "downloads" ? 1 : 0) * (index * index * 1.6)
                        y: card.height - 60 - (ShellState.dockPopup === "downloads" ? index * 60 : 0)
                        rotation: -index * 1.2
                        transformOrigin: Item.Right
                        Behavior on y { SpringAnimation { spring: 4; damping: 0.38; epsilon: 0.3 } }
                        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors { right: icon.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: Math.min(name.implicitWidth + 22, card.width - 80); height: 28; radius: 14
                            color: fanMouse.containsMouse ? Theme.accent : Theme.panel
                            GlassRim { radius: 14; strength: 0.7 }
                            Text { id: name; anchors.centerIn: parent; width: parent.width - 20; elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                text: fanItem.fileName; color: fanMouse.containsMouse ? "white" : Theme.text
                                font { family: Theme.font; pixelSize: 12; weight: Font.Medium } }
                        }
                        Item {
                            id: icon
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 50; height: 50
                            scale: fanMouse.pressed ? 0.9 : fanMouse.containsMouse ? 1.08 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.fast } }
                            readonly property string src: dock.fileIcon(fanItem.fileName, fanItem.fileIsDir)
                            IconImage { anchors.fill: parent; source: parent.src; visible: parent.src !== "" }
                            Rectangle { // no icon theme entry: a plain paper page with the file's extension
                                visible: parent.src === ""
                                anchors { fill: parent; leftMargin: 7; rightMargin: 7; topMargin: 2; bottomMargin: 2 }
                                radius: 6; color: "white"
                                GlassRim { radius: 6; strength: 0.6 }
                                Icon { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
                                    width: 20; height: 20; name: fanItem.fileIsDir ? "folder" : "file"; color: Theme.accent }
                                Text { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
                                    text: fanItem.fileIsDir ? "" : (fanItem.fileName.split(".").pop() || "").toUpperCase().substring(0, 4)
                                    color: "#3a3a3c"; font { family: Theme.font; pixelSize: 9; weight: Font.Bold } }
                            }
                        }
                        MouseArea { id: fanMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: { Quickshell.execDetached(["xdg-open", fanItem.fileUrl.toString()]); ShellState.dockPopup = "" } }
                    }
                }
                Rectangle { // "Open in Files" at the top of the fan
                    anchors { right: parent.right; top: parent.top }
                    width: 140; height: 30; radius: 15
                    color: openAll.containsMouse ? Theme.accent : Theme.panel
                    GlassRim { radius: 15; strength: 0.7 }
                    Text { anchors.centerIn: parent; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                        text: fan.count > 0 ? "Open in Files" : "No downloads yet"; color: openAll.containsMouse ? "white" : Theme.text }
                    MouseArea { id: openAll; anchors.fill: parent; hoverEnabled: true
                        onClicked: { ShellState.run("xdg-open \"$HOME/Downloads\""); ShellState.dockPopup = "" } }
                }
            }
        }
    }
}
