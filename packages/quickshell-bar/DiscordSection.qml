import QtQuick
import QtQuick.Layouts

Column {
    id: section
    required property var theme
    required property var status
    signal actionRequested(string action)
    visible: status?.connected === true
    spacing: 8

    SectionHeader { width: parent.width; theme: section.theme; title: "DISCORD" }

    RowLayout {
        width: section.width
        height: 42
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: [section.status.server, section.status.channel].filter(Boolean).join(" · ")
            color: section.theme.foreground
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 }
        }

        DiscordIconButton {
            theme: section.theme
            glyph: section.status.muted ? "\uf131" : "\uf130"
            tooltip: section.status.muted ? "Включить микрофон" : "Выключить микрофон"
            selected: section.status.muted === true
            onClicked: section.actionRequested("mute")
        }
        DiscordIconButton {
            theme: section.theme
            glyph: section.status.deafened ? "\uf026" : "\uf028"
            tooltip: section.status.deafened ? "Включить звук" : "Выключить звук"
            selected: section.status.deafened === true
            onClicked: section.actionRequested("deafen")
        }
        DiscordIconButton {
            theme: section.theme
            glyph: "\uf03d"
            tooltip: "Включить или выключить камеру"
            onClicked: section.actionRequested("camera")
        }
        DiscordIconButton {
            theme: section.theme
            glyph: "\uf14d"
            tooltip: "Начать или остановить демонстрацию экрана"
            onClicked: section.actionRequested("screenshare")
        }
        DiscordIconButton {
            theme: section.theme
            glyph: "\uf2f5"
            tooltip: "Выйти из звонка"
            destructive: true
            onClicked: section.actionRequested("disconnect")
        }
    }
}
