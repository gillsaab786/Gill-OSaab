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
    property bool keyboard: false // touch keyboard (handhelds have no keyboard)
    // Face unlock (Settings > Apps & Security): the lock screen looks for you as soon as it shows
    FileView { id: faceConf; path: "/etc/gill-osaab/face.conf"; blockLoading: true }
    readonly property bool faceUnlock: faceConf.text().indexOf("enabled=on") >= 0
    property bool lookingForFace: false
    function tryFace() {
        if (!faceUnlock || pam.active || !sessionLock.locked) return
        lookingForFace = true
        pam.messageText = ""
        pam.start()
    }
    // Fingerprint (Settings > Apps & Security): checked alongside the password, like Touch ID.
    // Its own PAM stack (gill-osaab-fprint: pam_fprintd only), so typing a password still works.
    FileView { id: fpConf; path: "/etc/gill-osaab/fingerprint.conf"; blockLoading: true }
    readonly property bool fingerUnlock: fpConf.text().indexOf("enabled=on") >= 0
    property int fingerTries: 0
    function tryFinger() {
        if (!fingerUnlock || fp.active || !sessionLock.locked || fingerTries >= 3) return
        fingerTries++
        fp.start()
    }
    Timer { id: fingerRetry; interval: 1500; onTriggered: root.tryFinger() }
    // typed password: answer the waiting prompt, or start a new check
    // Each screen has its own password field; they share what's typed through these:
    property string typed: ""
    signal clearPassword()
    signal shake()
    function submit() {
        if (typed === "") return
        if (pam.active && pam.responseRequired) pam.respond(typed)
        else if (!pam.active) pam.start()
    }
    function unlock() { cover = true; if (fp.active) fp.abort(); unlockTimer.start() }
    Timer { id: unlockTimer; interval: 300; onTriggered: sessionLock.locked = false }
    Timer { id: revealTimer; interval: 30; onTriggered: { root.cover = false; faceTimer.start() } }
    Timer { id: faceTimer; interval: 400; onTriggered: { root.tryFace(); root.fingerTries = 0; root.tryFinger() } }

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
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                          bottomMargin: root.keyboard ? osk.height + 40 : parent.height * 0.12 }
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
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
                    Connections { target: root; function onShake() { shakeAnim.restart() } }
                    SequentialAnimation { // "wrong password" shake, like macOS
                        id: shakeAnim
                        NumberAnimation { target: pill; property: "shake"; to: -14; duration: 50 }
                        NumberAnimation { target: pill; property: "shake"; to: 14; duration: 70 }
                        NumberAnimation { target: pill; property: "shake"; to: -10; duration: 70 }
                        NumberAnimation { target: pill; property: "shake"; to: 8; duration: 60 }
                        NumberAnimation { target: pill; property: "shake"; to: 0; duration: 50 }
                    }
                    TapHandler { onTapped: root.keyboard = true } // touching the field brings up the keyboard
                    TextInput {
                        id: password
                        onTextChanged: root.typed = text
                        Connections { target: root; function onClearPassword() { password.text = "" } }
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: "white"
                        font { family: Theme.font; pixelSize: 14 }
                        focus: true
                        enabled: !pam.active || pam.responseRequired
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !password.text
                            text: pam.active && !pam.responseRequired ? "Checking…" : "Enter Password"; color: Qt.rgba(1, 1, 1, 0.6); font: password.font }
                        onAccepted: root.submit()
                    }
                }
                Text { // face unlock: looking / try again
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.faceUnlock
                    text: root.lookingForFace ? "Looking for you…" : "Try Face Unlock again"
                    color: Qt.rgba(1, 1, 1, root.lookingForFace ? 0.95 : 0.75)
                    font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                    SequentialAnimation on opacity { // gentle pulse while looking
                        running: root.lookingForFace; loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; enabled: !root.lookingForFace
                        onClicked: { if (pam.active) pam.abort(); root.tryFace() } }
                }
                Text { // fingerprint: touch the sensor
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.fingerUnlock
                    text: fp.active ? "Touch the fingerprint sensor" : "Use fingerprint again"
                    color: Qt.rgba(1, 1, 1, fp.active ? 0.95 : 0.75)
                    font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; enabled: !fp.active
                        onClicked: { root.fingerTries = 0; root.tryFinger() } }
                }
                Text { // show/hide the touch keyboard
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.keyboard ? "Hide keyboard" : "Show keyboard"
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font { family: Theme.font; pixelSize: 13 }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.keyboard = !root.keyboard }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pam.messageText
                    visible: text !== ""
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font { family: Theme.font; pixelSize: 12 }
                }
            }

            OnScreenKeyboard {
                id: osk
                visible: root.keyboard
                target: password
                fontName: Theme.font
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                onAccepted: root.submit()
            }
        }
    }

    PamContext {
        id: pam
        config: "gill-osaab-lock"
        user: root.user
        property string messageText: ""
        // the face step ran first; now it wants the password: send it if typed, else wait for it
        onResponseRequiredChanged: if (responseRequired) {
            root.lookingForFace = false
            if (root.typed !== "") respond(root.typed)
            else if (root.faceUnlock) pam.messageText = "Not recognised – enter your password"
        }
        onCompleted: result => {
            const wasFace = root.lookingForFace && root.typed === ""
            root.lookingForFace = false
            if (result === PamResult.Success) {
                root.clearPassword()
                pam.messageText = ""
                ShellState.haptic("success")
                root.unlock()
            } else if (!wasFace) {
                root.clearPassword()
                pam.messageText = "Incorrect password"
                ShellState.haptic("error")
                root.shake()
            }
        }
        onError: pam.messageText = "Could not check the password"
    }

    PamContext {
        id: fp
        config: "gill-osaab-fprint"
        user: root.user
        onCompleted: result => {
            if (!sessionLock.locked) return
            if (result === PamResult.Success) {
                if (pam.active) pam.abort()
                root.clearPassword()
                pam.messageText = ""
                ShellState.haptic("success")
                root.unlock()
            } else {
                pam.messageText = "Fingerprint not recognised"
                fingerRetry.start()
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { ShellState.closeAll(); root.cover = true; sessionLock.locked = true; revealTimer.start() }
        function isLocked(): bool { return sessionLock.locked }
        function unlockForTest(): void { if (root.testMode) root.unlock() }
        function keyboard(): void { root.keyboard = !root.keyboard }
        function typeForTest(text: string): void { if (root.testMode) { root.typed = text; root.submit() } }
    }
}
