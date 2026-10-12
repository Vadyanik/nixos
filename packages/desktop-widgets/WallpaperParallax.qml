import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    required property string python
    required property string configDir
    property var state: ({ x: 0, y: 0, screens: {}, devices: 0 })
    property bool enabled: false
    onEnabledChanged: {
        retry.stop();
        pointer.running = enabled;
    }
    readonly property real zoom: enabled ? 1.025 : 1
    property real motionX: enabled ? state.x : 0
    property real motionY: enabled ? state.y : 0
    Behavior on motionX { SmoothedAnimation { velocity: 0.07; duration: 220 } }
    Behavior on motionY { SmoothedAnimation { velocity: 0.083; duration: 220 } }
    function offsetX(screen): real {
        return enabled ? -screen.width * (zoom - 1) / 2 + motionX * screen.width * 0.008 : 0;
    }
    function offsetY(screen): real {
        return enabled ? -screen.height * (zoom - 1) / 2 + motionY * screen.height * 0.008 : 0;
    }
    function bottomMargin(screen, original): real {
        return zoom * original - screen.height * (zoom - 1) - offsetY(screen);
    }
    function rightMargin(screen, original): real {
        return zoom * original - screen.width * (zoom - 1) - offsetX(screen);
    }

    Process {
        id: pointer
        command: [root.python, root.configDir + "parallax-pointer.py"]
        running: root.enabled
        stdout: SplitParser {
            onRead: data => {
                try { root.state = JSON.parse(data); }
                catch (error) { console.warn("Parallax state:", error); }
            }
        }
        onExited: if (root.enabled) retry.restart()
    }
    Timer { id: retry; interval: 3000; onTriggered: pointer.running = root.enabled }

    IpcHandler {
        target: "parallax"
        function toggle(): bool { root.enabled = !root.enabled; return root.enabled; }
        function status(): string { return JSON.stringify({enabled: root.enabled, x: root.state.x, y: root.state.y, screens: root.state.screens, devices: root.state.devices}); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "wallpaper-parallax"
            mask: Region {}
            color: "transparent"
            // QsWindow recreates its content when hidden. Tying visibility to
            // child Image.status would repeatedly destroy the loaded images.
            visible: root.enabled && wallpaper !== ""
            readonly property string wallpaper: root.state.screens[modelData.name]?.image || ""
            property bool secondActive: false
            property string firstSource: ""
            property string secondSource: ""
            onWallpaperChanged: {
                if (!wallpaper) return;
                if (secondActive) firstSource = "file://" + wallpaper;
                else secondSource = "file://" + wallpaper;
            }

            Item {
                anchors.fill: parent
                clip: true
                Item {
                    // Keep overscan small enough to retain the caption margins.
                    width: window.width * root.zoom
                    height: window.height * root.zoom
                    x: root.offsetX(window.modelData)
                    y: root.offsetY(window.modelData)
                    Image {
                        id: first
                        source: window.firstSource
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: window.secondActive ? 0 : 1
                        onStatusChanged: if (status === Image.Ready && source.toString() === "file://" + window.wallpaper) window.secondActive = false
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }
                    }
                    Image {
                        id: second
                        source: window.secondSource
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: window.secondActive ? 1 : 0
                        onStatusChanged: if (status === Image.Ready && source.toString() === "file://" + window.wallpaper) window.secondActive = true
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }
                    }
                }
            }
        }
    }
}
