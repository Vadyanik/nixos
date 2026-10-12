import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popup
    required property var compositor
    required property var theme
    required property var service
    readonly property bool showing: Object.keys(service.nowPlaying).length > 0 && !service.controlOpen
    property bool present: false
    property real slideX: implicitWidth
    // Keep the last artwork through the exit animation, when the service clears
    // nowPlaying immediately. On entry, wait for the new image before sliding in.
    property string displayedArt: ""

    function beginEntrance() {
        if (!showing) return;
        if (!displayedArt || cover.status === Image.Ready || cover.status === Image.Error)
            slideX = 0;
        else
            entranceFallback.restart();
    }
    screen: Quickshell.screens.find(s => s.name === compositor.focusedMonitor) || Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 32; right: 0 }
    implicitWidth: 370
    implicitHeight: Math.max(100, coverFrame.height + 24)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-now-playing"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: popupSurface }
    visible: present
    onShowingChanged: {
        if (showing) {
            displayedArt = service.nowPlaying.art || "";
            present = true;
            slideX = implicitWidth;
            Qt.callLater(beginEntrance);
        }
        else slideX = implicitWidth;
    }
    Behavior on slideX {
        NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
            onRunningChanged: if (!running && !popup.showing) popup.present = false
        }
    }
    Component.onCompleted: if (showing) {
        displayedArt = service.nowPlaying.art || "";
        present = true;
        slideX = implicitWidth;
        Qt.callLater(beginEntrance);
    }
    Timer {
        id: entranceFallback
        interval: 2000
        repeat: false
        onTriggered: if (popup.showing) popup.slideX = 0
    }
    Rectangle {
        id: popupSurface
        width: parent.width
        height: parent.height
        x: popup.slideX
        color: popup.theme.panelSurface
        border { width: 1; color: popup.theme.separator }
        Row {
            anchors { fill: parent; margins: 12 }
            spacing: 12
            Item {
                id: coverFrame
                property real ratio: cover.sourceSize.width > 0 && cover.sourceSize.height > 0 ? cover.sourceSize.width / cover.sourceSize.height : 1
                width: ratio >= 1 ? Math.min(112, 96 * ratio) : Math.min(96, 112 * ratio)
                height: width / ratio
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    id: cover
                    anchors.fill: parent
                    source: popup.displayedArt
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    onStatusChanged: {
                        if (status === Image.Ready || status === Image.Error) {
                            entranceFallback.stop();
                            if (popup.showing) popup.slideX = 0;
                        }
                    }
                }
            Rectangle { anchors.fill: parent; visible: cover.status !== Image.Ready; color: popup.theme.barSurface; Text { anchors.centerIn: parent; text: "♪"; color: popup.theme.accent; font.pixelSize: 34 } }
            Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: popup.theme.separator }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: popup.service.focusPlayer(popup.service.nowPlaying.player || "") }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 88
                spacing: 6
                Text { width: parent.width; text: popup.service.nowPlaying.title || ""; textFormat: Text.PlainText; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight; color: popup.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 16; bold: true } }
                Text { width: parent.width; visible: text.length > 0; text: popup.service.nowPlaying.artist || ""; textFormat: Text.PlainText; maximumLineCount: 1; elide: Text.ElideRight; color: popup.theme.mutedForeground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 14 } }
            }
        }
    }
}
