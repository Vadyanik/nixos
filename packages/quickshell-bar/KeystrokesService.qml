import QtQuick
import Quickshell
import Quickshell.Io

// Echoes pressed keys and chords; the bar renders `current` and `entries`.
// Modifiers and long key names are shown as icons. The evdev reader only
// runs while the echo is open.
Item {
    id: panel
    required property var compositor
    property bool opened: false
    // Show RU/UA layout keys as the Latin keys they sit on.
    property bool latinKeys: false
    property var current: ({mods: [], key: ""})
    readonly property alias entries: entryModel
    readonly property int maxEntries: 40
    readonly property string separator: "\u001f"
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
    readonly property var usShift: ({"1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
        "-": "_", "=": "+", "[": "{", "]": "}", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~", "\\": "|"})
    readonly property var cyrillicShift: ({"2": "\"", "3": "№", "4": ";", "5": "%", "6": ":", "7": "?", "/": ",", "\\": "/"})
    readonly property var ukrainianShift: Object.assign({}, cyrillicShift, {"\\": "Ґ"})
    readonly property string layoutName: compositor.language || ""
    function layoutTable() {
        if (latinKeys) return null;
        return layoutName.startsWith("Russian") ? russian : (layoutName.startsWith("Ukrainian") ? ukrainian : null);
    }
    // Text of a single key. Letters stay lowercase unless `shifted`.
    function keyText(name, shifted) {
        if (glyphs[name]) return glyphs[name];
        if (name.length !== 1) return name.startsWith("kp") ? name.slice(2).toUpperCase() : name.toUpperCase();
        const table = layoutTable();
        const base = table && table[name] ? table[name] : name;
        if (!shifted) return base;
        const symbols = table === russian ? cyrillicShift : (table === ukrainian ? ukrainianShift : usShift);
        return symbols[name] || (base.toUpperCase() !== base ? base.toUpperCase() : (usShift[name] || base));
    }
    // Pieces of one chord. Shift alone on a character key becomes its capital or
    // symbol (n -> N, 1 -> !) instead of a shift icon; with other modifiers it stays an icon.
    function parts(chord) {
        const others = chord.mods.filter(m => m !== "shift");
        const shift = chord.mods.length > others.length;
        const absorb = shift && others.length === 0 && chord.key.length === 1;
        const result = absorb ? [] : chord.mods.map(m => glyphs[m]);
        if (chord.key) result.push(keyText(chord.key, absorb));
        return result;
    }
    function push(chord) {
        const joined = parts(chord).join(separator);
        if (entryModel.count > 0 && entryModel.get(0).parts === joined) {
            entryModel.setProperty(0, "count", entryModel.get(0).count + 1);
        } else {
            entryModel.insert(0, {parts: joined, count: 1});
            if (entryModel.count > maxEntries) entryModel.remove(maxEntries, entryModel.count - maxEntries);
        }
        idle.restart();
        drain.stop();
    }
    function snapshot() {
        return Array.from({length: entryModel.count}, (_, i) => entryModel.get(i).parts.split(separator).join("") + (entryModel.get(i).count > 1 ? " x" + entryModel.get(i).count : ""));
    }
    function handle(line) {
        let event;
        try { event = JSON.parse(line); } catch (e) { return; }
        if (event.type === "state") current = {mods: event.mods, key: event.key};
        else if (event.type === "chord") push(event);
    }

    onOpenedChanged: if (opened) { entryModel.clear(); current = {mods: [], key: ""}; }

    ListModel { id: entryModel }
    // After a pause the oldest entries fade out one by one instead of vanishing together.
    Timer { id: idle; interval: 8000; onTriggered: drain.start() }
    Timer {
        id: drain
        interval: 300
        repeat: true
        onTriggered: entryModel.count > 0 ? entryModel.remove(entryModel.count - 1) : stop()
    }
    Process {
        command: ["python3", Quickshell.shellPath("scripts/keystrokes.py")]
        running: panel.opened
        stdout: SplitParser { onRead: line => panel.handle(line) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Keystrokes:", text.trim()) }
    }
}
