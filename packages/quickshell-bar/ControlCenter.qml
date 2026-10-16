import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var shell
    required property var compositor
    required property var theme
    required property var media
    required property var bookmarks
    required property var metrics
    required property var disk
    required property var five
    required property var weekly
    required property var boot
    required property var stt
    required property var bluetooth
    required property var vpnStatus
    required property var discord
    readonly property alias claudeLimits: claudeSection.limits
    property bool opened: false
    property bool cornerReady: false
    property real reveal: 0
    readonly property real revealRadius: Math.hypot(surface.width, surface.height) * reveal
    signal discordActionRequested(string action)
    property string powerHoldAction: ""
    property double powerHoldStartedAt: 0
    property int powerCountdownCentiseconds: 300
    property var selectedScreen: null
    signal closeRequested()
    signal notificationsRequested()
    screen: selectedScreen || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-control-center"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    // Blur only the visible sidebar, preserving windows beneath the transparent
    // outside-click surface when the compositor uses wallpaper xray effects.
    BackgroundEffect.blurRegion: Region {
        item: surface
        Region {
            intersection: Intersection.Intersect
            shape: RegionShape.Ellipse
            x: panel.width - panel.revealRadius
            y: -panel.revealRadius
            width: panel.revealRadius * 2
            height: width
        }
    }
    visible: opened || reveal > 0
    onOpenedChanged: {
        cornerReady = false;
        if (opened) {
            cornerEnable.restart();
            selectedScreen = Quickshell.screens.find(s => s.name === compositor.focusedMonitor) || Quickshell.screens[0];
            // Map the transparent window and allocate its texture before revealing it.
            revealAnimation.stop();
            openingDelay.restart();
            focusItem.forceActiveFocus();
        } else {
            openingDelay.stop();
            revealAnimation.stop();
            revealAnimation.to = 0;
            revealAnimation.duration = 460;
            revealAnimation.start();
        }
    }
    Timer {
        id: openingDelay
        interval: 48
        onTriggered: {
            revealAnimation.to = 1;
            revealAnimation.duration = 760;
            revealAnimation.start();
        }
    }
    NumberAnimation {
        id: revealAnimation
        target: panel
        property: "reveal"
        easing.type: Easing.InOutCubic
    }
    function adjustVolume(delta) { let audio = Pipewire.defaultAudioSink?.audio; if (audio) audio.volume = Math.max(0, Math.min(1, audio.volume + delta)); }
    function startPowerHold(action) {
        powerHoldAction = action;
        powerHoldStartedAt = Date.now();
        powerCountdownCentiseconds = 300;
        powerCountdownTimer.start();
        powerActionTimer.start();
    }
    function cancelPowerHold(action) {
        if (powerHoldAction !== action) return;
        powerHoldAction = "";
        powerCountdownTimer.stop();
        powerActionTimer.stop();
    }
    function executePowerHold(action) {
        powerHoldAction = "";
        powerCountdownTimer.stop();
        powerActionTimer.stop();
        panel.closeRequested();
        Quickshell.execDetached(["systemctl", action]);
    }
    function snapshot() { return {opened: opened, visible: visible, reveal: reveal, revealRadius: revealRadius, animation: "top-right-circle", width: surface.width, height: surface.height, contentHeight: content.height, viewportHeight: scroll.height, contentY: scroll.contentY, screen: screen?.name, layer: "overlay", systemLayout: systemSection.snapshot(), mediaLayout: mediaSection.snapshot()}; }
    function capture(path) { surface.grabToImage(result => result.saveToFile(path)); }
    Timer {
        id: cornerEnable
        interval: 200
        onTriggered: if (!closeCorner.containsMouse) panel.cornerReady = true;
    }
    Timer {
        id: cornerClose
        interval: 1
        onTriggered: panel.closeRequested()
    }
    Item {
        id: focusItem
        anchors.fill: parent
        focus: panel.opened
        MouseArea {
            id: closeCorner
            anchors { top: parent.top; right: parent.right }
            width: 3
            height: 3
            z: 100
            enabled: panel.compositor.isNiri
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onExited: if (panel.opened) panel.cornerReady = true;
            onEntered: if (panel.opened && panel.cornerReady) {
                panel.cornerReady = false;
                cornerClose.start();
            }
        }
        Keys.onEscapePressed: {
            panel.closeRequested();
        }
        Keys.onTabPressed: panel.notificationsRequested()
        Shortcut { sequence: "Right"; enabled: panel.opened; onActivated: panel.adjustVolume(0.02) }
        Shortcut { sequence: "Left"; enabled: panel.opened; onActivated: panel.adjustVolume(-0.02) }
        Shortcut { sequence: "Space"; enabled: panel.opened && !!panel.media.player?.canTogglePlaying; onActivated: panel.media.player.togglePlaying() }
        Timer {
            id: powerCountdownTimer
            interval: 10
            repeat: true
            onTriggered: panel.powerCountdownCentiseconds = Math.max(0, Math.ceil((3000 - (Date.now() - panel.powerHoldStartedAt)) / 10))
        }
        Timer {
            id: powerActionTimer
            interval: 3000
            onTriggered: {
                if (panel.powerHoldAction === "reboot" && rebootMouse.pressed) panel.executePowerHold("reboot");
                else if (panel.powerHoldAction === "poweroff" && poweroffMouse.pressed) panel.executePowerHold("poweroff");
                else panel.cancelPowerHold(panel.powerHoldAction);
            }
        }
        MouseArea { anchors.fill: parent; onClicked: panel.closeRequested() }
        Rectangle {
            id: surface
            x: parent.width - width
            y: 0
            width: parent.width * 0.25
            height: parent.height
            color: panel.theme.panelSurface
            clip: true
            // Keep one rendering path throughout the reveal to avoid an endpoint flash.
            layer.enabled: true
            layer.effect: ShaderEffect {
                property vector2d size: Qt.vector2d(surface.width, surface.height)
                property real progress: panel.reveal
                fragmentShader: "shaders/control-reveal.frag.qsb"
            }
            // Consume clicks within the panel; the surrounding surface closes it.
            MouseArea { anchors.fill: parent }
            Rectangle { width: 1; height: parent.height; color: panel.theme.separator }
            Flickable {
                id: scroll
                anchors { fill: parent; topMargin: 16; leftMargin: 22; rightMargin: 22; bottomMargin: 18 }
                contentWidth: width
                interactive: true
                contentHeight: content.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3; contentItem: Rectangle { color: panel.theme.separator; implicitWidth: 3 } }
                Column {
                    id: content
                    width: scroll.width
                    spacing: 16
                    Item {
                        width: parent.width
                        height: 64
                        Row {
                            anchors.centerIn: parent
                            spacing: 12
                            Rectangle {
                                id: dndButton
                                width: 64; height: 64
                                color: dndMouse.containsMouse ? panel.theme.hover : (panel.shell.dndActive ? Qt.alpha(panel.theme.accent, 0.14) : "transparent")
                                border.width: 1
                                border.color: panel.shell.dndActive ? panel.theme.accent : panel.theme.separator
                                Text { anchors.centerIn: parent; text: "󰂟"; color: panel.shell.dndActive ? panel.theme.accent : panel.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 27 } }
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
                            Rectangle {
                                id: vpnButton
                                width: 64; height: 64
                                color: vpnMouse.containsMouse ? panel.theme.hover : (vpnConnected ? Qt.alpha(panel.theme.accent, 0.14) : "transparent")
                                border.width: 1
                                border.color: vpnConnected || vpnMouse.containsMouse ? panel.theme.accent : panel.theme.separator
                                readonly property bool vpnConnected: (panel.vpnStatus.text || "").startsWith("Connected")
                                Text { anchors.centerIn: parent; text: vpnButton.vpnConnected ? "󰌾" : "󰌿"; color: vpnButton.vpnConnected ? panel.theme.accent : panel.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 27 } }
                                MouseArea { id: vpnMouse; anchors.fill: parent; hoverEnabled: true; onClicked: panel.shell.toggleVpn() }
                            }
                            Rectangle {
                                id: rebootButton
                                width: 64; height: 64
                                color: rebootMouse.pressed ? "#e53935" : rebootMouse.containsMouse ? panel.theme.hover : "transparent"
                                border.width: 1
                                border.color: rebootMouse.pressed ? "#e53935" : rebootMouse.containsMouse ? panel.theme.accent : panel.theme.separator
                                Text { anchors.centerIn: parent; text: rebootMouse.pressed && panel.powerHoldAction === "reboot" ? (panel.powerCountdownCentiseconds / 100).toFixed(2) : "󰜉"; color: rebootMouse.pressed ? "white" : rebootMouse.containsMouse ? panel.theme.accent : panel.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: rebootMouse.pressed ? 18 : 27; bold: rebootMouse.pressed } }
                                MouseArea { id: rebootMouse; anchors.fill: parent; hoverEnabled: true; onPressed: panel.startPowerHold("reboot"); onReleased: panel.cancelPowerHold("reboot"); onCanceled: panel.cancelPowerHold("reboot") }
                            }
                            Rectangle {
                                id: poweroffButton
                                width: 64; height: 64
                                color: poweroffMouse.pressed ? "#e53935" : poweroffMouse.containsMouse ? panel.theme.hover : "transparent"
                                border.width: 1
                                border.color: poweroffMouse.pressed ? "#e53935" : poweroffMouse.containsMouse ? panel.theme.accent : panel.theme.separator
                                Text { anchors.centerIn: parent; text: poweroffMouse.pressed && panel.powerHoldAction === "poweroff" ? (panel.powerCountdownCentiseconds / 100).toFixed(2) : "󰐥"; color: poweroffMouse.pressed ? "white" : poweroffMouse.containsMouse ? panel.theme.accent : panel.theme.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: poweroffMouse.pressed ? 18 : 27; bold: poweroffMouse.pressed } }
                                MouseArea { id: poweroffMouse; anchors.fill: parent; hoverEnabled: true; onPressed: panel.startPowerHold("poweroff"); onReleased: panel.cancelPowerHold("poweroff"); onCanceled: panel.cancelPowerHold("poweroff") }
                            }
                        }
                    }
                    SystemSection { id: systemSection; width: parent.width; theme: panel.theme; shell: panel.shell; metrics: panel.metrics; boot: panel.boot; stt: panel.stt; bluetooth: panel.bluetooth }
                    ClaudeSection { id: claudeSection; width: parent.width; theme: panel.theme; shell: panel.shell; five: panel.five; weekly: panel.weekly }
                    DiscordSection { width: parent.width; theme: panel.theme; status: panel.discord; onActionRequested: action => panel.discordActionRequested(action) }
                    MediaSection { id: mediaSection; width: parent.width; theme: panel.theme; service: panel.media; active: panel.opened }
                    BookmarksSection { width: parent.width; theme: panel.theme; service: panel.bookmarks; onActivated: panel.closeRequested() }
                }
            }
        }
    }
}
