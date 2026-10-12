import QtQuick
import Quickshell

Column {
    id: section
    required property var theme
    required property var service
    property var expandedApps: ({})
    readonly property var groups: {
        let revision = service.historyRevision;
        let result = [];
        let byApp = new Map();
        for (let i = 0; i < service.history.count; i++) {
            let row = service.history.get(i);
            let group = byApp.get(row.app);
            if (!group) { group = {app: row.app, desktop: row.desktop || "", icon: row.icon, entries: []}; byApp.set(row.app, group); result.push(group); }
            group.entries.push({id: row.id, title: row.title, body: row.body, time: row.time});
        }
        return result;
    }
    function toggleGroup(app) {
        let expanded = Object.assign({}, expandedApps);
        expanded[app] = expandedApps[app] !== true;
        expandedApps = expanded;
    }
    function snapshot() { return groups.map(g => { let expanded = expandedApps[g.app] === true; return {app: g.app, count: g.entries.length, expanded: expanded, visibleIds: (expanded ? g.entries : g.entries.slice(0, 1)).map(e => e.id)}; }); }
    visible: service.history.count > 0
    spacing: 8
    Row {
        width: parent.width
        SectionHeader { width: parent.width - clear.width - 8; theme: section.theme; title: "NOTIFICATIONS" }
        TextAction { id: clear; theme: section.theme; text: "CLEAR"; enabled: section.service.history.count > 0; onClicked: section.service.clear() }
    }
    Repeater {
        model: section.groups
        Item {
            id: group
            required property var modelData
            width: section.width
            height: contents.height
            readonly property bool expanded: section.expandedApps[modelData.app] === true
            Column {
                id: contents
                width: parent.width
                spacing: 5
                Item {
                    width: parent.width
                    height: 20
                    Row {
                        anchors.fill: parent
                        spacing: 8
                        Item {
                            width: 18; height: 20
                            Image {
                                id: icon
                                anchors.centerIn: parent; width: 18; height: 18; asynchronous: true
                                source: {
                                    if (group.modelData.icon) return group.modelData.icon.startsWith("/") || group.modelData.icon.includes(":") ? group.modelData.icon : Quickshell.iconPath(group.modelData.icon);
                                    let desktop = group.modelData.desktop.replace(/\.desktop$/i, "");
                                    if (/chatgpt/i.test(group.modelData.app + " " + desktop)) desktop = "codex-desktop";
                                    return Quickshell.iconPath(desktop || group.modelData.app.toLowerCase());
                                }
                            }
                            Text { anchors.centerIn: parent; visible: icon.status !== Image.Ready; text: "▣"; color: section.theme.accent; font.pixelSize: 15 }
                        }
                        Text { width: parent.width - 100; text: group.modelData.app; elide: Text.ElideRight; color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                        Text { visible: group.modelData.entries.length > 1; text: group.modelData.entries.length + (group.expanded ? " ▴" : " ▾"); color: section.theme.accent; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) section.service.openNotification(group.modelData.entries[0].id);
                            else if (mouse.button === Qt.RightButton && group.modelData.entries.length > 1) section.toggleGroup(group.modelData.app);
                            else if (mouse.button === Qt.MiddleButton) section.service.dismissGroup(group.modelData.app);
                        }
                    }
                }
                Repeater {
                    model: group.expanded ? group.modelData.entries : group.modelData.entries.slice(0, 1)
                    Item {
                        id: entry
                        required property var modelData
                        width: contents.width
                        height: entryContent.implicitHeight
                        Column {
                        id: entryContent
                        width: parent.width
                        spacing: 5
                        Row {
                            width: parent.width
                            spacing: 8
                            Text { width: parent.width - 92; text: entry.modelData.title; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 1; elide: Text.ElideRight; color: section.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16; bold: true } }
                            Text { text: Qt.formatDateTime(new Date(entry.modelData.time), "HH:mm"); color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                        }
                        Text { width: parent.width; visible: text.length > 0; text: entry.modelData.body; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                        Rectangle { width: parent.width; height: 1; color: section.theme.separator }
                        Item { height: 5; width: 1 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) section.service.openNotification(entry.modelData.id);
                                else if (mouse.button === Qt.MiddleButton) section.service.dismiss(entry.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
