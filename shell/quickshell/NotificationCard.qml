import QtQuick
import Quickshell
import Quickshell.Widgets

// One notification: app icon, title, text, optional progress bar (e.g. downloads) and actions.
Rectangle {
    id: card
    property var notification
    property real progress: -1   // 0..100, or -1 for none
    property bool banner: false
    signal timedOut()

    implicitHeight: body.implicitHeight + 24
    radius: 24
    color: Theme.panel
    border { color: Theme.panelBorder; width: 1 }

    // slide in from the right with a little spring, like iOS/macOS banners
    property real slide: banner ? 1 : 0
    transform: Translate { x: card.slide * 400 }
    opacity: 1 - card.slide
    Component.onCompleted: slide = 0
    Behavior on slide { SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.002 } }

    Timer { // banners go away after 5s unless something is still in progress
        running: card.banner && (card.progress < 0 || card.progress >= 100) && !hover.containsMouse
        interval: card.progress >= 100 ? 3000 : 5000
        onTriggered: card.timedOut()
    }

    GlassRim { radius: 24 }
    // press: glass squishes a little, like iOS 26
    scale: hover.pressed ? 0.97 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.002 } }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            const def = card.notification.actions.find(a => a.identifier === "default")
            if (def) def.invoke()
            if (card.banner) card.timedOut(); else card.notification.dismiss()
        }
    }

    Row {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10
        Item {
            width: 36; height: 36
            readonly property string src: Theme.icon(card.notification.image, card.notification.appIcon,
                card.notification.desktopEntry, (card.notification.appName || "").toLowerCase(), "dialog-information-symbolic", "dialog-information")
            IconImage { anchors.fill: parent; visible: parent.src !== ""; source: parent.src }
            Rectangle { // no icon found: a tidy letter tile instead of a broken image
                anchors.fill: parent; radius: 9; visible: parent.src === ""; color: Theme.accent
                Text { anchors.centerIn: parent; text: (card.notification.appName || "G").charAt(0).toUpperCase()
                    color: "white"; font { family: Theme.font; pixelSize: 18; weight: Font.Bold } }
            }
        }
        Column {
            width: parent.width - 46
            spacing: 2
            Row {
                width: parent.width
                Text {
                    width: parent.width - when.width
                    text: card.notification.appName || "Gill-OSaab"
                    color: Theme.subtext; elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 11; weight: Font.Medium; capitalization: Font.AllUppercase }
                }
                Text { id: when; text: "now"; color: Theme.subtext; font { family: Theme.font; pixelSize: 11 } }
            }
            Text {
                width: parent.width
                text: card.notification.summary
                color: Theme.text; elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: card.notification.body
                color: Theme.text; opacity: 0.85
                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                textFormat: Text.StyledText
                font { family: Theme.font; pixelSize: 13 }
            }
            Item { // progress bar (downloads, installs, updates)
                visible: card.progress >= 0
                width: parent.width; height: 18
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - pct.width - 8; height: 5; radius: 2.5
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        width: parent.width * Math.max(0, card.progress) / 100; height: parent.height; radius: 2.5
                        color: card.progress >= 100 ? Theme.green : Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    id: pct
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: Math.round(card.progress) + "%"
                    color: Theme.subtext; font { family: Theme.font; pixelSize: 11 }
                }
            }
            Row {
                visible: card.notification.actions.length > 0
                spacing: 6
                topPadding: 4
                Repeater {
                    model: card.notification.actions.filter(a => a.identifier !== "default")
                    Rectangle {
                        required property var modelData
                        width: actionText.implicitWidth + 20; height: 24; radius: 7
                        color: actMouse.containsMouse ? Theme.tileHover : Theme.tile
                        Text { id: actionText; anchors.centerIn: parent; text: modelData.text; color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
                        MouseArea { id: actMouse; anchors.fill: parent; hoverEnabled: true; onClicked: modelData.invoke() }
                    }
                }
            }
        }
    }
}
