import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Spotlight (Super+Space), macOS Tahoe style: type to find apps, files and actions, do quick
// maths; or pick a view with the buttons: Apps, Files, Actions, Clipboard history.
PanelWindow {
    id: spot
    property var modelData
    visible: ShellState.spotlight || box.opacity > 0.01
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gosaab-spotlight:r29"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ShellState.spotlight ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: ShellState.spotlight ? fullArea : box }

    property int selected: 0
    property string view: "" // "" = everything, or apps / files / actions / clipboard
    readonly property string query: input.text.trim().toLowerCase()
    readonly property string libexec: Quickshell.env("GOSAAB_LIBEXEC") || "/usr/libexec/gill-osaab"

    function matches(text, q) {
        const n = (text || "").toLowerCase()
        if (n.startsWith(q)) return 0
        if (n.split(/[ \-_.]/).some(w => w.startsWith(q))) return 1
        if (n.includes(q)) return 2
        return 9
    }

    readonly property var apps: {
        const all = DesktopEntries.applications.values.filter(e => Theme.listed(e))
        if (query === "")
            return view === "apps" ? all.slice().sort((a, b) => Theme.displayName(a).localeCompare(Theme.displayName(b))) : []
        const score = e => {
            const s = matches(Theme.displayName(e), query)
            if (s < 9) return s
            if ((e.genericName || "").toLowerCase().includes(query) || e.keywords.some(k => k.toLowerCase().includes(query))) return 3
            return 9
        }
        return all.map(e => ({ e: e, s: score(e) })).filter(x => x.s < 9)
                  .sort((a, b) => a.s - b.s || a.e.name.localeCompare(b.e.name)).map(x => x.e)
    }

    // Quick actions: things you'd otherwise dig through menus for
    readonly property var actionList: [
        { t: Theme.dark ? "Turn Dark Mode Off" : "Turn Dark Mode On", k: "appearance light dark theme", g: "darkmode",
          f: () => Theme.set("mode", Theme.dark ? "light" : "dark") },
        { t: "Lock Screen", k: "lock away", g: "power", f: () => ShellState.run("qs -c gill-osaab ipc call lock lock") },
        { t: "Take Screenshot", k: "screen capture picture", g: "screenoff",
          f: () => ShellState.run("sleep 0.4; mkdir -p \"$HOME/Pictures/Screenshots\"; grim \"$HOME/Pictures/Screenshots/Screenshot $(date '+%Y-%m-%d at %H.%M.%S').png\"") },
        { t: "Switch to Game Mode", k: "steam gaming handheld", g: "gamepad", f: () => ShellState.run("gosaab-game-mode || steamos-session-select gamescope") },
        { t: "Open Settings", k: "preferences control", g: "controls", f: () => ShellState.run("gosaab-settings") },
        { t: "Check for Updates", k: "update upgrade drivers", g: "downloads", f: () => ShellState.run("gosaab-settings updates") },
        { t: "Show On-Screen Keyboard", k: "touch typing", g: "keyboard", f: () => ShellState.toggleKeyboard() },
        { t: "Empty Trash", k: "delete bin rubbish", g: "trash", f: () => ShellState.run("gio trash --empty") },
        { t: "Open Downloads", k: "files folder", g: "downloads", f: () => ShellState.run("xdg-open \"$HOME/Downloads\"") },
        { t: "Copy Clipboard History", k: "paste copied text", g: "clipboard", f: () => { spot.view = "clipboard"; input.text = "" } },
        { t: "Restart", k: "reboot", g: "power", f: () => ShellState.run("systemctl reboot") },
        { t: "Shut Down", k: "power off", g: "power", f: () => ShellState.run("systemctl poweroff") }
    ]
    readonly property var actions: {
        if (view !== "" && view !== "actions") return []
        if (query === "") return view === "actions" ? actionList : []
        return actionList.filter(a => matches(a.t, query) < 9 || a.k.split(" ").some(w => w.startsWith(query)))
    }

    // Files in your home folder (names only; hidden folders skipped)
    property var files: []
    Process {
        id: fileSearch
        stdout: StdioCollector { onStreamFinished: spot.files = text.split("\n").filter(l => l !== "").slice(0, 12) }
    }
    Timer {
        id: fileTimer
        interval: 220
        onTriggered: {
            if (spot.query.length < 2 || (spot.view !== "" && spot.view !== "files")) { spot.files = []; return }
            fileSearch.running = false
            fileSearch.command = ["sh", "-c", "find \"$HOME\" -maxdepth 5 -not -path '*/.*' -iname \"*$1*\" 2>/dev/null | head -12",
                                  "sh", spot.query.replace(/[\[\]*?\\]/g, "")]
            fileSearch.running = true
        }
    }

    // Clipboard history (gosaab-clipboard keeps the last 25 text copies, in memory only)
    property var clips: []
    Process {
        id: clipList
        command: [spot.libexec + "/gosaab-clipboard", "list"]
        stdout: StdioCollector { onStreamFinished: { try { spot.clips = JSON.parse(text) } catch (e) { spot.clips = [] } } }
    }
    readonly property var clipResults: view !== "clipboard" ? [] :
        clips.map((c, i) => ({ c: c, i: i })).filter(x => query === "" || x.c.toLowerCase().includes(query))

    readonly property string maths: {
        if (!/^[0-9+\-*/().% ^]+$/.test(query) || !/[0-9]/.test(query)) return ""
        try {
            const v = Function("return (" + query.replace(/\^/g, "**") + ")")()
            return (typeof v === "number" && isFinite(v)) ? String(Math.round(v * 1e10) / 1e10) : ""
        } catch (e) { return "" }
    }

    // Every row in one list: apps, then actions, files and clipboard items
    readonly property var rows: {
        const out = []
        const appCap = view === "apps" ? 60 : view === "" ? 6 : 0
        for (const e of apps.slice(0, appCap))
            out.push({ kind: "app", title: Theme.displayName(e), sub: e.genericName || e.comment || "", icon: Theme.icon(e.icon, "application-x-executable"), e: e })
        for (const a of actions.slice(0, view === "" ? 3 : 20))
            out.push({ kind: "action", title: a.t, sub: "Action", glyph: a.g, a: a })
        for (const f of files.slice(0, view === "" ? 4 : 12)) {
            const name = f.substring(f.lastIndexOf("/") + 1)
            out.push({ kind: "file", title: name, sub: f.replace(Quickshell.env("HOME") || "", "~"), glyph: "file", path: f })
        }
        for (const c of clipResults)
            out.push({ kind: "clip", title: c.c.replace(/\s+/g, " ").trim().substring(0, 90), sub: "Copied text", glyph: "clipboard", i: c.i })
        return out
    }

    onQueryChanged: { selected = 0; fileTimer.restart() }
    onViewChanged: { selected = 0; fileTimer.restart(); if (view === "clipboard") clipList.running = true }

    function launch(i) {
        const r = rows[i]
        if (!r) return
        if (r.kind === "app") r.e.execute()
        else if (r.kind === "action") r.a.f()
        else if (r.kind === "file") Quickshell.execDetached(["xdg-open", r.path])
        else if (r.kind === "clip") Quickshell.execDetached([libexec + "/gosaab-clipboard", "copy", String(r.i)])
        if (r.kind === "action" && r.a.g === "clipboard") return
        ShellState.haptic("toggle")
        ShellState.spotlight = false
    }

    Connections {
        target: ShellState
        function onSpotlightChanged() { if (ShellState.spotlight) { spot.view = ""; input.text = ""; input.forceActiveFocus() } }
    }

    Item { id: fullArea; anchors.fill: parent }
    MouseArea { anchors.fill: parent; enabled: ShellState.spotlight; onClicked: ShellState.spotlight = false }

    readonly property bool hasResults: rows.length > 0 || maths !== "" || view !== ""

    Rectangle {
        id: box
        width: 680
        height: 58 + (spot.hasResults ? Math.min(results.implicitHeight, 470) + 16 : 0)
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.2 }
        radius: 29
        color: Theme.panel
        clip: true
        opacity: ShellState.spotlight ? 1 : 0
        scale: ShellState.spotlight ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.4; epsilon: 0.002 } }
        Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        GlassRim { radius: 29 }
        MouseArea { anchors.fill: parent } // keep clicks inside from closing

        Icon { id: glass; name: "search"; width: 22; height: 22; color: Theme.subtext
            anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 18 } }
        TextInput {
            id: input
            anchors { left: glass.right; leftMargin: 12; right: viewButtons.left; rightMargin: 10; top: parent.top; topMargin: 14 }
            height: 30
            clip: true
            color: Theme.text
            font { family: Theme.font; pixelSize: 22 }
            selectionColor: Theme.accent
            focus: true
            Text {
                visible: !input.text
                text: ({ "": "Spotlight Search", apps: "Search Apps", files: "Search Files", actions: "Search Actions",
                         clipboard: "Search Clipboard" })[spot.view]
                color: Theme.subtext; font: input.font
            }
            Keys.onEscapePressed: { if (spot.view !== "" && input.text === "") spot.view = ""; else ShellState.spotlight = false }
            Keys.onDownPressed: spot.selected = Math.min(spot.selected + 1, spot.rows.length - 1)
            Keys.onUpPressed: spot.selected = Math.max(spot.selected - 1, 0)
            Keys.onReturnPressed: spot.launch(spot.selected)
            Keys.onEnterPressed: spot.launch(spot.selected)
            Keys.onTabPressed: { // Tab cycles the views, like Cmd+1..4
                const v = ["", "apps", "files", "actions", "clipboard"]
                spot.view = v[(v.indexOf(spot.view) + 1) % v.length]
            }
        }

        Row { // the four view buttons (Tahoe's Apps / Files / Actions / Clipboard)
            id: viewButtons
            anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 11 }
            spacing: 6
            Repeater {
                model: [{ v: "apps", g: "apps", t: "Apps" }, { v: "files", g: "folder", t: "Files" },
                        { v: "actions", g: "bolt", t: "Actions" }, { v: "clipboard", g: "clipboard", t: "Clipboard" }]
                Rectangle {
                    required property var modelData
                    readonly property bool on: spot.view === modelData.v
                    width: 36; height: 36; radius: 18
                    color: on ? Theme.accent : vb.containsMouse ? Theme.tileHover : Theme.tile
                    scale: vb.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.fast } }
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Icon { anchors.centerIn: parent; width: 18; height: 18; name: modelData.g; color: parent.on ? Theme.onAccent : Theme.text }
                    MouseArea { id: vb; anchors.fill: parent; hoverEnabled: true
                        onClicked: { spot.view = parent.on ? "" : modelData.v; ShellState.haptic("tick"); input.forceActiveFocus() } }
                }
            }
        }

        Flickable {
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 58; bottom: parent.bottom; margins: 8 }
            contentHeight: results.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: results
                width: parent.width
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.5, 0.5, 0.5, 0.2) }
                Text {
                    visible: spot.maths !== ""
                    width: parent.width; height: 44; leftPadding: 12; verticalAlignment: Text.AlignVCenter
                    text: "= " + spot.maths; color: Theme.text; font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
                }
                Text {
                    visible: spot.view !== "" && spot.rows.length === 0
                    width: parent.width; height: 60; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: Theme.subtext; font { family: Theme.font; pixelSize: 14 }
                    text: spot.view === "clipboard" ? "Nothing copied yet. Text you copy shows up here until you sign out."
                        : spot.view === "files" ? "Type at least two letters of a file name." : "No results"
                }
                Repeater {
                    model: spot.rows
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === spot.selected
                        width: results.width; height: 46; radius: 23
                        color: sel ? Theme.accent : "transparent"
                        Text { // section headings, like macOS
                            visible: index === 0 || spot.rows[index - 1].kind !== modelData.kind
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: ({ app: "Applications", action: "Actions", file: "Files", clip: "Clipboard" })[modelData.kind]
                            color: sel ? Qt.rgba(1, 1, 1, 0.8) : Theme.subtext; font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                        }
                        Row {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 110; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            IconTile { visible: modelData.kind === "app"; width: 30; height: 30; source: modelData.icon || ""; label: modelData.title || "" }
                            Rectangle {
                                visible: modelData.kind !== "app"
                                width: 30; height: 30; radius: 8
                                color: sel ? Qt.rgba(1, 1, 1, 0.22) : modelData.kind === "action" ? Theme.accent : Theme.tile
                                Icon { anchors.centerIn: parent; width: 18; height: 18; name: modelData.glyph || "dot"
                                    color: sel || modelData.kind === "action" ? "white" : Theme.text }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 42
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.title
                                    color: sel ? Theme.onAccent : Theme.text; font { family: Theme.font; pixelSize: 14 } }
                                Text { visible: text !== ""; width: parent.width; elide: Text.ElideMiddle; text: modelData.sub
                                    color: sel ? Qt.rgba(1, 1, 1, 0.8) : Theme.subtext; font { family: Theme.font; pixelSize: 11 } }
                            }
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: spot.selected = index; onClicked: spot.launch(index) }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "spotlight"
        function toggle(): void { ShellState.toggle("spotlight") }
        function search(text: string): void { ShellState.spotlight = true; input.text = text }
        function showView(name: string): void { ShellState.spotlight = true; spot.view = name }
        function currentView(): string { return spot.view }
        function results(): string { return spot.rows.filter(r => r.kind === "app").map(r => r.title).join(",") }
        function rowKinds(): string { return spot.rows.map(r => r.kind).join(",") }
    }
}
