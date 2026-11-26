import QtQuick
import QtQml
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// App switcher (Alt/Super+Tab): a glass strip of open apps. Keep holding Alt and press
// Tab to move along; letting go switches to the highlighted app (the compositor tells us).
PanelWindow {
    id: sw
    property bool open: false
    property int selected: 0
    property var mru: []      // windows, most recently used first
    property var items: []    // snapshot taken when the switcher opens

    visible: open || strip.opacity > 0.01
    implicitWidth: Math.max(1, row.implicitWidth + 36)
    implicitHeight: 150
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gosaab-switcher:r30"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Keep a most-recently-used order by watching which window gets focus
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            required property var modelData
            readonly property bool act: modelData.activated
            onActChanged: if (act) sw.touch(modelData)
            Component.onCompleted: sw.touch(modelData, !act)
        }
    }
    function touch(t, atEnd) {
        const list = mru.filter(w => w !== t && ToplevelManager.toplevels.values.includes(w))
        if (atEnd) list.push(t); else list.unshift(t)
        mru = list
    }

    function step(dir) {
        if (!open) {
            items = mru.filter(w => ToplevelManager.toplevels.values.includes(w))
            if (items.length === 0) return
            selected = 0
            open = true
        }
        selected = (selected + dir + items.length) % items.length
    }
    function done() {
        if (!open) return
        const t = items[selected]
        open = false
        if (t) t.activate()
    }

    IpcHandler {
        target: "switcher"
        function next(): void { sw.step(1) }
        function previous(): void { sw.step(-1) }
        function done(): void { sw.done() }
        function cancel(): void { sw.open = false }
        function count(): int { return sw.items.length }
        function current(): string { const t = sw.items[sw.selected]; return t ? t.appId : "" }
    }

    Rectangle {
        id: strip
        anchors.fill: parent
        radius: 30
        color: Theme.panel
        opacity: sw.open ? 1 : 0
        scale: sw.open ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.4; epsilon: 0.002 } }
        GlassRim { radius: 30 }

        Row {
            id: row
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -10
            spacing: 10
            Repeater {
                model: sw.items
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)
                    readonly property bool sel: index === sw.selected
                    width: 96; height: 96
                    Rectangle {
                        id: hi
                        anchors.fill: parent
                        radius: 24
                        color: Theme.tileHover
                        opacity: parent.sel ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    }
                    IconTile {
                        anchors.centerIn: parent
                        width: 72; height: 72
                        scale: parent.sel ? 1.06 : 1
                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.002 } }
                        source: Theme.icon(parent.entry ? parent.entry.icon : "", parent.modelData.appId,
                                           (parent.modelData.appId || "").toLowerCase(), "application-x-executable")
                        label: parent.entry ? Theme.displayName(parent.entry) : (parent.modelData.appId || "")
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { sw.selected = parent.index; sw.done() }
                    }
                }
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 12 }
            readonly property var t: sw.items[sw.selected]
            readonly property var entry: t ? DesktopEntries.heuristicLookup(t.appId) : null
            text: entry ? Theme.displayName(entry) : (t ? (t.title || t.appId) : "")
            color: Theme.text
            font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
            elide: Text.ElideRight
            width: Math.min(implicitWidth, strip.width - 30)
        }
    }
}
