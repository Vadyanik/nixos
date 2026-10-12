import QtQuick

Row {
    required property var theme
    property string title
    spacing: 12
    height: 28
    Text { text: title; color: theme.accent; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16; bold: true; letterSpacing: 1.5 } }
    Rectangle { width: Math.max(0, parent.width - parent.children[0].width - 12); height: 1; y: 8; color: theme.separator }
}
