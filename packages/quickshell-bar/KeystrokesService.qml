import QtQuick
import Quickshell
import Quickshell.Io

// Echoes pressed keys and chords; the bar renders `current` and `history`.
// Modifiers and long key names are shown as icons. The evdev reader only
// runs while the panel is open.
Item {
    id: panel
    required property var compositor
    property bool opened: false
    // Show RU/UA layout keys as the Latin keys they sit on.
    property bool latinKeys: false
    property var current: ({mods: [], key: ""})
    property var history: []
    readonly property int maxHistory: 40
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
            if (!latinKeys && table && table[name]) return table[name].toUpperCase();
        }
        if (name.startsWith("kp")) return name.slice(2).toUpperCase();
        return name.toUpperCase();
    }
    function label(chord) {
        const parts = chord.mods.map(glyph);
        if (chord.key) parts.push(glyph(chord.key));
        return parts.join("");
    }
    // Newest first. The bar shows as many entries as fit and hides the rest,
    // so the oldest ones drop off the right edge one at a time.
    // Entries keep the text rendered when they were typed, so switching
    // latinKeys later does not rewrite what is already on the bar.
    function push(chord) {
        const text = label(chord);
        const last = history[0];
        if (last && last.text === text)
            history = [{text: text, count: last.count + 1}].concat(history.slice(1));  // fold repeats into "A ×3"
        else
            history = [{text: text, count: 1}].concat(history).slice(0, maxHistory);
        idle.restart();
    }
    function handle(line) {
        let event;
        try { event = JSON.parse(line); } catch (e) { return; }
        if (event.type === "state") current = {mods: event.mods, key: event.key};
        else if (event.type === "chord") push(event);
    }

    onOpenedChanged: if (opened) { history = []; current = {mods: [], key: ""}; }

    // Fade old history away once typing stops.
    Timer { id: idle; interval: 20000; onTriggered: panel.history = [] }
    Process {
        command: ["python3", Quickshell.shellPath("scripts/keystrokes.py")]
        running: panel.opened
        stdout: SplitParser { onRead: line => panel.handle(line) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Keystrokes:", text.trim()) }
    }
}
