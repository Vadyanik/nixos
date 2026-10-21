import QtQuick
import Quickshell
import Quickshell.Io

// Echoes pressed keys and chords; the bar renders `current` and `entries`.
// Modifiers and long key names are shown as icons. The evdev reader only
// runs while the echo is open.
Item {
    id: panel
    required property var compositor
    property bool opened: true  // on by default; toggled by clicking its area in the bar
    // Show RU/UA layout keys as the Latin keys they sit on; right click in the bar toggles it.
    property bool latinKeys: false
    property var current: ({mods: [], key: "", secret: false})
    readonly property alias entries: entryModel
    readonly property int maxEntries: 300
    // Entries stay fully visible for fadeDelay ms, then fade linearly and are
    // dropped once they are lifetime ms old.
    readonly property int fadeDelay: 5000
    readonly property int lifetime: 20000
    property real now: Date.now()
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
    // Text of a single key. Letters stay lowercase unless `shifted`; `latin`
    // ignores the RU/UA layout (hotkeys are bound to the Latin keys).
    function keyText(name, shifted, latin) {
        if (glyphs[name]) return glyphs[name];
        if (name.length !== 1) return name.startsWith("kp") ? name.slice(2).toUpperCase() : name.toUpperCase();
        const table = latin ? null : layoutTable();
        const base = table && table[name] ? table[name] : name;
        if (!shifted) return base;
        const symbols = table === russian ? cyrillicShift : (table === ukrainian ? ukrainianShift : usShift);
        return symbols[name] || (base.toUpperCase() !== base ? base.toUpperCase() : (usShift[name] || base));
    }
    // Pieces of one chord. Shift alone on a character key becomes its capital or
    // symbol (n -> N, 1 -> !) instead of a shift icon; with other modifiers it stays
    // an icon and the key is shown in Latin.
    function parts(chord) {
        const others = chord.mods.filter(m => m !== "shift");
        const shift = chord.mods.length > others.length;
        const absorb = shift && others.length === 0 && chord.key.length === 1;
        const result = absorb ? [] : chord.mods.map(m => glyphs[m]);
        if (chord.key) result.push(keyText(chord.key, absorb, others.length > 0));
        return result;
    }
    // One continuous stream, newest first: every key is its own entry and
    // entries sit flush. A real Space press adds a space. A combination (two or
    // more keys pressed together) is one entry with a gap on both sides. Shift on
    // a character only changes it (n -> N), so that stays a single key.
    // Repeats fold into "×N": combinations and special keys from the second press,
    // plain characters from the third, so double letters in words stay as typed.
    function push(chord) {
        const pieces = parts(chord);
        if (!pieces.length || (pieces.length === 1 && chord.key === "" && chord.mods[0] === "shift")) return;  // lone Shift tap
        const space = chord.mods.length === 0 && chord.key === "space";
        const text = space ? " " : pieces.join(separator);
        const combo = pieces.length > 1;
        const character = !combo && (space || chord.key.length === 1);
        const time = Date.now();
        const same = i => i < entryModel.count && entryModel.get(i).parts === text && entryModel.get(i).combo === combo;
        if (same(0) && (!character || entryModel.get(0).count >= 3)) {
            entryModel.setProperty(0, "count", entryModel.get(0).count + 1);
            entryModel.setProperty(0, "born", time);
        } else if (character && same(0) && same(1) && entryModel.get(0).count === 1 && entryModel.get(1).count === 1) {
            entryModel.remove(0);  // third in a row: fold the two plain ones into "×3"
            entryModel.setProperty(0, "count", 3);
            entryModel.setProperty(0, "born", time);
        } else {
            entryModel.insert(0, {parts: text, combo: combo, count: 1, born: time});
            if (entryModel.count > maxEntries) entryModel.remove(maxEntries, entryModel.count - maxEntries);
        }
        now = time;
    }
    function snapshot() {
        return Array.from({length: entryModel.count}, (_, i) => entryModel.get(i)).reverse()
            .map(e => {
                const text = e.parts.split(separator).join("+") + (e.count > 1 ? "×" + e.count : "");
                return e.combo || e.count > 1 ? " " + text + " " : text;
            }).join("");
    }
    function handle(line) {
        let event;
        try { event = JSON.parse(line); } catch (e) { return; }
        if (event.type === "state") current = {mods: event.mods, key: event.key, secret: event.secret === true};
        else if (event.type === "chord") push(event);
    }

    onOpenedChanged: { entryModel.clear(); current = {mods: [], key: "", secret: false}; }

    ListModel { id: entryModel }
    Timer { id: restartReader; interval: 2000; onTriggered: if (panel.opened) reader.running = true }
    // One clock drives every entry's fade and drops the ones past their lifetime.
    Timer {
        interval: 100
        repeat: true
        running: entryModel.count > 0
        onTriggered: {
            panel.now = Date.now();
            while (entryModel.count > 0 && panel.now - entryModel.get(entryModel.count - 1).born >= panel.lifetime)
                entryModel.remove(entryModel.count - 1);
        }
    }
    Process {
        id: reader
        command: ["python3", Quickshell.shellPath("scripts/keystrokes.py")]
        running: panel.opened
        // Restart after a crash instead of silently showing nothing.
        onExited: (code, status) => { if (panel.opened) restartReader.restart(); }
        stdout: SplitParser { onRead: line => panel.handle(line) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Keystrokes:", text.trim()) }
    }
}
