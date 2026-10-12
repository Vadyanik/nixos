import QtQuick

Column {
    id: section
    required property var theme
    required property var service
    signal activated()
    visible: (service.result.sections || []).some(group => (group.bookmarks || []).length > 0)
    spacing: 14
    SectionHeader { width: parent.width; theme: section.theme; title: "BOOKMARKS" }
    Repeater {
        model: section.service.result.sections
        Column {
            id: group
            required property var modelData
            visible: (modelData.bookmarks || []).length > 0
            width: section.width
            spacing: 10
            Text { width: parent.width; text: group.modelData.title; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: section.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
            Grid {
                width: parent.width
                columns: Math.max(1, Math.floor((width + spacing) / 120))
                spacing: 8
                Repeater {
                    model: group.modelData.bookmarks
                    Rectangle {
                        id: tile
                        required property var modelData
                        width: (group.width - (parent.columns - 1) * parent.spacing) / parent.columns
                        height: 80
                        color: mouse.containsMouse ? section.theme.hover : "transparent"
                        Image { id: icon; anchors { top: parent.top; topMargin: 8; horizontalCenter: parent.horizontalCenter } width: 28; height: 28; source: tile.modelData.icon; asynchronous: true; fillMode: Image.PreserveAspectFit }
                        Text { anchors { top: parent.top; topMargin: 8; horizontalCenter: parent.horizontalCenter } visible: icon.status !== Image.Ready; text: tile.modelData.title.slice(0, 1).toUpperCase(); color: section.theme.accent; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 24; bold: true } }
                        Text { anchors { top: icon.bottom; topMargin: 9; left: parent.left; right: parent.right; margins: 4 } text: tile.modelData.title; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: mouse.containsMouse ? section.theme.accent : section.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { section.service.openId(tile.modelData.id); section.activated(); } }
                    }
                }
            }
        }
    }
}
