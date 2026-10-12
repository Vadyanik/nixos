import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Only this adapter depends on compositor APIs. The same visual shell can run
// in either session; Niri's event stream includes the initial complete state.
Scope {
    id: adapter
    readonly property bool isNiri: !!Quickshell.env("NIRI_SOCKET")
    property var niriWorkspaces: []
    property var niriWindows: []
    property var keyboardLayouts: ({names: [], current_idx: 0})
    property string hyprLanguage: ""
    readonly property string language: isNiri ? (keyboardLayouts.names[keyboardLayouts.current_idx] || "") : hyprLanguage
    readonly property string focusedMonitor: isNiri
        ? (niriWorkspaces.find(w => w.is_focused)?.output || "")
        : (Hyprland.focusedMonitor?.name || "")
    readonly property var focusedWindow: isNiri
        ? (niriWindows.find(w => w.is_focused) || null) : (Hyprland.activeToplevel?.lastIpcObject || null)
    readonly property var workspaces: isNiri
        ? niriWorkspaces.filter(w => w.is_active || (w.name !== "magic" && niriWindows.some(window => window.workspace_id === w.id))).slice().sort((a, b) => String(a.output).localeCompare(String(b.output)) || a.idx - b.idx).map(w => ({
            id: w.id, label: w.name || String(w.idx), name: w.name || String(w.idx),
            active: w.is_active, urgent: w.is_urgent || false, monitor: {name: w.output}
        }))
        : Hyprland.workspaces.values.map(w => ({
            id: w.id, label: String(w.id), name: w.name,
            active: w.active, urgent: w.urgent, monitor: {name: w.monitor?.name}
        }))

    function activateWorkspace(workspace) {
        if (isNiri) {
            // JSON uses the stable ID even after Niri reorders workspace indices.
            Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/niri_focus_workspace.py"), String(workspace.id)]);
        } else {
            Hyprland.dispatch("workspace " + workspace.id);
        }
    }
    function event(line) {
        try {
            const e = JSON.parse(line);
            if (e.WorkspacesChanged) niriWorkspaces = e.WorkspacesChanged.workspaces;
            else if (e.WorkspaceActivated) {
                const activated = niriWorkspaces.find(w => w.id === e.WorkspaceActivated.id);
                niriWorkspaces = niriWorkspaces.map(w => Object.assign({}, w, {
                    is_active: activated && w.output === activated.output ? w.id === activated.id : w.is_active,
                    is_focused: e.WorkspaceActivated.focused ? w.id === e.WorkspaceActivated.id : w.is_focused
                }));
            } else if (e.WorkspaceUrgencyChanged) {
                niriWorkspaces = niriWorkspaces.map(w => w.id === e.WorkspaceUrgencyChanged.id ? Object.assign({}, w, {is_urgent: e.WorkspaceUrgencyChanged.urgent}) : w);
            } else if (e.WindowsChanged) niriWindows = e.WindowsChanged.windows;
            else if (e.WindowOpenedOrChanged) {
                const updated = e.WindowOpenedOrChanged.window;
                niriWindows = niriWindows.filter(w => w.id !== updated.id).map(w => updated.is_focused ? Object.assign({}, w, {is_focused: false}) : w).concat([updated]);
            } else if (e.WindowClosed) niriWindows = niriWindows.filter(w => w.id !== e.WindowClosed.id);
            else if (e.WindowFocusChanged) niriWindows = niriWindows.map(w => Object.assign({}, w, {is_focused: w.id === e.WindowFocusChanged.id}));
            else if (e.KeyboardLayoutsChanged) keyboardLayouts = e.KeyboardLayoutsChanged.keyboard_layouts;
            else if (e.KeyboardLayoutSwitched) keyboardLayouts = Object.assign({}, keyboardLayouts, {current_idx: e.KeyboardLayoutSwitched.idx});
        } catch (error) { console.warn("Niri event", error); }
    }
    Process {
        id: niriEvents
        command: ["niri", "msg", "--json", "event-stream"]
        running: adapter.isNiri
        stdout: SplitParser { onRead: line => adapter.event(line) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Niri IPC:", text.trim()) }
        onExited: if (adapter.isNiri) reconnect.restart()
    }
    Timer { id: reconnect; interval: 1500; onTriggered: niriEvents.running = true }
    Process {
        id: hyprKeyboard
        command: ["hyprctl", "devices", "-j"]
        running: !adapter.isNiri
        stdout: StdioCollector { onStreamFinished: {
            try { adapter.hyprLanguage = (JSON.parse(text).keyboards.find(k => k.main) || {}).active_keymap || ""; }
            catch (error) { console.warn("Keyboard state", error); }
        } }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!adapter.isNiri && (event.name === "activelayout" || event.name === "configreloaded")) hyprKeyboard.running = true;
        }
    }
}
