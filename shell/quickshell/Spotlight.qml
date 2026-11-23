import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Spotlight: Super+Space, type to find apps (and do quick maths), Enter to open.
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
    readonly property string query: input.text.trim().toLowerCase()
    readonly property var apps: {
        const all = DesktopEntries.applications.values.filter(e => Theme.listed(e))
        if (query === "") return []
        const score = e => {
            const n = e.name.toLowerCase()
            if (n.startsWith(query)) return 0
            if (n.split(" ").some(w => w.startsWith(query))) return 1
            if (n.includes(query)) return 2
            if ((e.genericName || "").toLowerCase().includes(query) || e.keywords.some(k => k.toLowerCase().includes(query))) return 3
            return 9
        }
        return all.map(e => ({ e: e, s: score(e) })).filter(x => x.s < 9)
                  .sort((a, b) => a.s - b.s || a.e.name.localeCompare(b.e.name)).slice(0, 7).map(x => x.e)
    }
    readonly property string maths: {
        if (!/^[0-9+\-*/().% ^]+$/.test(query) || !/[0-9]/.test(query)) return ""
        try {
            const v = Function("return (" + query.replace(/\^/g, "**") + ")")()
            return (typeof v === "number" && isFinite(v)) ? String(Math.round(v * 1e10) / 1e10) : ""
        } catch (e) { return "" }
    }
    onQueryChanged: selected = 0

    function launch(i) {
        const e = apps[i]
        if (e) e.execute()
        ShellState.spotlight = false
    }

    Connections {
        target: ShellState
        function onSpotlightChanged() { if (ShellState.spotlight) { input.text = ""; input.forceActiveFocus() } }
    }

    Item { id: fullArea; anchors.fill: parent }
    MouseArea { anchors.fill: parent; enabled: ShellState.spotlight; onClicked: ShellState.spotlight = false }

    Rectangle {
        id: box
        width: 640
        height: 58 + (list.count > 0 || spot.maths !== "" ? results.height + 10 : 0)
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.22 }
        radius: 29
        color: Theme.panel
        border { color: Theme.panelBorder; width: 1 }
        clip: true
        opacity: ShellState.spotlight ? 1 : 0
        scale: ShellState.spotlight ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.4; epsilon: 0.002 } }
        Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        GlassRim { radius: 29 }
        MouseArea { anchors.fill: parent } // keep clicks inside from closing

        Icon { id: glass; name: "search"; width: 22; height: 22; color: Theme.subtext
            anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 18 } }
        TextInput {
            id: input
            anchors { left: glass.right; leftMargin: 12; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 14 }
            height: 30
            color: Theme.text
            font { family: Theme.font; pixelSize: 22 }
            selectionColor: Theme.accent
            focus: true
            Text { visible: !input.text; text: "Spotlight Search"; color: Theme.subtext; font: input.font }
            Keys.onEscapePressed: ShellState.spotlight = false
            Keys.onDownPressed: spot.selected = Math.min(spot.selected + 1, list.count - 1)
            Keys.onUpPressed: spot.selected = Math.max(spot.selected - 1, 0)
            Keys.onReturnPressed: spot.launch(spot.selected)
            Keys.onEnterPressed: spot.launch(spot.selected)
        }

        Column {
            id: results
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 58; margins: 8 }
            Rectangle { width: parent.width; height: 1; color: Theme.panelBorder }
            Text {
                visible: spot.maths !== ""
                width: parent.width; height: 44; leftPadding: 12; verticalAlignment: Text.AlignVCenter
                text: "= " + spot.maths; color: Theme.text; font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
            }
            ListView {
                id: list
                width: parent.width
                height: count * 44
                interactive: false
                model: spot.apps
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width; height: 44; radius: 10
                    color: index === spot.selected ? Theme.accent : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 12
                        IconImage { width: 30; height: 30; source: Theme.icon(modelData.icon, "application-x-executable") }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: modelData.name; color: index === spot.selected ? "white" : Theme.text; font { family: Theme.font; pixelSize: 14 } }
                            Text { visible: text !== ""; text: modelData.genericName || modelData.comment || ""
                                color: index === spot.selected ? Qt.rgba(1, 1, 1, 0.8) : Theme.subtext; font { family: Theme.font; pixelSize: 11 } }
                        }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: spot.selected = index; onClicked: spot.launch(index) }
                }
            }
        }
    }

    IpcHandler {
        target: "spotlight"
        function toggle(): void { ShellState.toggle("spotlight") }
        function search(text: string): void { ShellState.spotlight = true; input.text = text }
    }
}
