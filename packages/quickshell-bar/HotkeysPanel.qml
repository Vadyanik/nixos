import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var theme
    required property var compositor
    property bool opened: false
    property var selectedScreen: null
    readonly property var entries: {
        try { return JSON.parse(index.text() || "[]"); }
        catch (error) { return []; }
    }
    readonly property var filtered: entries.filter(entry =>
        (entry.shortcut + " " + entry.description).toLowerCase().includes(search.text.toLowerCase().trim()))
    screen: selectedScreen || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-hotkeys"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: surface }
    color: "transparent"
    visible: opened
    onOpenedChanged: {
        if (opened) {
            selectedScreen = Quickshell.screens.find(s => s.name === compositor.focusedMonitor) || Quickshell.screens[0];
            search.text = "";
            grid.positionViewAtBeginning();
            search.forceActiveFocus();
        }
    }
    FileView { id: index; path: Quickshell.shellPath("hotkeys.json"); blockLoading: true }
    MouseArea { anchors.fill: parent; onClicked: panel.opened = false }
    Rectangle {
        id: surface
        anchors.centerIn: parent
        width: Math.min(1500, panel.width - 64)
        height: Math.min(920, panel.height - 64)
        color: theme.panelSurface
        border.width: 1
        border.color: theme.separator
        MouseArea { anchors.fill: parent }
        Column {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 24 }
            spacing: 8
            Text {
                text: "Niri shortcuts"
                color: theme.foreground
                font.pixelSize: 26
                font.bold: true
            }
            Text {
                text: "Super = Win · H/L — columns · J/K — workspaces · Shift — move · Esc or Super+/ — close"
                color: theme.mutedForeground
                font.pixelSize: 14
            }
            TextField {
                id: search
                width: parent.width
                height: 42
                placeholderText: "Search by key or action…"
                color: theme.foreground
                placeholderTextColor: theme.mutedForeground
                font.pixelSize: 16
                selectByMouse: true
                background: Rectangle { color: theme.surfaceElevated; border.width: 1; border.color: theme.separator }
                Keys.onEscapePressed: panel.opened = false
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Slash && (event.modifiers & Qt.MetaModifier)) {
                        panel.opened = false;
                        event.accepted = true;
                    }
                }
            }
            Text {
                text: (search.text.length ? "Matches: " + panel.filtered.length + " / " : "Shortcuts: ") + panel.entries.length
                color: theme.mutedForeground
                font.pixelSize: 13
            }
        }
        GridView {
            id: grid
            anchors { top: parent.top; topMargin: 172; left: parent.left; right: parent.right; bottom: footer.top; margins: 24 }
            clip: true
            cellWidth: width / (width > 1100 ? 3 : 2)
            cellHeight: 76
            model: panel.filtered
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; rightMargin: 20; topMargin: 6 }
                    spacing: 5
                    Text { width: parent.width; text: modelData.shortcut; color: theme.primary; font.family: "monospace"; font.pixelSize: 15; wrapMode: Text.Wrap }
                    Text { width: parent.width; text: modelData.description; color: theme.foreground; font.pixelSize: 14; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                }
            }
        }
        Text {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 24 }
            text: "Full list from configuration · Scroll to browse · Workspace moves follow the window · No lock shortcut"
            color: theme.mutedForeground
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }
    }
}
