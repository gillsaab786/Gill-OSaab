import QtQuick

// Touch keyboard for the lock screen and the login screen, so handhelds without a keyboard
// (ROG Ally, Legion Go, GPD…) can type a password. Glass look; types into `target` (a TextInput).
// Shared by the shell and the SDDM theme (install.sh copies it), so it only uses QtQuick.
Rectangle {
    id: kb
    property Item target: null
    property string fontName: "Inter"
    property bool shifted: false
    property int page: 0 // 0 letters, 1 numbers/symbols, 2 more symbols
    signal accepted()

    width: Math.min(parent ? parent.width - 24 : 820, 860)
    height: width * 0.36
    radius: 24
    color: Qt.rgba(0.10, 0.10, 0.12, 0.72)
    border { color: Qt.rgba(1, 1, 1, 0.20); width: 1 }
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    readonly property var pages: [
        [["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
         ["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"], ["123", "space", "⏎"]],
        [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], ["-", "/", ":", ";", "(", ")", "$", "&", "@"],
         ["#+=", ".", ",", "?", "!", "'", "\"", "_", "⌫"], ["ABC", "space", "⏎"]],
        [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
         ["123", "`", "§", "°", "¡", "¿", "©", "®", "⌫"], ["ABC", "space", "⏎"]]
    ]
    readonly property real unit: (width - 24) / 10

    function widthOf(k) {
        if (k === "space") return unit * 6
        if (k === "⏎" || k === "123" || k === "ABC") return unit * 2
        if (k === "⇧" || k === "⌫" || k === "#+=") return unit * 1.5
        return unit
    }
    function label(k) {
        if (k === "space") return ""
        return (kb.shifted && kb.page === 0 && k.length === 1) ? k.toUpperCase() : k
    }
    function press(k) {
        if (k === "⇧") { shifted = !shifted; return }
        if (k === "123") { page = 1; return }
        if (k === "#+=") { page = 2; return }
        if (k === "ABC") { page = 0; return }
        if (k === "⏎") { accepted(); return }
        if (!target) return
        target.forceActiveFocus()
        if (k === "⌫") {
            const p = target.cursorPosition
            if (p > 0) target.remove(p - 1, p)
            return
        }
        target.insert(target.cursorPosition, k === "space" ? " " : label(k))
        if (shifted && page === 0) shifted = false
    }

    Column {
        anchors.centerIn: parent
        spacing: kb.unit * 0.12
        Repeater {
            model: kb.pages[kb.page]
            delegate: Row {
                required property var modelData
                anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                spacing: kb.unit * 0.12
                Repeater {
                    model: parent.modelData
                    delegate: Rectangle {
                        required property string modelData
                        width: kb.widthOf(modelData) - kb.unit * 0.12
                        height: kb.unit * 0.82
                        radius: 12
                        color: tap.pressed ? Qt.rgba(1, 1, 1, 0.42)
                             : (modelData.length > 1 && modelData !== "space") || modelData === "⇧" || modelData === "⌫"
                               ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.20)
                        border { color: modelData === "⇧" && kb.shifted ? "white" : "transparent"; width: 1 }
                        scale: tap.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 80 } }
                        Text {
                            anchors.centerIn: parent
                            text: kb.label(parent.modelData)
                            color: "white"
                            font { family: kb.fontName; pixelSize: Math.max(14, kb.unit * 0.34) }
                        }
                        MouseArea { id: tap; anchors.fill: parent; onClicked: kb.press(parent.modelData) }
                    }
                }
            }
        }
    }
}
