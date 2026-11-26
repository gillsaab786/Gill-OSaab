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

    implicitHeight: Math.max(body.implicitHeight, card.progress >= 0 ? 56 : 0) + 24
    radius: 24
    color: Theme.panel
    border { color: Theme.panelBorder; width: 1 }

    // slide in from the right with a little spring, like iOS/macOS banners
    property real slide: banner ? 1 : 0
    transform: Translate { x: card.slide * 400 }
    opacity: 1 - card.slide
    Component.onCompleted: slide = 0
    Behavior on slide { SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.002 } }

    // going away: slide out to the right and fade, then remove (also when swiped)
    property bool leaving: false
    property var afterLeave: null
    function leave(fn) {
        if (leaving) return
        leaving = true; afterLeave = fn; slide = 1; leaveTimer.start()
    }
    function close() { leave(() => { if (card.banner) card.timedOut(); else card.notification.dismiss() }) }
    Timer { id: leaveTimer; interval: 320; onTriggered: if (card.afterLeave) card.afterLeave() }

    Timer { // banners go away after 5s unless something is still in progress
        running: card.banner && (card.progress < 0 || card.progress >= 100) && !hover.containsMouse
        interval: card.progress >= 100 ? 3000 : 5000
        onTriggered: card.leave(() => card.timedOut())
    }

    GlassRim { radius: 24 }
    // press: glass squishes a little, like iOS 26
    scale: hover.pressed ? 0.97 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.002 } }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        property real startX: 0
        property bool swiped: false
        onPressed: (m) => { startX = m.x; swiped = false }
        onPositionChanged: (m) => { if (pressed && !card.leaving) card.slide = Math.max(0, (m.x - startX) / 400) }
        onReleased: (m) => {
            if (card.slide > 0.25) { swiped = true; card.close() } else if (!card.leaving) card.slide = 0
        }
        onClicked: {
            if (swiped || card.leaving) return
            const def = card.notification.actions.find(a => a.identifier === "default")
            if (def) def.invoke()
            card.close()
        }
    }

    ProgressRing { // downloads, installs, updates: Liquid Glass ring with the percentage
        visible: card.progress >= 0
        value: Math.max(0, card.progress)
        width: 56; height: 56
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        z: 2
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
            width: parent.width - 46 - (card.progress >= 0 ? 66 : 0)
            spacing: 2
            Row {
                width: parent.width
                Text {
                    width: parent.width - when.width
                    text: card.notification.appName || "Gill(OS)"
                    color: Theme.subtext; elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 11; weight: Font.Medium; capitalization: Font.AllUppercase }
                }
                Text { id: when; text: "now"; color: Theme.subtext; font { family: Theme.font; pixelSize: 11 } }
            }
            Text {
                width: parent.width
                text: card.notification.summary
                textFormat: Text.PlainText // apps can't inject formatting or images here
                color: Theme.text; elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: text !== ""
                // bold/italic/links only: no <img> (a remote image would tell a website you saw it)
                text: card.notification.body.replace(/<img[^>]*>/gi, "")
                color: Theme.text; opacity: 0.85
                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                textFormat: Text.StyledText
                font { family: Theme.font; pixelSize: 13 }
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
