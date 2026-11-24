import QtQuick

// Gill-OSaab login screen: wallpaper, big clock, pick your account, type your password.
// Uses SDDM's objects: sddm (login/power), userModel, sessionModel, config.
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "black"

    readonly property string fontName: config.font || "Inter"
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string userName: ""
    property string realName: ""
    property string message: ""
    property bool keyboard: false // touch keyboard (handhelds have no keyboard)

    // look up the chosen account's names from the model
    Repeater {
        model: userModel
        Item {
            required property int index
            required property string name
            required property string realName
            Component.onCompleted: if (index === root.userIndex) { root.userName = name; root.realName = realName }
        }
    }
    onUserIndexChanged: message = ""

    Connections {
        target: sddm
        function onLoginFailed() {
            password.text = ""
            root.message = "Incorrect password"
            shake.restart()
        }
    }

    Image {
        anchors.fill: parent
        source: config.background ? "file://" + config.background : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28) }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
    Column {
        id: clock
        property date now: new Date()
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.10 }
        spacing: -6
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clock.now, "dddd d MMMM")
            color: Qt.rgba(1, 1, 1, 0.85); font { family: root.fontName; pixelSize: 26; weight: Font.DemiBold } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clock.now, "h:mm")
            color: Qt.rgba(1, 1, 1, 0.92); font { family: root.fontName; pixelSize: 128; weight: Font.Bold } }
    }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                  bottomMargin: root.keyboard ? osk.height + 80 : parent.height * 0.12 }
        spacing: 12

        Row { // accounts (only shown when there is more than one)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 26
            visible: userModel.count > 1
            Repeater {
                model: userModel
                Column {
                    required property int index
                    required property string name
                    required property string realName
                    spacing: 6
                    opacity: index === root.userIndex ? 1 : 0.55
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 46; height: 46; radius: 23; color: Qt.rgba(1, 1, 1, 0.25)
                        Text { anchors.centerIn: parent; text: (realName || name).charAt(0).toUpperCase(); color: "white"
                            font { family: root.fontName; pixelSize: 20; weight: Font.Bold } }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: realName || name; color: "white"
                        font { family: root.fontName; pixelSize: 12 } }
                    MouseArea { anchors.fill: parent; onClicked: { root.userIndex = index; root.userName = name; root.realName = realName; password.forceActiveFocus() } }
                }
            }
        }

        Rectangle { // avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; radius: 36
            gradient: Gradient {
                GradientStop { position: 0; color: "#64d2ff" }
                GradientStop { position: 1; color: "#5e5ce6" }
            }
            Text { anchors.centerIn: parent; text: (root.realName || root.userName || "?").charAt(0).toUpperCase()
                color: "white"; font { family: root.fontName; pixelSize: 32; weight: Font.Bold } }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.realName || root.userName; color: "white"
            font { family: root.fontName; pixelSize: 16; weight: Font.DemiBold } }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 34; radius: 17
            color: Qt.rgba(1, 1, 1, 0.20)
            border { color: Qt.rgba(1, 1, 1, 0.25); width: 1 }
            property real dx: 0
            transform: Translate { x: pill.dx }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: pill; property: "dx"; to: -14; duration: 50 }
                NumberAnimation { target: pill; property: "dx"; to: 14; duration: 70 }
                NumberAnimation { target: pill; property: "dx"; to: -10; duration: 70 }
                NumberAnimation { target: pill; property: "dx"; to: 0; duration: 60 }
            }
            TapHandler { onTapped: root.keyboard = true } // touch: bring up the keyboard
            TextInput {
                id: password
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: "white"
                font { family: root.fontName; pixelSize: 14 }
                focus: true
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !password.text; text: "Enter Password"
                    color: Qt.rgba(1, 1, 1, 0.6); font: password.font }
                Keys.onReturnPressed: sddm.login(root.userName, password.text, root.sessionIndex)
                Keys.onEnterPressed: sddm.login(root.userName, password.text, root.sessionIndex)
            }
        }
        Text { // show/hide the touch keyboard
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.keyboard ? "Hide keyboard" : "Show keyboard"
            color: Qt.rgba(1, 1, 1, 0.75); font { family: root.fontName; pixelSize: 13 }
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.keyboard = !root.keyboard }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: root.message !== ""; text: root.message
            color: Qt.rgba(1, 1, 1, 0.85); font { family: root.fontName; pixelSize: 12 } }
    }

    OnScreenKeyboard {
        id: osk
        visible: root.keyboard
        target: password
        fontName: root.fontName
        z: 10
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 70 }
        onAccepted: sddm.login(root.userName, password.text, root.sessionIndex)
    }

    // bottom bar: session (Desktop / Game Mode) and power
    Row {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
        spacing: 14
        Repeater {
            model: sessionModel
            Rectangle {
                required property int index
                required property string name
                width: label.implicitWidth + 28; height: 30; radius: 15
                color: index === root.sessionIndex ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.10)
                Text { id: label; anchors.centerIn: parent; text: name; color: "white"; font { family: root.fontName; pixelSize: 12 } }
                MouseArea { anchors.fill: parent; onClicked: root.sessionIndex = index }
            }
        }
        Item { width: 20; height: 1 }
        Repeater {
            model: [["Sleep", function() { sddm.suspend() }, sddm.canSuspend],
                    ["Restart", function() { sddm.reboot() }, sddm.canReboot],
                    ["Shut Down", function() { sddm.powerOff() }, sddm.canPowerOff]]
            Rectangle {
                required property var modelData
                visible: modelData[2]
                width: plabel.implicitWidth + 28; height: 30; radius: 15
                color: pm.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10)
                Text { id: plabel; anchors.centerIn: parent; text: modelData[0]; color: "white"; font { family: root.fontName; pixelSize: 12 } }
                MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: modelData[1]() }
            }
        }
    }
}
