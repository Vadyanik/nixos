import QtQuick
import QtQuick.Controls
import Quickshell.Services.Mpris

Column {
    id: section
    required property var theme
    required property var service
    property bool active: false
    readonly property var player: service.player
    function snapshot() { return {previousWidth: previousButton.width, playWidth: playButton.width, nextX: nextButton.x, playerX: playerButton.x}; }
    visible: !!player
    spacing: 8
    SectionHeader { width: parent.width; theme: section.theme; title: "NOW PLAYING" }
    Column {
        width: parent.width
        visible: !!section.player
        spacing: 8
        Item {
            width: parent.width
            height: metadataRow.implicitHeight
            Row {
                id: metadataRow
                width: parent.width
                spacing: 12
                Item {
                    id: artFrame
                    property real ratio: art.sourceSize.width > 0 && art.sourceSize.height > 0 ? art.sourceSize.width / art.sourceSize.height : 1
                    width: ratio >= 1 ? Math.min(112, 80 * ratio) : Math.min(80, 112 * ratio)
                    height: width / ratio
                    Image { id: art; anchors.fill: parent; source: section.player?.trackArtUrl || ""; fillMode: Image.PreserveAspectFit; asynchronous: true; cache: true }
                    Text { anchors.centerIn: parent; visible: art.status !== Image.Ready; text: "♪"; color: section.theme.accent; font.pixelSize: 30 }
                }
                Column {
                    width: parent.width - artFrame.width - 12
                    spacing: 5
                    Text { width: parent.width; text: section.service.displayTitle(section.player); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: section.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16; bold: true } }
                    Text { width: parent.width; visible: text.trim().length > 0; text: section.player?.trackArtist || ""; textFormat: Text.PlainText; elide: Text.ElideRight; color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: section.service.focusPlayer(section.player?.dbusName || "") }
        }
        Slider {
            height: 28
            width: parent.width
            visible: (section.player?.length || 0) > 0 && !!section.player?.positionSupported
            from: 0; to: Math.max(1, section.player?.length || 1)
            value: section.player?.position || 0
            enabled: !!section.player?.canSeek
            onMoved: section.player.position = value
            background: Rectangle { x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - 1; width: parent.availableWidth; height: 2; color: section.theme.separator; Rectangle { width: parent.width * parent.parent.visualPosition; height: 2; color: section.theme.accent } }
            handle: Rectangle { x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width); y: parent.topPadding + parent.availableHeight / 2 - height / 2; width: 6; height: 6; color: section.theme.accent }
        }
        Row {
            spacing: 12
            TextAction { id: previousButton; width: 42; theme: section.theme; text: "◀"; enabled: !!section.player?.canGoPrevious; onClicked: section.player.previous() }
            TextAction { id: playButton; width: 42; theme: section.theme; text: section.player?.isPlaying ? "" : "▶"; enabled: !!section.player?.canTogglePlaying; onClicked: section.player.togglePlaying()
                Row {
                    anchors.centerIn: parent
                    visible: !!section.player?.isPlaying
                    spacing: 4
                    Rectangle { width: 3; height: 12; color: section.theme.foreground }
                    Rectangle { width: 3; height: 12; color: section.theme.foreground }
                }
            }
            TextAction { id: nextButton; width: 42; theme: section.theme; text: "▶▶"; enabled: !!section.player?.canGoNext; onClicked: section.player.next() }
            TextAction { id: playerButton; width: Math.max(0, section.width - 162); theme: section.theme; text: section.player?.identity || ""; onClicked: section.service.cycle(1) }
        }
    }
    Timer { interval: 1000; repeat: true; running: section.active && !!section.player?.isPlaying; onTriggered: section.player.positionChanged() }
}
