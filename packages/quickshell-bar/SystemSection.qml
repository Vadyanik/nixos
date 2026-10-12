import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Pipewire

Column {
    id: section
    required property var theme
    required property var metrics
    required property var disk
    required property var shell
    required property var boot
    required property var stt
    required property var bluetooth
    readonly property var audio: Pipewire.defaultAudioSink?.audio
    function adjustVolume(steps) { if (section.audio) section.audio.volume = Math.max(0, Math.min(1, section.audio.volume + steps * 0.02)); }
    function openSettings(command) { section.shell.controlOpen = false; section.shell.run(command); }
    spacing: 8
    function snapshot() { return {volumeWidth: volumeButton.width, sliderX: volumeSlider.x, volumeHeight: volumeRow.height, diskWidth: section.width}; }
    function rate(value) { if (value === null || value === undefined) return "—"; return value >= 1048576 ? (value / 1048576).toFixed(1) + " MiB/s" : (value / 1024).toFixed(1) + " KiB/s"; }
    SectionHeader { width: parent.width; theme: section.theme; title: "SYSTEM" }
    GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: 12
        rowSpacing: 12
        Repeater {
            model: [ {label: "CPU", value: metrics?.cpu == null ? "—" : metrics.cpu + "%"}, {label: "GPU", value: metrics?.gpu == null ? "—" : metrics.gpu + "%"}, {label: "RAM", value: metrics?.ramUsed == null ? "—" : metrics.ramUsed + " / " + metrics.ramTotal + " GiB"}, {label: "DISK", value: (disk?.mounts || []).map(m => m.path + " " + m.freePercent + "%").join("  ") || "—"}, {label: "NET", value: "↓ " + section.rate(metrics?.rx) + "  ↑ " + section.rate(metrics?.tx)}, {label: "BLUETOOTH", value: (section.bluetooth.name || "Device") + " · " + (section.bluetooth.battery == null ? "—" : section.bluetooth.battery + "%")} ]
            Column {
                required property var modelData
                visible: modelData.label !== "BLUETOOTH" || section.bluetooth?.connected === true
                Layout.minimumWidth: (section.width - 12) / 2
                Layout.maximumWidth: (section.width - 12) / 2
                Layout.preferredWidth: (section.width - 12) / 2
                spacing: 3
                Text { text: modelData.label; color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                Text { text: modelData.value; elide: Text.ElideRight; color: modelData.label === "BLUETOOTH" && section.bluetooth.battery !== null && section.bluetooth.battery <= 15 ? section.theme.error : section.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16 } }
            }
        }
    }
    RowLayout {
        id: volumeRow
        width: parent.width
        implicitHeight: 32
        TextAction { id: volumeButton; theme: section.theme; Layout.minimumWidth: 112; Layout.preferredWidth: 112; Layout.maximumWidth: 112; Layout.preferredHeight: 32; Layout.alignment: Qt.AlignVCenter; text: "VOL " + (section.audio ? (section.audio.muted ? "MUTE" : Math.round(section.audio.volume * 100) + "%") : "—"); acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: section.openSettings("pavucontrol"); onRightClicked: section.openSettings("blueman-manager") }
        Slider {
            id: volumeSlider
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter
            from: 0; to: 1
            stepSize: 0.02
            value: section.audio?.volume || 0
            enabled: !!section.audio
            onMoved: section.audio.volume = value
            background: Rectangle { x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - 1; width: parent.availableWidth; height: 2; color: section.theme.separator; Rectangle { width: parent.width * parent.parent.visualPosition; height: 2; color: section.theme.accent } }
            handle: Rectangle { x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width); y: parent.topPadding + parent.availableHeight / 2 - height / 2; width: 6; height: 12; color: section.theme.accent }
        }
        WheelHandler {
            target: null
            onWheel: event => {
                const delta = event.angleDelta.y || event.angleDelta.x;
                if (delta !== 0) {
                    section.adjustVolume(delta > 0 ? 1 : -1);
                    event.accepted = true;
                }
            }
        }
    }
    Row {
        spacing: 6
        Text { text: "Boot streak: " + (boot.text || "—"); color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
        TextAction { visible: !!stt.text; theme: section.theme; text: stt.text || ""; onClicked: shell.run("~/.nix-profile/bin/stt-toggle --final") }
    }
}
