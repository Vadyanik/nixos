import QtQuick
import Quickshell

Item {
    id: module
    property string text: ""
    property string tooltip: ""
    required property var theme
    property color background: theme.primary
    property color foreground: theme["on-primary"]
    property int padding: 8
    property int margin: 2
    property int leadingMargin: margin
    property int trailingMargin: margin
    property int verticalMargin: 0
    property int minimumWidth: 0
    property bool bold: true
    property bool blink: false
    property bool blinkPhase: false
    property var leftAction: null
    property var rightAction: null
    property var middleAction: null
    property var scrollAction: null
    visible: text.length > 0
    implicitWidth: visible ? Math.max(minimumWidth, label.implicitWidth + padding * 2) + leadingMargin + trailingMargin : 0
    implicitHeight: 40
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: module.leadingMargin; anchors.rightMargin: module.trailingMargin
        anchors.topMargin: module.verticalMargin; anchors.bottomMargin: module.verticalMargin
        color: module.blink ? (module.blinkPhase ? "#003300" : "#00ff00") : module.background
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: module.text
        textFormat: Text.PlainText
        color: module.blink ? (module.blinkPhase ? "white" : "black") : module.foreground
        font.family: "JetBrainsMonoNL Nerd Font"
        font.pixelSize: 18
        font.bold: module.bold || module.blink
    }
    Timer { interval: 400; running: module.blink; repeat: true; onTriggered: module.blinkPhase = !module.blinkPhase }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            let action = event.button === Qt.LeftButton ? module.leftAction : event.button === Qt.RightButton ? module.rightAction : module.middleAction;
            if (action) action();
        }
        onWheel: event => { if (module.scrollAction) module.scrollAction(event.angleDelta.y, event.angleDelta.x); }
    }
    Timer { id: hoverDelay; interval: 500; running: mouse.containsMouse && module.tooltip.length > 0; onTriggered: tip.visible = true }
    Connections { target: mouse; function onContainsMouseChanged() { if (!mouse.containsMouse) tip.visible = false; } }
    Tooltip {
        id: tip
        anchor.item: module
        text: module.tooltip
        theme: module.theme
    }
    function snapshot() {
        let p = module.mapToItem(null, 0, 0);
        return {text: text, tooltip: tooltip, visible: visible, x: p.x, y: p.y, width: width, height: height, background: background.toString(), foreground: foreground.toString(), padding: padding, leadingMargin: leadingMargin, trailingMargin: trailingMargin, verticalMargin: verticalMargin, minimumWidth: minimumWidth, tooltipStyle: {fontSize: tip.fontPixelSize, background: tip.color.toString(), foreground: tip.textColor.toString()}};
    }
}
