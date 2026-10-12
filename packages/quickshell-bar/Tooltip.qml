import QtQuick
import Quickshell

PopupWindow {
    id: tip
    property string text: ""
    readonly property int fontPixelSize: label.font.pixelSize
    readonly property color textColor: label.color
    required property var theme
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    implicitWidth: label.implicitWidth + 30
    implicitHeight: label.implicitHeight + 16
    color: Qt.alpha(theme.surface, 0.85)
    Text {
        id: label
        anchors.centerIn: parent
        text: tip.text
        textFormat: Text.PlainText
        color: tip.theme.foreground
        font.family: "JetBrainsMonoNL Nerd Font"
        font.pixelSize: 18
        font.bold: true
    }
}
