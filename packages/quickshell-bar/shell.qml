//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell/bar/"
    readonly property string scripts: Quickshell.shellPath("scripts/")
    property bool enableInputRemapperPreset: false
    readonly property string language: desktop.language
    Compositor { id: desktop }
    property var panels: []
    property bool controlOpen: false
    property double controlClosedAt: 0
    property bool notificationsOpen: false
    property bool bluetoothInitialized: false
    property var previousBluetooth: ({connected: false, address: "", name: "", battery: null})
    property bool bluetoothLowNotified: false
    property bool manualDndEnabled: false
    property bool autoDndOnShareEnabled: true
    property bool volumePreviewVisible: false
    readonly property var palette: theme.colors
    readonly property var bluetoothState: bluetooth.value
    readonly property bool screenSharing: screenShare.value.text === "true"
    readonly property bool dndActive: manualDndEnabled || (autoDndOnShareEnabled && screenSharing)
    readonly property string layoutCode: ({Russian: "RU", Ukrainian: "UA", "English (US)": "US", English: "US"})[language] || language.slice(0, 2).toUpperCase()
    readonly property int volumePercent: Math.round((Pipewire.defaultAudioSink?.audio?.volume || 0) * 100)
    Theme { id: theme; path: root.configDir + "colors.css" }
    onControlOpenChanged: {
        if (controlOpen) { metrics.refresh(); disk.refresh(); vpn.refresh(); bookmarks.refresh(); }
        else controlClosedAt = Date.now();
    }
    Component.onCompleted: {
        try {
            const settings = JSON.parse(dndSettings.text() || "{}");
            root.manualDndEnabled = settings.manualDndEnabled === true;
            root.autoDndOnShareEnabled = settings.autoDndOnShareEnabled !== false;
        } catch (e) { console.warn("DND settings", e); }
    }
    function run(command) { Quickshell.execDetached(["bash", "-c", command]); }
    Process {
        id: workspaceWallpaperWatcher
        command: ["wallpaper-workspace", "watch"]
        running: false // Legacy per-workspace wallpapers; see legacy/space-wallpaper
        stdout: StdioCollector {}
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Workspace wallpaper watcher:", text.trim()) }
        onExited: (code, status) => {
            console.warn("Workspace wallpaper watcher exited", code);
            workspaceWallpaperRestart.restart();
        }
    }
    Timer { id: workspaceWallpaperRestart; interval: 2000; onTriggered: workspaceWallpaperWatcher.running = true }
    function openNotificationsCenter() {
        if (notifications.history.count === 0) { notificationsOpen = false; return; }
        controlOpen = false;
        notificationsOpen = true;
    }
    function bluetoothNotice(title, body) {
        Quickshell.execDetached(["/run/current-system/sw/bin/notify-send", "--app-name=Bluetooth", "--app-icon=bluetooth", "--expire-time=6000", title, body]);
    }
    function persistDndSettings() {
        dndSettings.setText(JSON.stringify({manualDndEnabled: manualDndEnabled, autoDndOnShareEnabled: autoDndOnShareEnabled}));
    }
    function toggleManualDnd() { manualDndEnabled = !manualDndEnabled; persistDndSettings(); }
    function toggleAutoDndOnShare() { autoDndOnShareEnabled = !autoDndOnShareEnabled; persistDndSettings(); }
    function changeVolume(delta) {
        const audio = Pipewire.defaultAudioSink?.audio;
        if (audio) audio.volume = Math.max(0, Math.min(1, audio.volume + delta));
        volumePreviewVisible = true;
        volumePreviewTimer.restart();
    }
    function toggleVpn() {
        const connected = (vpn.value.text || "").trim().startsWith("Connected");
        actionComponent.createObject(root, {
            command: ["/run/current-system/sw/bin/mullvad", connected ? "disconnect" : "connect"],
            callback: () => vpnRefreshTimer.restart(),
            running: true
        });
    }
    function action(script, argument, callback) {
        actionComponent.createObject(root, {command: ["bash", scripts + script, argument], callback: callback, running: true});
    }
    function discordAction(name) {
        actionComponent.createObject(root, {command: ["python3", scripts + "discord_rpc.py", "action", name], callback: () => discord.refresh(), running: true});
    }
    function refresh(name) {
        if (name === "all" || name === "claude") { five.refresh(); weekly.refresh(); }
        if (name === "all" || name === "disk") disk.refresh();
        if (name === "all" || name === "vpn") vpn.refresh();
        if (name === "all" || name === "alert") alert.refresh();
        if (name === "all" || name === "bluetooth") bluetooth.refresh();
        if (name === "all" || name === "stt") stt.refresh();
        if (name === "all" || name === "media") { if (media.player) media.player.positionChanged(); }
    }
    function statusColor(value) {
        let cls = value.class || "";
        return ({safe: palette.primary, alert: "#c62828", recording: "#c62828", transcribing: "#f9a825", surplus: "#2e7d32", full: palette.primary, warn: "#f17c5b", low: "#d8432e", critical: "#c62828", excess: "#00ff00"})[cls] || (cls === "error" ? palette["charcoal-2"] : palette.primary);
    }
    function statusInk(value) { return ["surplus", "low", "critical", "error", "recording"].includes(value.class) ? palette.white : palette["on-primary"]; }
    Component {
        id: actionComponent
        Process {
            property var callback: null
            onExited: (code, status) => { if (code !== 0) console.warn("Action failed", command, code); if (callback) callback(); destroy(); }
        }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Timer { id: volumePreviewTimer; interval: 1100; onTriggered: root.volumePreviewVisible = false }
    FileView { id: dndSettings; path: root.configDir + "dnd-settings.json"; blockLoading: true; printErrors: false }
    Timer { id: vpnRefreshTimer; interval: 1500; onTriggered: vpn.refresh() }
    Poll { id: alert; command: ["bash", root.scripts + "dnipro_alert.sh"]; interval: 30000 }
    MediaService { id: media; compositor: desktop; scripts: root.scripts; controlOpen: root.controlOpen || root.notificationsOpen; doNotDisturb: root.dndActive }
    NotificationService { id: notifications; doNotDisturb: root.dndActive }
    Connections {
        target: notifications
        function onHistoryRevisionChanged() {
            if (notifications.history.count === 0 && root.notificationsOpen) root.notificationsOpen = false;
        }
    }
    BookmarkService { id: bookmarks; scripts: root.scripts }
    Poll { id: metrics; command: ["python3", root.scripts + "system_metrics.py"]; interval: root.controlOpen ? 2000 : 0 }
    Poll { id: vpn; command: ["/run/current-system/sw/bin/mullvad", "status", "-v"]; interval: root.controlOpen ? 5000 : 0; json: false }
    Poll { id: five; command: ["bash", root.scripts + "claude_usage.sh", "status", "five"]; interval: 60000 }
    Poll { id: weekly; command: ["bash", root.scripts + "claude_usage.sh", "status", "weekly"]; interval: 60000 }
    ClaudeStageNotifications { id: claudeNotices; five: five.value; weekly: weekly.value; limits: control.claudeLimits }
    Poll { id: disk; command: ["bash", root.scripts + "disk_space.sh", "both"]; interval: 10000 }
    Poll { id: boot; command: ["bash", root.scripts + "boot_streak.sh"]; interval: 3600000; json: false }
    Poll { id: stt; command: ["bash", root.scripts + "stt-status.sh"]; interval: 1000 }
    Poll { id: screenShare; command: ["bash", root.scripts + "screen_share_status.sh"]; interval: 2000; json: false }
    Poll { id: bluetooth; command: ["bash", root.scripts + "bluetooth_status.sh"]; interval: 30000 }
    Poll { id: discord; command: ["python3", root.scripts + "discord_rpc.py", "status"]; interval: 1200 }
    Process {
        id: discordDaemon
        command: ["python3", root.scripts + "discord_rpc.py", "daemon"]
        running: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (code !== 0) console.warn("Discord RPC bridge exited", code);
            discordDaemonRestart.start();
        }
    }
    Timer { id: discordDaemonRestart; interval: 3000; onTriggered: discordDaemon.running = true }
    Connections {
        target: bluetooth
        function onValueChanged() {
            const current = bluetooth.value || {};
            const previous = root.previousBluetooth;
            if (!root.bluetoothInitialized) {
                root.bluetoothInitialized = true;
                root.bluetoothLowNotified = false;
                if (current.connected && current.battery !== null && current.battery <= 15) {
                    root.bluetoothNotice("Low Bluetooth battery", `${current.name}: ${current.battery}%`);
                    root.bluetoothLowNotified = true;
                }
            } else {
                if (current.connected && (!previous.connected || current.address !== previous.address)) {
                    root.bluetoothNotice("Bluetooth connected", current.name || "Device");
                    root.bluetoothLowNotified = false;
                } else if (!current.connected && previous.connected) {
                    root.bluetoothNotice("Bluetooth disconnected", previous.name || "Device");
                    root.bluetoothLowNotified = false;
                }
                if (current.connected && current.battery !== null && current.battery <= 15 && !root.bluetoothLowNotified) {
                    root.bluetoothNotice("Low Bluetooth battery", `${current.name}: ${current.battery}%`);
                    root.bluetoothLowNotified = true;
                } else if (current.connected && current.battery !== null && current.battery > 15) {
                    root.bluetoothLowNotified = false;
                }
            }
            root.previousBluetooth = current;
        }
    }
    // Keep the configured but disabled preset available without enabling a new module.
    Poll { id: preset; command: ["bash", root.scripts + "toggle_preset.sh", "display"]; interval: root.enableInputRemapperPreset ? 500 : 0; json: false }
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/stt-" + (Quickshell.env("XDG_RUNTIME_DIR").split("/").pop()) + "/status"
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); stt.refresh(); }
    }
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    HotkeysPanel { id: hotkeys; theme: root.palette; compositor: desktop }
    KeystrokesService { id: keystrokes; compositor: desktop }
    IpcHandler {
        target: "bar"
        function toggleHotkeys(): void {
            root.controlOpen = false;
            root.notificationsOpen = false;
            hotkeys.opened = !hotkeys.opened;
        }
        function closeHotkeys(): void { hotkeys.opened = false; }
        function hotkeysStatus(): string { return JSON.stringify({opened: hotkeys.opened, count: hotkeys.entries.length}); }
        function toggleKeystrokes(): void { keystrokes.opened = !keystrokes.opened; }
        function toggleKeystrokesLatin(): void { keystrokes.latinKeys = !keystrokes.latinKeys; }
        function keystrokesStatus(): string { return JSON.stringify({opened: keystrokes.opened, latinKeys: keystrokes.latinKeys, current: keystrokes.current, entries: keystrokes.snapshot()}); }
        function toggleControlCenter(): void {
            if (root.controlOpen || root.notificationsOpen) { root.controlOpen = false; root.notificationsOpen = false; }
            else root.controlOpen = true;
        }
        function openNotifications(): void { root.openNotificationsCenter(); }
        function closeControlCenter(): void { root.controlOpen = false; root.notificationsOpen = false; }
        function captureControl(path: string): void { control.capture(path); }
        function capturePopups(path: string): void { notificationPopups.capture(path); }
        function dismissNotification(id: int): void { notifications.dismiss(id); }
        function clearNotifications(): void { notifications.clear(); }
        function volumeUp(): void { root.changeVolume(0.02); }
        function volumeDown(): void { root.changeVolume(-0.02); }
        function openBookmark(id: string): void { bookmarks.openId(id); }
        function refresh(module: string): void { root.refresh(module); }
        function trayMenu(id: string, open: bool): void {
            for (let panel of root.panels) panel.trayMenu(id, open);
        }
        function interact(module: string, action: string): void {
            for (let panel of root.panels) panel.interact(module, action);
        }
        function capture(path: string): void {
            for (let panel of root.panels) panel.capture(path);
        }
        function status(): string {
            return JSON.stringify({claudeNotifications: {stages: claudeNotices.previous, resetTimes: claudeNotices.resetTimes}, palette: root.palette, language: root.language, media: media.snapshot(), discord: discord.value, bluetooth: bluetooth.value, doNotDisturb: root.dndActive, manualDnd: root.manualDndEnabled, autoDndOnShare: root.autoDndOnShareEnabled, screenSharing: root.screenSharing, system: metrics.value, notifications: notifications.snapshot(), popups: notifications.popupSnapshot(), popupWindow: notificationPopups.snapshot(), bookmarks: bookmarks.snapshot(), control: control.snapshot(), notificationsCenter: notificationsCenter.snapshot(), five: five.value, weekly: weekly.value, disk: disk.value, boot: boot.value, stt: stt.value, alert: alert.value, tray: SystemTray.items.values.map(t => ({id: t.id, title: t.title, icon: t.icon, hasMenu: t.hasMenu})), workspaces: desktop.workspaces.map(w => ({id: w.id, name: w.name, active: w.active, monitor: w.monitor?.name})), volume: Pipewire.defaultAudioSink?.audio?.volume, muted: Pipewire.defaultAudioSink?.audio?.muted, panels: root.panels.map(p => p.snapshot())});
        }
    }
    Variants {
        model: Quickshell.screens
        Scope {
            required property var modelData
            // A separate overlay keeps the corner available above fullscreen windows.
            // Niri continues to handle its native top-left Overview corner.
            PanelWindow {
                screen: modelData
                visible: desktop.isNiri
                anchors { top: true; right: true }
                implicitWidth: 3
                implicitHeight: 3
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.namespace: "quickshell-control-hot-corner"
                color: "transparent"
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    id: cornerMouse
                    property bool armed: true
                    onEntered: {
                        cornerRearm.stop();
                        if (!armed || Date.now() - root.controlClosedAt < 800) return;
                        armed = false;
                        cornerAction.start();
                    }
                    onExited: cornerRearm.restart()
                    Timer {
                        id: cornerRearm
                        interval: 150
                        onTriggered: if (!cornerMouse.containsMouse) cornerMouse.armed = true;
                    }
                    Timer {
                        id: cornerAction
                        interval: 1
                        onTriggered: {
                            if (root.controlOpen) { root.controlOpen = false; return; }
                            root.notificationsOpen = false;
                            hotkeys.opened = false;
                            control.selectedScreen = modelData;
                            root.controlOpen = true;
                        }
                    }
                }
            }
            PanelWindow {
                id: panel
                screen: modelData
                anchors { top: true; left: true; right: true }
                implicitHeight: 32
                exclusiveZone: 32
                WlrLayershell.namespace: "quickshell-bar"
                color: root.palette.barSurface
                Component.onCompleted: root.panels.push(panel)
                Component.onDestruction: root.panels = root.panels.filter(p => p !== panel)
                function trayState() {
                    let result = [];
                    for (let i = 0; i < trayRepeater.count; i++) result.push(trayRepeater.itemAt(i).menuState());
                    return result;
                }
                function snapshot() { return {trayMenus: trayState(), screen: screen.name, width: width, height: height, left: leftRow.width, center: clockLabel.width, right: rightRow.width, clock: clockLabel.text, volumePreviewVisible: root.volumePreviewVisible, volume: volumeLabel.text, layout: root.layoutCode, workspaceLabels: Array.from({length: workspaceRepeater.count}, (_, i) => workspaceRepeater.itemAt(i).label), modules: [alertModule.snapshot()]}; }
                function trayMenu(id, open) {
                    for (let i = 0; i < trayRepeater.count; i++) {
                        let item = trayRepeater.itemAt(i);
                        if (item.modelData.id === id) item.setMenuOpen(open);
                    }
                }
                function interact(module, action) {
                    if (module === "alert") { if (action === "left") alertModule.leftAction(); else if (action === "right") alertModule.rightAction(); }
                    else if (module === "disk") disk.refresh();
                    else if (module === "five" || module === "weekly") root.action("claude_usage.sh", "toggle", () => root.refresh("claude"));
                    else if (module === "media" && media.player) {
                        if (action === "left" && media.player.canTogglePlaying) media.player.togglePlaying();
                        else if (action === "right" && media.player.canGoNext) media.player.next();
                        else if (action === "middle" && media.player.canGoPrevious) media.player.previous();
                        else if (action === "up" || action === "down") media.cycle(action === "up" ? -1 : 1);
                    } else if (module === "volume") { if (action === "mute" && Pipewire.defaultAudioSink?.audio) Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted; else control.adjustVolume(action === "up" ? 0.02 : -0.02); }
                    else if (module === "stt" && action === "left") root.run("~/.nix-profile/bin/stt-toggle --final");
                }
                function capture(path) { panelContent.grabToImage(result => result.saveToFile(path)); }
                Item {
                    id: panelContent
                    anchors.fill: parent
                    Rectangle { anchors.fill: parent; color: root.palette.barSurface }
                    Row {
                        id: leftRow
                        anchors { left: parent.left; leftMargin: 8 }
                        height: 32
                        spacing: 4
                        Row {
                            height: 32
                            Repeater {
                                id: workspaceRepeater
                                model: desktop.workspaces
                                Item {
                                    required property var modelData
                                    property string label: modelData.active ? "[" + modelData.label + "]" : modelData.label
                                    visible: !modelData.name.startsWith("special:") && modelData.monitor?.name === panel.screen.name
                                    width: visible ? workspaceLabel.implicitWidth + 12 : 0
                                    height: 32
                                    Text {
                                        id: workspaceLabel
                                        anchors.centerIn: parent
                                        text: parent.label
                                        color: modelData.urgent ? root.palette.error : (modelData.active || workspaceMouse.containsMouse ? root.palette.accent : root.palette.mutedForeground)
                                        font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18; bold: modelData.active }
                                    }
                                    MouseArea { id: workspaceMouse; anchors.fill: parent; hoverEnabled: true; onClicked: desktop.activateWorkspace(modelData) }
                                }
                            }
                        }
                        // Preserve the hidden alert indicator and its original actions/status colors.
                        Module {
                            id: alertModule
                            theme: root.palette
                            height: 32
                            text: alert.value.text || ""
                            tooltip: alert.value.tooltip || ""
                            background: alert.value.class === "error" ? "#f9a825" : root.statusColor(alert.value)
                            foreground: alert.value.class === "safe" ? root.palette["on-primary"] : root.palette.white
                            leftAction: () => root.run("xdg-open https://alerts.in.ua/")
                            rightAction: () => alert.refresh()
                        }
                        // Live key echo: the held chord first, then entries newest to oldest.
                        // Keys pressed together sit close; separate presses are a space apart.
                        // It fills the bar up to the clock; entries that do not fit fade out whole.
                        Item {
                            id: keystrokesBox
                            visible: keystrokes.opened
                            height: 32
                            width: Math.max(0, panelContent.width / 2 - Math.max(clockLabel.width, volumeLabel.width) / 2 - 16 - leftRow.anchors.leftMargin - x)
                            readonly property bool holding: keystrokes.current.mods.length > 0 || keystrokes.current.key !== ""
                            Row {
                                id: heldRow
                                height: 32
                                spacing: 6
                                Repeater {
                                    model: keystrokesBox.holding ? keystrokes.parts(keystrokes.current) : ["󰌌"]
                                    Text {
                                        required property string modelData
                                        height: 32
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData
                                        color: keystrokesBox.holding ? root.palette.accent : root.palette.mutedForeground
                                        font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18; bold: true }
                                    }
                                }
                            }
                            ListView {
                                id: keystrokesList
                                anchors { left: heldRow.right; leftMargin: 14; top: parent.top; bottom: parent.bottom }
                                width: Math.max(0, keystrokesBox.width - heldRow.width - 14)
                                orientation: ListView.Horizontal
                                spacing: 14
                                clip: true
                                interactive: false
                                model: keystrokes.entries
                                add: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                                        NumberAnimation { property: "x"; from: ViewTransition.destination.x - 28; duration: 220; easing.type: Easing.OutCubic }
                                    }
                                }
                                displaced: Transition { NumberAnimation { property: "x"; duration: 220; easing.type: Easing.OutCubic } }
                                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 400 } }
                                delegate: Item {
                                    id: entry
                                    required property string parts
                                    required property int count
                                    required property int index
                                    width: entryRow.width
                                    height: 32
                                    Row {
                                        id: entryRow
                                        height: 32
                                        spacing: 6
                                        opacity: entry.x + entry.width <= keystrokesList.width ? Math.max(0.3, 1 - entry.index * 0.04) : 0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                        Repeater {
                                            model: entry.parts.split(keystrokes.separator)
                                            Text {
                                                required property string modelData
                                                height: 32
                                                verticalAlignment: Text.AlignVCenter
                                                text: modelData
                                                color: root.palette.foreground
                                                font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 }
                                            }
                                        }
                                        Text {
                                            visible: entry.count > 1
                                            height: 32
                                            verticalAlignment: Text.AlignVCenter
                                            text: "×" + entry.count
                                            color: root.palette.mutedForeground
                                            font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        id: clockLabel
                        anchors.centerIn: parent
                        visible: !root.volumePreviewVisible
                        text: Qt.formatDateTime(clock.date, "dd  HH:mm")
                        color: root.palette.foreground
                        font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 }
                    }
                    Text {
                        id: volumeLabel
                        anchors.centerIn: parent
                        visible: root.volumePreviewVisible
                        text: Pipewire.defaultAudioSink?.audio?.muted ? "MUTE" : "VOL " + root.volumePercent + "%"
                        color: root.palette.accent
                        font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18; bold: true }
                    }
                    Row {
                        id: rightRow
                        anchors { right: parent.right; rightMargin: 12 }
                        height: 32
                        spacing: 10
                        Text {
                            id: dictationIndicator
                            readonly property bool recording: stt.value.class === "recording"
                            visible: recording || stt.value.class === "transcribing"
                            text: recording ? "REC" : (stt.value.text || "ASR")
                            height: 32
                            verticalAlignment: Text.AlignVCenter
                            color: root.palette.foreground
                            font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 }
                        }
                    Item {
                        id: tray
                        width: trayRow.width ? trayRow.width + 4 : 0; height: 32
                        Row {
                            id: trayRow
                            anchors.centerIn: parent
                            spacing: 9
                            Repeater {
                                id: trayRepeater
                                model: SystemTray.items
                                Item {
                                    id: trayItem
                                    required property var modelData
                                    function menuState() { return {id: modelData.id, visible: menu.visible}; }
                                    function setMenuOpen(open) { if (modelData.hasMenu) { if (open) menu.open(); else if (menu.visible) menu.close(); } }
                                    visible: modelData.status !== Status.Passive
                                    width: visible ? 20 : 0; height: 32
                                    Image { anchors.centerIn: parent; width: 20; height: 20; source: modelData.icon; asynchronous: false } // sync: async loads read the SNI pixmap off-thread and segfault when the item unregisters
                                    QsMenuAnchor { id: menu; menu: trayItem.modelData.menu; anchor.item: trayItem; anchor.edges: Edges.Bottom; anchor.gravity: Edges.Bottom }
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        hoverEnabled: true
                                        onClicked: event => {
                                            if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && modelData.onlyMenu)) {
                                                trayItem.setMenuOpen(true);
                                            } else if (event.button === Qt.MiddleButton) modelData.secondaryActivate();
                                            else modelData.activate();
                                        }
                                        onWheel: event => { let horizontal = event.angleDelta.y === 0; modelData.scroll(horizontal ? event.angleDelta.x : event.angleDelta.y, horizontal); }
                                        onContainsMouseChanged: trayTip.visible = containsMouse
                                    }
                                    Tooltip {
                                        id: trayTip
                                        anchor.item: trayItem
                                        theme: root.palette
                                        text: (trayItem.modelData.tooltipTitle || trayItem.modelData.title) + (trayItem.modelData.tooltipDescription ? "\n" + trayItem.modelData.tooltipDescription : "")
                                    }
                                }
                            }
                        }
                    }
                        Text { text: "│"; visible: tray.width > 0; height: 32; verticalAlignment: Text.AlignVCenter; color: root.palette.separator; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 } }
                        Text { text: root.layoutCode; height: 32; verticalAlignment: Text.AlignVCenter; color: root.palette.foreground; font { family: "JetBrainsMonoNL Nerd Font"; pixelSize: 18 } }
                    }
                }
            }
        }
    }
    NotificationPopups { id: notificationPopups; compositor: desktop; theme: root.palette; service: notifications; onOpenCenter: root.openNotificationsCenter() }
    NowPlayingPopup { id: nowPlayingPopup; compositor: desktop; theme: root.palette; service: media }
    ControlCenter {
        id: control
        compositor: desktop
        shell: root
        theme: root.palette
        bluetooth: root.bluetoothState
        opened: root.controlOpen
        media: media
        bookmarks: bookmarks
        metrics: metrics.value
        disk: disk.value
        five: five.value
        weekly: weekly.value
        boot: boot.value
        stt: stt.value
        vpnStatus: vpn.value
        discord: discord.value
        onDiscordActionRequested: action => root.discordAction(action)
        onCloseRequested: root.controlOpen = false
        onNotificationsRequested: root.openNotificationsCenter()
    }
    NotificationsCenter {
        id: notificationsCenter
        compositor: desktop
        theme: root.palette
        notifications: notifications
        shell: root
        opened: root.notificationsOpen && notifications.history.count > 0
        onCloseRequested: root.notificationsOpen = false
        onControlRequested: { root.notificationsOpen = false; root.controlOpen = true }
    }
}
