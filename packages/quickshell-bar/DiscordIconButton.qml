import QtQuick

Item {
    id: control
    required property var theme
    property string glyph: ""
    property string tooltip: ""
    property bool selected: false
    property bool destructive: false
    readonly property color tone: destructive || selected ? theme.error : theme.accent
    signal clicked()
    implicitWidth: 36
    implicitHeight: 36

    Rectangle {
        anchors.fill: parent
        color: mouse.containsMouse ? control.theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Text {
        anchors.centerIn: parent
        text: control.glyph
        color: mouse.containsMouse && control.destructive
            ? control.theme.error
            : control.selected
                ? control.theme.accent
                : mouse.containsMouse
                    ? control.theme.accent
                    : control.theme.foreground
        font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }

    Timer { id: hoverDelay; interval: 450; running: mouse.containsMouse && control.tooltip.length > 0; onTriggered: tip.visible = true }
    Connections { target: mouse; function onContainsMouseChanged() { if (!mouse.containsMouse) tip.visible = false; } }
    Tooltip { id: tip; anchor.item: control; text: control.tooltip; theme: control.theme }
}
