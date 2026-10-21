import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property string share: "@share@"
    property var pointer: ({ x: 0, y: 0 })
    property string wallpaperId: ""
    property string cursorDebug: "none"
    readonly property var catalog: {
        try { return JSON.parse(catalogFile.text()); }
        catch (error) { return { default: "00004", wallpapers: {} }; }
    }
    readonly property string activeId: catalog.wallpapers[wallpaperId] ? wallpaperId : catalog.default
    readonly property var active: catalog.wallpapers[activeId] || ({ focusY: 0.5, back: 0.012, front: 0.035 })

    FileView {
        id: catalogFile
        path: root.share + "wallpapers.json"
        blockLoading: true
    }
    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/parallax-wallpaper/current"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaperId = text().trim()
        onLoadFailed: root.wallpaperId = ""
    }

    // Smoothed pointer so quick flicks glide instead of snapping the layers.
    property real motionX: pointer.x
    property real motionY: pointer.y
    Behavior on motionX { SmoothedAnimation { velocity: 0.9; duration: 260 } }
    Behavior on motionY { SmoothedAnimation { velocity: 0.9; duration: 260 } }

    Process {
        id: pointerProcess
        command: ["@python@", "@share@parallax-pointer.py"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try { root.pointer = JSON.parse(data); }
                catch (error) { console.warn("Parallax pointer:", error); }
            }
        }
        onExited: retry.restart()
    }
    Timer { id: retry; interval: 3000; onTriggered: pointerProcess.running = true }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "parallax-wallpaper"
            color: "#000000"

            // Layers are square sources covered over the screen, then enlarged by
            // their own travel so a full pointer sweep never exposes an edge.
            component Layer: Item {
                id: layer
                required property string source
                required property real amplitude
                readonly property real cover: Math.max(window.width / 2000, window.height / 2000) * (1 + 2 * amplitude)
                readonly property real size: 2000 * cover
                clip: false
                anchors.fill: parent
                Image {
                    source: layer.source
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    width: layer.size
                    height: layer.size
                    sourceSize: Qt.size(2000, 2000)
                    x: (window.width - layer.size) / 2 - root.motionX * layer.amplitude * window.width
                    y: -(layer.size - window.height) * root.active.focusY - root.motionY * layer.amplitude * window.width * 0.6
                }
            }

            Item {
                anchors.fill: parent
                clip: true
                Layer {
                    source: "file://" + root.share + "assets/" + root.activeId + "/back.jpg"
                    amplitude: root.active.back
                }
                Layer {
                    source: "file://" + root.share + "assets/" + root.activeId + "/front.png"
                    amplitude: root.active.front
                }
                // The compositor only reports the real cursor while it is over the
                // wallpaper, which is also the only place the cat is visible.
                MouseArea {
                    id: cursor
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    property real lastX: window.width / 2
                    property real lastY: window.height / 2
                    property int moves: 0
                    onPositionChanged: mouse => { lastX = mouse.x; lastY = mouse.y; moves++; root.cursorDebug = window.width + "x" + window.height + " " + lastX + "," + lastY + " n=" + moves; }
                }
                Neko {
                    sprite: "file://" + root.share + "assets/oneko.gif"
                    targetX: cursor.lastX
                    targetY: cursor.lastY
                }
            }
        }
    }

    IpcHandler {
        target: "parallax"
        function status(): string {
            return JSON.stringify({ cursor: root.cursorDebug, wallpaper: root.activeId, x: root.pointer.x, y: root.pointer.y });
        }
    }
}
