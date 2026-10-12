import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window
    required property var compositor
    required property var theme
    required property var service
    signal openCenter()
    visible: service.popups.count > 0
    screen: Quickshell.screens.find(s => s.name === compositor.focusedMonitor) || Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 42; right: 12 }
    implicitWidth: Math.min(440, screen?.width || 440)
    implicitHeight: Math.min(stack.implicitHeight, (screen?.height || 1440) - 54)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: stack }
    function capture(path) { stack.grabToImage(result => result.saveToFile(path)); }
    function snapshot() { return {visible: visible, width: width, height: height, count: service.popups.count}; }
    Column {
        id: stack
        width: parent.width
        spacing: 10
        Repeater {
            model: window.service.popups
            Rectangle {
                id: toast
                required property var model
                property bool entered: false
                width: stack.width
                height: content.height + 28
                x: entered && !model.closing ? 0 : width
                Behavior on x { NumberAnimation { duration: window.service.popupAnimationDuration; easing.type: Easing.OutCubic } }
                Component.onCompleted: Qt.callLater(() => entered = true)
                color: window.theme.panelSurface
                border { width: 1; color: window.theme.separator }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        let action = window.service.live[toast.model.liveId]?.actions.find(a => a.identifier === "default");
                        window.service.openNotification(toast.model.id);
                        window.service.hidePopup(toast.model.id);
                    }
                }
                Column {
                    id: content
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 6
                    Row {
                        width: parent.width
                        spacing: 8
                        Item {
                            width: 20; height: 20
                            Image { id: appIcon; anchors.fill: parent; source: toast.model.icon ? (toast.model.icon.startsWith("/") || toast.model.icon.includes(":") ? toast.model.icon : Quickshell.iconPath(toast.model.icon)) : window.service.appIconSource(toast.model.app, toast.model.desktop); asynchronous: true }
                            Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: "▣"; color: window.theme.accent; font.pixelSize: 16 }
                        }
                        Text { width: parent.width - 68; text: toast.model.app; textFormat: Text.PlainText; elide: Text.ElideRight; color: window.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                    }
                    Text { width: parent.width; text: toast.model.title; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 1; elide: Text.ElideRight; color: window.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16; bold: true } }
                    Text { width: parent.width; visible: text.length > 0; text: toast.model.body; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: window.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
                }
                Timer { interval: Math.max(1, toast.model.timeout || 0); running: toast.model.timeout > 0 && !toast.model.closing; repeat: false; onTriggered: window.service.expirePopup(toast.model.id, toast.model.token) }
                Timer { interval: window.service.popupAnimationDuration + 30; running: toast.model.closing; repeat: false; onTriggered: window.service.removePopup(toast.model.token) }
            }
        }
    }
}
