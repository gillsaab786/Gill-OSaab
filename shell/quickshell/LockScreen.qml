import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// macOS-style lock screen: big clock over the wallpaper, your name, a password pill.
Scope {
    id: root
    property bool testMode: Quickshell.env("GOSAAB_TEST") === "1"
    readonly property string user: Quickshell.env("USER") || "user"
    readonly property string fullName: Quickshell.env("GOSAAB_USER_NAME") || user

    // fades: the lock screen fades up from black; unlocking fades to black and the
    // compositor then fades the desktop back in
    property bool cover: true
    function unlock() { cover = true; unlockTimer.start() }
    Timer { id: unlockTimer; interval: 300; onTriggered: sessionLock.locked = false }
    Timer { id: revealTimer; interval: 30; onTriggered: root.cover = false }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            id: surface
            color: "black"
            Rectangle { // fade cover
                anchors.fill: parent
                z: 100
                color: "black"
                opacity: root.cover ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
            }

            Image {
                anchors.fill: parent
                source: "file://" + Theme.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.30) }

            SystemClock { id: clock; precision: SystemClock.Seconds }

            Column {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.10 }
                spacing: -6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "dddd d MMMM")
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font { family: Theme.font; pixelSize: 26; weight: Font.DemiBold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "h:mm")
                    color: Qt.rgba(1, 1, 1, 0.92)
                    font { family: Theme.font; pixelSize: 128; weight: Font.Bold }
                }
            }

            Column {
                id: login
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.12 }
                spacing: 12
                Rectangle { // avatar
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72; height: 72; radius: 36
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#64d2ff" }
                        GradientStop { position: 1; color: "#5e5ce6" }
                    }
                    Text { anchors.centerIn: parent; text: root.fullName.charAt(0).toUpperCase(); color: "white"
                        font { family: Theme.font; pixelSize: 32; weight: Font.Bold } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.fullName; color: "white"
                    font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold }
                }
                Rectangle {
                    id: pill
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220; height: 34; radius: 17
                    color: Qt.rgba(1, 1, 1, 0.20)
                    border { color: Qt.rgba(1, 1, 1, 0.25); width: 1 }
                    property real shake: 0
                    transform: Translate { x: pill.shake }
                    SequentialAnimation { // "wrong password" shake, like macOS
                        id: shakeAnim
                        NumberAnimation { target: pill; property: "shake"; to: -14; duration: 50 }
                        NumberAnimation { target: pill; property: "shake"; to: 14; duration: 70 }
                        NumberAnimation { target: pill; property: "shake"; to: -10; duration: 70 }
                        NumberAnimation { target: pill; property: "shake"; to: 8; duration: 60 }
                        NumberAnimation { target: pill; property: "shake"; to: 0; duration: 50 }
                    }
                    TextInput {
                        id: password
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: "white"
                        font { family: Theme.font; pixelSize: 14 }
                        focus: true
                        enabled: !pam.active
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !password.text
                            text: pam.active ? "Checking…" : "Enter Password"; color: Qt.rgba(1, 1, 1, 0.6); font: password.font }
                        onAccepted: {
                            if (text === "") return
                            pam.start()
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pam.messageText
                    visible: text !== ""
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
        }
    }

    PamContext {
        id: pam
        config: "gill-osaab-lock"
        user: root.user
        property string messageText: ""
        onResponseRequiredChanged: if (responseRequired) { respond(password.text) }
        onCompleted: result => {
            if (result === PamResult.Success) {
                password.text = ""
                pam.messageText = ""
                root.unlock()
            } else {
                password.text = ""
                pam.messageText = "Incorrect password"
                shakeAnim.restart()
            }
        }
        onError: pam.messageText = "Could not check the password"
    }

    IpcHandler {
        target: "lock"
        function lock(): void { ShellState.closeAll(); root.cover = true; sessionLock.locked = true; revealTimer.start() }
        function isLocked(): bool { return sessionLock.locked }
        function unlockForTest(): void { if (root.testMode) root.unlock() }
    }
}
