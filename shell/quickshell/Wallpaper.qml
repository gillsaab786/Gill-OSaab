import QtQuick
import Quickshell
import Quickshell.Wayland

// The desktop picture. "Tide" has a light and a dark version that cross-fade with Dark Mode
// (and with Auto at sunrise/sunset); other choices are a single picture.
PanelWindow {
    id: wall
    property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "black"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "gill-osaab-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property size pixels: Qt.size(modelData ? modelData.width : 1920, modelData ? modelData.height : 1080)
    Image {
        anchors.fill: parent
        source: "file://" + Theme.wallpaperFor(false)
        sourceSize: wall.pixels
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: Theme.dynamicWallpaper || !Theme.dark
    }
    Image {
        anchors.fill: parent
        source: "file://" + Theme.wallpaperFor(true)
        sourceSize: wall.pixels
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: Theme.dynamicWallpaper ? Theme.darkness : 1
        visible: opacity > 0.001
    }
}
