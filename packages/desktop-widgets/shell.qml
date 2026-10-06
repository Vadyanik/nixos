import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var bars: []
    property var frame: ({ cols: 120, rows: 35, lines: [] })
    readonly property var modes: ["lavat", "cbonsai", "pipes", "aafire", "genact", "unimatrix"]
    property int modeIndex: 0
    function nextMode(step) {
        modeIndex = (modeIndex + step + modes.length) % modes.length;
        frame = { cols: 120, rows: 35, lines: [] };
        animation.running = false;
        animationRestart.start();
    }
    function randomMode() {
        nextMode(1 + Math.floor(Math.random() * (modes.length - 1)));
    }
    IpcHandler {
        target: "animations"
        function next(): void { root.nextMode(1); }
        function previous(): void { root.nextMode(-1); }
        function random(): void { root.randomMode(); }
        function current(): string { return root.modes[root.modeIndex]; }
    }
    Timer { id: animationRestart; interval: 100; onTriggered: animation.running = true }
    property var caption: ({ width: 1513, left: 96, bottom: 161, sourceWidth: 3840, title: "", sourceId: "" })
    onCaptionChanged: {
        if (modes[modeIndex] === "cbonsai") {
            animation.running = false;
            animationRestart.start();
        }
    }
    readonly property var palette: {
        let result = {primary: "#96ccf8", surface: "#1c2024"};
        let css = paletteFile.text();
        let re = /@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6});/g;
        let match;
        while ((match = re.exec(css)) !== null) result[match[1]] = match[2];
        return result;
    }
    readonly property color ink: Qt.alpha(palette.primary, 0.78)
    readonly property color backdrop: Qt.alpha(palette.surface, 0.45)

    FileView {
        id: paletteFile
        path: Quickshell.env("HOME") + "/.config/quickshell/bar/colors.css"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/space-wallpaper/shuffle.json"
        watchChanges: true
        onFileChanged: { reload(); captionMeasure.running = true; }
    }
    FileView {
        path: "/etc/space-wallpaper/settings.json"
        watchChanges: true
        onFileChanged: { reload(); captionMeasure.running = true; }
    }
    Process {
        id: captionMeasure
        command: ["@python@", root.configDir + "caption-size.py"]
        running: true
        stdout: SplitParser {
            onRead: data => root.caption = JSON.parse(data)
        }
    }
    readonly property string configDir: "@configDir@"

    Process {
        command: ["/run/current-system/sw/bin/cava", "-p", root.configDir + "cava.conf"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                let values = data.split(";").filter(v => v.trim().length > 0).map(Number);
                if (values.length === 128 && values.every(v => Number.isFinite(v)))
                    root.bars = values;
            }
        }
    }
    Process {
        id: animation
        command: ["@python@", root.configDir + "animation-bridge.py", root.modes[root.modeIndex], root.modes[root.modeIndex] === "cbonsai" ? (root.caption.sourceId || "") : ""]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.frame = JSON.parse(data);
                lavaCanvas.requestPaint();
            }
        }
    }

    PanelWindow {
        id: cavaWindow
        anchors { left: true; bottom: true }
        readonly property real wallpaperScale: screen.width / root.caption.sourceWidth
        margins { left: Math.round(root.caption.left * cavaWindow.wallpaperScale); bottom: Math.round(root.caption.bottom * cavaWindow.wallpaperScale) + 24 }
        implicitWidth: Math.round(root.caption.width * wallpaperScale)
        implicitHeight: 160
        color: root.backdrop
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "desktop-cava"
        mask: Region {}

        Canvas {
            id: cavaCanvas
            anchors.fill: parent
            Connections {
                target: root
                function onBarsChanged() { cavaCanvas.requestPaint(); }
                function onInkChanged() { cavaCanvas.requestPaint(); }
            }
            onWidthChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.ink.toString();
                const barWidth = 26;
                const gap = 5;
                const count = Math.max(1, Math.floor((width - 8 + gap) / (barWidth + gap)));
                const left = (width - (count * barWidth + (count - 1) * gap)) / 2;
                for (let i = 0; i < count; i++) {
                    const start = Math.floor(i * 128 / count);
                    const end = Math.max(start + 1, Math.floor((i + 1) * 128 / count));
                    let level = 0;
                    for (let j = start; j < end; j++) level += root.bars[j] || 0;
                    const h = Math.max(2, Math.min(1000, level / (end - start)) / 1000 * 136);
                    ctx.fillRect(left + i * (barWidth + gap), 148 - h, barWidth, h);
                }
            }
        }
    }

    PanelWindow {
        anchors { right: true; bottom: true }
        margins { right: 64; bottom: 64 }
        implicitWidth: 720
        implicitHeight: 420
        color: root.backdrop
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "desktop-animations"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) root.randomMode();
                else root.nextMode(mouse.button === Qt.RightButton ? -1 : 1);
            }
        }
        Canvas {
            id: lavaCanvas
            anchors.fill: parent
            Connections {
                target: root
                function onInkChanged() { lavaCanvas.requestPaint(); }
            }
            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.ink.toString();
                const cellW = width / root.frame.cols;
                const cellH = height / root.frame.rows;
                const ansi = {black: "#252830", red: "#ef8b91", green: "#a6d99a", brown: "#e5c890", blue: "#8cbcf3", magenta: "#cb9eed", cyan: "#91d7df", white: "#e8e8ed"};
                function color(value) {
                    if (value === "default" || value === "foreground") return root.ink.toString();
                    return ansi[value] || (value.length === 6 ? "#" + value : root.ink.toString());
                }
                ctx.textBaseline = "top";
                for (let y = 0; y < root.frame.lines.length; y++) {
                    let x = 0;
                    for (const run of root.frame.lines[y]) {
                        ctx.font = (run[3] ? "bold " : "") + Math.floor(cellH) + "px monospace";
                        ctx.fillStyle = color(run[1]);
                        for (const ch of Array.from(run[0])) {
                            if (run[2] !== "default") {
                                ctx.fillStyle = color(run[2]);
                                ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
                                ctx.fillStyle = color(run[1]);
                            }
                            if (ch === "█") ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
                            else if (ch === "▀") ctx.fillRect(x * cellW, y * cellH, cellW, cellH / 2);
                            else if (ch === "▄") ctx.fillRect(x * cellW, y * cellH + cellH / 2, cellW, cellH / 2);
                            else if (ch !== " ") ctx.fillText(ch, x * cellW, y * cellH);
                            x++;
                        }
                    }
                }
            }
        }
    }
}
