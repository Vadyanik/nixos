import QtQuick
import Quickshell
import Quickshell.Io

Column {
    id: section
    required property var theme
    required property var five
    required property var weekly
    required property var shell
    property var limits: ({})
    visible: !!window(300) || !!window(10080)
    spacing: 10
    FileView {
        id: cached
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/waybar-codex-usage.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { section.limits = JSON.parse(text()); } catch (e) { section.limits = {}; } }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    function window(duration) { return [limits.primary, limits.secondary].find(w => w?.windowDurationMins === duration) || null; }
    function countdown(reset) {
        if (!reset) return "—";
        let minutes = Math.max(0, Math.floor((reset * 1000 - clock.date.getTime()) / 60000));
        return (minutes >= 1440 ? Math.floor(minutes / 1440) + "d " : "") + Math.floor(minutes % 1440 / 60) + "h " + minutes % 60 + "m";
    }
    function details(index) {
        let lines = (five.tooltip || weekly.tooltip || "").split("\n");
        return lines.slice(index * 2, index * 2 + 2).join("\n").trim().replace(/^(5h|Weekly): /, "Score: ");
    }
    SectionHeader { width: parent.width; theme: section.theme; title: "CODEX" }
    Row {
        width: section.width
        spacing: 16
        Repeater {
            model: [{title: "5 HOUR", duration: 300, index: 0}, {title: "7 DAY", duration: 10080, index: 1}]
            Column {
                id: windowRow
                required property var modelData
                readonly property var limit: section.window(modelData.duration)
                readonly property var status: modelData.index === 0 ? section.five : section.weekly
                readonly property real remaining: limit ? Math.max(0, Math.min(100, 100 - limit.usedPercent)) : 0
                visible: !!limit
                width: (section.width - 16) / 2
                spacing: 6
                Row {
                    width: parent.width
                    Text { width: parent.width / 2; text: windowRow.modelData.title; color: section.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16; bold: true } }
                    Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: windowRow.limit ? windowRow.remaining + "% remaining" : "Unavailable"; color: section.shell.statusColor(windowRow.status); font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16 } }
                }
                Rectangle {
                    width: parent.width; height: 3; color: section.theme.separator
                    Rectangle { width: parent.width * windowRow.remaining / 100; height: 3; color: section.shell.statusColor(windowRow.status) }
                }
                Text {
                    width: parent.width
                    text: windowRow.limit ? "Used " + windowRow.limit.usedPercent + "% · Reset in " + section.countdown(windowRow.limit.resetsAt) + "\n" + Qt.formatDateTime(new Date(windowRow.limit.resetsAt * 1000), "dd.MM HH:mm") : "Codex limits are unavailable."
                    color: section.theme.mutedForeground
                    font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 }
                    wrapMode: Text.Wrap
                }
                // The original score/normalization date/Pace strings come directly from codex_usage.sh.
                Text { width: parent.width; text: section.details(windowRow.modelData.index); color: section.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16 } wrapMode: Text.Wrap }
                Text {
                    visible: !!windowRow.status.class && windowRow.status.class !== "full"
                    text: windowRow.status.class === "excess" ? "EXCESS" : (windowRow.status.class || "").toUpperCase()
                    color: section.shell.statusColor(windowRow.status)
                    font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14; bold: true }
                }
                Item { width: 1; height: 8 }
            }
        }
    }
}
