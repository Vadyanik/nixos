import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Quick shell under the bar that echoes pressed keys and chords.
// Modifiers and long key names are shown as icons. The evdev reader only
// runs while the panel is open.
PanelWindow {
    id: panel
    required property var compositor
    required property var theme
    property bool opened: false
    property var current: ({mods: [], key: ""})
    property var history: []
    readonly property int maxHistory: 7
    readonly property var glyphs: ({
        super: "\uf313", ctrl: "󰘴", alt: "󰘵", altgr: "󰘵", shift: "󰘶",
        enter: "󰌑", kpenter: "󰌑", backspace: "󰁮", tab: "󰌒", esc: "󱊷", space: "󱁐",
        caps: "󰪛", delete: "󰆴", insert: "󰏫", menu: "󰍜", print: "󰹑",
        up: "\uf062", down: "\uf063", left: "\uf060", right: "\uf061",
        home: "󰜷", end: "󰜮", pageup: "󰶣", pagedown: "󰶡",
        mute: "󰝟", volumedown: "󰖀", volumeup: "󰕾", playpause: "󰐎",
        next: "󰒭", previous: "󰒮", brightnessdown: "󰃞", brightnessup: "󰃠",
        pause: "󰏤", numlock: "󰎠", scrolllock: "󰌐"
    })
    // Physical (US) key -> letter on the active layout; evdev reports positions only.
    readonly property var russian: ({q: "й", w: "ц", e: "у", r: "к", t: "е", y: "н", u: "г", i: "ш", o: "щ", p: "з", "[": "х", "]": "ъ",
        a: "ф", s: "ы", d: "в", f: "а", g: "п", h: "р", j: "о", k: "л", l: "д", ";": "ж", "'": "э", z: "я", x: "ч", c: "с", v: "м",
        b: "и", n: "т", m: "ь", ",": "б", ".": "ю", "/": ".", "`": "ё"})
    readonly property var ukrainian: Object.assign({}, russian, {s: "і", "]": "ї", "'": "є", "`": "'", "\\": "ґ"})
    readonly property string layoutName: compositor.language || ""
    function glyph(name) {
        if (glyphs[name]) return glyphs[name];
        if (name.length === 1) {
            const table = layoutName.startsWith("Russian") ? russian : (layoutName.startsWith("Ukrainian") ? ukrainian : null);
            if (table && table[name]) return table[name].toUpperCase();
        }
        if (name.startsWith("kp")) return name.slice(2).toUpperCase();
        return name.toUpperCase();
    }
    function label(chord) {
        const parts = chord.mods.map(glyph);
        if (chord.key) parts.push(glyph(chord.key));
        return parts.join("  ");
    }
    function push(chord) {
        const last = history[0];
        history = [{mods: chord.mods, key: chord.key, count: 1}].concat(history).slice(0, maxHistory);
        if (last && last.key === chord.key && last.mods.join() === chord.mods.join()) {
            // Fold repeats ("A ×3") instead of filling the list.
            history = [{mods: last.mods, key: last.key, count: last.count + 1}].concat(history.slice(2));
        }
        idle.restart();
    }
    function handle(line) {
        let event;
        try { event = JSON.parse(line); } catch (e) { return; }
        if (event.type === "state") current = {mods: event.mods, key: event.key};
        else if (event.type === "chord") push(event);
    }

    screen: Quickshell.screens.find(s => s.name === compositor.focusedMonitor) || Quickshell.screens[0]
    anchors { top: true }
    margins { top: 32 }
    implicitWidth: 460
    implicitHeight: surface.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-keystrokes"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: surface }
    color: "transparent"
    visible: opened
    onOpenedChanged: if (opened) { history = []; current = {mods: [], key: ""}; }

    // Fade old history away once typing stops.
    Timer { id: idle; interval: 6000; onTriggered: panel.history = [] }
    Process {
        command: ["python3", Quickshell.shellPath("scripts/keystrokes.py")]
        running: panel.opened
        stdout: SplitParser { onRead: line => panel.handle(line) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Keystrokes:", text.trim()) }
    }
    Rectangle {
        id: surface
        width: parent.width
        height: column.height + 28
        color: panel.theme.panelSurface
        border { width: 1; color: panel.theme.separator }
        Column {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: panel.current.mods.length || panel.current.key ? panel.label(panel.current) : "keys"
                color: panel.current.mods.length || panel.current.key ? panel.theme.accent : panel.theme.mutedForeground
                font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 30; bold: true }
            }
            Repeater {
                model: panel.history
                Text {
                    required property var modelData
                    required property int index
                    width: column.width
                    horizontalAlignment: Text.AlignHCenter
                    text: panel.label(modelData) + (modelData.count > 1 ? "  ×" + modelData.count : "")
                    color: panel.theme.foreground
                    opacity: Math.max(0.15, 0.75 - index * 0.12)
                    font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 }
                }
            }
        }
    }
}
