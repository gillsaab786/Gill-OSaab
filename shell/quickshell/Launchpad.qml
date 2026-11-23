import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Launchpad: every app in a paged grid over frosted glass (Super+G, or the Dock).
PanelWindow {
    id: pad
    visible: ShellState.launchpad || stage.opacity > 0.01
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gosaab-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ShellState.launchpad ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int columns: width > 1600 ? 7 : width > 1000 ? 6 : 5
    readonly property int rows: height > 900 ? 5 : 4
    readonly property int perPage: columns * rows
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => Theme.listed(e) && (query === "" || e.name.toLowerCase().includes(query)
                 || e.keywords.some(k => k.toLowerCase().includes(query))))
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property int pages: Math.max(1, Math.ceil(apps.length / perPage))
    property int page: 0
    property int selected: -1 // highlighted app (controller D-pad / arrow keys), -1 = none
    onQueryChanged: { page = 0; selected = query === "" ? -1 : 0 }
    function moveSelection(dx, dy) {
        if (apps.length === 0) return
        let i = selected < 0 ? page * perPage : selected + dx + dy * columns
        i = Math.max(0, Math.min(apps.length - 1, i))
        selected = i
        page = Math.floor(i / perPage)
    }

    function open(e) {
        e.execute()
        ShellState.launchpad = false
    }

    Connections {
        target: ShellState
        function onLaunchpadChanged() { if (ShellState.launchpad) { search.text = ""; pad.page = 0; search.forceActiveFocus() } }
    }

    Rectangle {
        id: stage
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.03, 0.06, 0.38)
        opacity: ShellState.launchpad ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        MouseArea { // click empty space to close; scroll to turn pages
            anchors.fill: parent
            onClicked: ShellState.launchpad = false
            onWheel: w => {
                if (w.angleDelta.y < 0 || w.angleDelta.x < 0) pad.page = Math.min(pad.page + 1, pad.pages - 1)
                else pad.page = Math.max(pad.page - 1, 0)
            }
        }

        Rectangle { // search field
            id: searchBox
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 60 }
            width: 260; height: 32; radius: 9
            color: Qt.rgba(1, 1, 1, 0.14)
            border { color: Qt.rgba(1, 1, 1, 0.12); width: 1 }
            Icon { id: glass; name: "search"; width: 14; height: 14; color: Theme.subtext
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
            TextInput {
                id: search
                anchors { left: glass.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                color: Theme.text; font { family: Theme.font; pixelSize: 14 }
                Text { visible: !search.text; text: "Search"; color: Theme.subtext; font: search.font }
                Keys.onEscapePressed: { if (search.text) search.text = ""; else ShellState.launchpad = false }
                Keys.onReturnPressed: if (pad.apps.length) pad.open(pad.apps[Math.max(0, pad.selected)])
                Keys.onRightPressed: pad.moveSelection(1, 0)
                Keys.onLeftPressed: pad.moveSelection(-1, 0)
                Keys.onUpPressed: pad.moveSelection(0, -1)
                Keys.onDownPressed: pad.moveSelection(0, 1)
            }
        }

        Item {
            id: viewport
            anchors { left: parent.left; right: parent.right; top: searchBox.bottom; topMargin: 40; bottom: dots.top; bottomMargin: 24 }
            clip: true
            // the zoom-in as Launchpad opens, like macOS
            scale: ShellState.launchpad ? 1 : 1.08
            Behavior on scale { NumberAnimation { duration: Theme.normal + 60; easing.type: Easing.OutCubic } }

            Row {
                id: strip
                x: -pad.page * viewport.width
                Behavior on x { SpringAnimation { spring: 3.0; damping: 0.36; epsilon: 0.5 } }
                Repeater {
                    model: pad.pages
                    Item {
                        id: pageItem
                        required property int index
                        width: viewport.width; height: viewport.height
                        Grid {
                            anchors.centerIn: parent
                            columns: pad.columns
                            readonly property real cellW: Math.min(150, (viewport.width - 200) / pad.columns)
                            readonly property real cellH: Math.min(150, viewport.height / pad.rows)
                            Repeater {
                                model: pad.apps.slice(pageItem.index * pad.perPage, (pageItem.index + 1) * pad.perPage)
                                Item {
                                    required property var modelData
                                    required property int index
                                    width: parent.cellW; height: parent.cellH
                                    Rectangle { // controller / keyboard highlight: glass pill around the app
                                        anchors.fill: parent; anchors.margins: 6; radius: 26
                                        color: Qt.rgba(1, 1, 1, 0.16)
                                        visible: pad.selected === pageItem.index * pad.perPage + parent.index
                                        GlassRim { radius: 26 }
                                    }
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        IconImage {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 72; height: 72
                                            source: Theme.icon(modelData.icon, "application-x-executable")
                                            scale: appMouse.pressed ? 0.88 : appMouse.containsMouse ? 1.06 : 1
                                            Behavior on scale { NumberAnimation { duration: Theme.fast } }
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: Math.min(implicitWidth, parent.parent.width - 12)
                                            text: Theme.displayName(modelData); color: "white"; elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            font { family: Theme.font; pixelSize: 13 }
                                            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
                                        }
                                    }
                                    MouseArea { id: appMouse; anchors.fill: parent; hoverEnabled: true; onClicked: pad.open(modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }

        Row { // page dots
            id: dots
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 120 }
            spacing: 10
            visible: pad.pages > 1
            Repeater {
                model: pad.pages
                Rectangle {
                    required property int index
                    width: 8; height: 8; radius: 4
                    color: "white"; opacity: index === pad.page ? 0.95 : 0.35
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: pad.page = index }
                }
            }
        }
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void { ShellState.toggle("launchpad") }
    }
}
