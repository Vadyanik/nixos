import QtQuick

Rectangle {
    id: button
    required property var theme
    property string text
    property string tooltip: ""
    property int acceptedButtons: Qt.LeftButton
    property bool wheelEnabled: false
    signal clicked()
    signal rightClicked()
    signal wheelScrolled(real steps)
    implicitWidth: Math.max(32, metrics.advanceWidth + 12)
    implicitHeight: 26
    color: mouse.containsMouse ? theme.hover : "transparent"
    opacity: enabled ? 1 : 0.35
    TextMetrics { id: metrics; text: button.text; font.family: "JetBrainsMonoNL Nerd Font"; font.pixelSize: 16 }
    Text { id: label; anchors.centerIn: parent; width: Math.max(0, button.width - 12); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: button.text; color: mouse.containsMouse ? button.theme.accent : button.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16 } }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: button.acceptedButtons; onClicked: mouse => { if (mouse.button === Qt.RightButton) button.rightClicked(); else button.clicked(); } onWheel: wheel => { if (button.wheelEnabled) { button.wheelScrolled(wheel.angleDelta.y / 120); wheel.accepted = true; } else wheel.accepted = false; } }
    Timer { id: hoverDelay; interval: 500; running: mouse.containsMouse && button.tooltip.length > 0; onTriggered: tip.visible = true }
    Connections { target: mouse; function onContainsMouseChanged() { if (!mouse.containsMouse) tip.visible = false; } }
    Tooltip { id: tip; anchor.item: button; text: button.tooltip; theme: button.theme }
}
