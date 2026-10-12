import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var compositor
    required property var theme
    required property var notifications
    required property var shell
    property bool opened: false
    property real slide: 0
    property var selectedScreen: null
    signal closeRequested()
    signal controlRequested()
    screen: selectedScreen || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications-center"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    BackgroundEffect.blurRegion: Region {
        item: surface
        Region { item: dndButton }
    }
    visible: opened || slide > 0
    onOpenedChanged: {
        if (opened) {
            selectedScreen = Quickshell.screens.find(s => s.name === compositor.focusedMonitor) || Quickshell.screens[0];
            slide = 1;
            focusItem.forceActiveFocus();
        } else slide = 0;
    }
    Behavior on slide { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    function snapshot() { return {opened: opened, visible: visible, slide: slide, width: surface.width, height: surface.height, contentHeight: content.height, viewportHeight: scroll.height, contentY: scroll.contentY, screen: screen?.name, layer: "overlay", notificationGroups: notificationSection.snapshot()}; }

    Item {
        id: focusItem
        anchors.fill: parent
        focus: panel.opened
        Keys.onEscapePressed: panel.closeRequested()
        Keys.onTabPressed: panel.controlRequested()
        MouseArea { anchors.fill: parent; onClicked: panel.closeRequested() }
        Rectangle {
            id: surface
            x: parent.width - width * panel.slide
            y: 0
            width: parent.width * 0.25
            height: parent.height
            color: panel.theme.panelSurface
            clip: true
            MouseArea { anchors.fill: parent }
            Rectangle { width: 1; height: parent.height; color: panel.theme.separator }
            Flickable {
                id: scroll
                anchors { fill: parent; topMargin: 16; leftMargin: 22; rightMargin: 22; bottomMargin: 18 }
                contentWidth: width
                contentHeight: content.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3; contentItem: Rectangle { color: panel.theme.separator; implicitWidth: 3 } }
                Column {
                    id: content
                    width: scroll.width
                    spacing: 16
                    NotificationsSection { id: notificationSection; width: parent.width; theme: panel.theme; service: panel.notifications }
                }
            }
        }
        Rectangle {
            id: dndButton
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 20; bottomMargin: 20 }
            width: 64
            height: 64
            z: 2
            color: dndMouse.containsMouse ? panel.theme.hover : (panel.shell.dndActive ? Qt.alpha(panel.theme.accent, 0.14) : "transparent")
            border.width: 1
            border.color: panel.shell.dndActive ? panel.theme.accent : panel.theme.separator
            Text {
                anchors.centerIn: parent
                text: "󰂟"
                color: panel.shell.dndActive ? panel.theme.accent : panel.theme.foreground
                font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 27 }
            }
            Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 6; anchors.bottomMargin: 6; width: 7; height: 7; radius: 4; color: panel.theme.accent; visible: panel.shell.autoDndOnShareEnabled }
            MouseArea {
                id: dndMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) panel.shell.toggleManualDnd();
                    else if (mouse.button === Qt.RightButton) panel.shell.toggleAutoDndOnShare();
                }
            }
        }
    }
}
