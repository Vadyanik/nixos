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
    readonly property int maxEntries: 40
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
    // Typing is grouped into words: plain characters (Shift only changes case)
    // join the newest word entry. A word ends on Space, on any other key or
    // hotkey, when focus moves to another window or field, on a mouse click,
    // or after a pause. Hotkeys and special keys stay separate entries whose
    // keys are drawn apart, and repeats of them fold into "×N".
    readonly property int wordPause: 3000
    property bool wordOpen: false
    property real lastTyped: 0
    readonly property var focusedWindowId: compositor.focusedWindow ? compositor.focusedWindow.id : null
    onFocusedWindowIdChanged: wordOpen = false

    function addEntry(pieces) {
        const joined = pieces.join(separator);
        const first = entryModel.count > 0 ? entryModel.get(0) : null;
        if (first && !first.word && first.parts === joined) {
            entryModel.setProperty(0, "count", first.count + 1);
            entryModel.setProperty(0, "born", Date.now());
        } else {
            entryModel.insert(0, {parts: joined, count: 1, born: Date.now(), word: false});
            trim();
        }
    }
    function trim() {
        if (entryModel.count > maxEntries) entryModel.remove(maxEntries, entryModel.count - maxEntries);
    }
    function typeCharacter(text) {
        const time = Date.now();
        const first = entryModel.count > 0 ? entryModel.get(0) : null;
        if (wordOpen && first && first.word && time - lastTyped < wordPause) {
            entryModel.setProperty(0, "parts", first.parts + text);
            entryModel.setProperty(0, "born", time);
        } else {
            entryModel.insert(0, {parts: text, count: 1, born: time, word: true});
            trim();
        }
        wordOpen = true;
        lastTyped = time;
    }
    // Backspace inside the word being typed edits it; returns false otherwise.
    function eraseCharacter() {
        const first = entryModel.count > 0 ? entryModel.get(0) : null;
        if (!wordOpen || !first || !first.word) return false;
        const characters = Array.from(first.parts);
        characters.pop();
        if (characters.length) {
            entryModel.setProperty(0, "parts", characters.join(""));
            entryModel.setProperty(0, "born", Date.now());
        } else {
            entryModel.remove(0);
            wordOpen = false;
        }
        lastTyped = Date.now();
        return true;
    }
    function push(chord) {
        const others = chord.mods.filter(m => m !== "shift");
        const shift = others.length < chord.mods.length;
        if (!chord.key) {
            if (others.length === 0) return;  // a lone Shift tap only changes case
            wordOpen = false;
            addEntry(parts(chord));
        } else if (others.length === 0 && chord.key.length === 1) {
            typeCharacter(keyText(chord.key, shift));
        } else if (chord.mods.length === 0 && chord.key === "space") {
            wordOpen = false;  // the gap between entries is the space
        } else if (chord.mods.length === 0 && chord.key === "backspace" && eraseCharacter()) {
        } else {
            wordOpen = false;
            addEntry(parts(chord));
        }
        now = Date.now();
    }
    function snapshot() {
        return Array.from({length: entryModel.count}, (_, i) => entryModel.get(i).parts.split(separator).join("") + (entryModel.get(i).count > 1 ? " x" + entryModel.get(i).count : ""));
    }
    function handle(line) {
        let event;
        try { event = JSON.parse(line); } catch (e) { return; }
        if (event.type === "state") current = {mods: event.mods, key: event.key, secret: event.secret === true};
        else if (event.type === "chord") push(event);
        else if (event.type === "boundary") wordOpen = false;
        if (current.secret) wordOpen = false;
    }

    onOpenedChanged: { entryModel.clear(); wordOpen = false; current = {mods: [], key: "", secret: false}; }

    ListModel { id: entryModel }
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
        command: ["python3", Quickshell.shellPath("scripts/keystrokes.py")]
        running: panel.opened
        stdout: SplitParser { onRead: line => panel.handle(line) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Keystrokes:", text.trim()) }
    }
}
