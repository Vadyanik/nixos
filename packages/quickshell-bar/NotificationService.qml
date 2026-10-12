import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Item {
    id: service
    property var live: ({})
    property bool loaded: false
    property bool doNotDisturb: false
    property int nextId: 1
    property int nextPopupToken: 1
    readonly property int popupAnimationDuration: 500
    property int historyRevision: 0
    readonly property alias history: history
    readonly property alias popups: popups
    onDoNotDisturbChanged: {
        if (doNotDisturb) {
            for (let i = 0; i < popups.count; i++) popups.setProperty(i, "closing", true);
        }
    }
    ListModel { id: history; dynamicRoles: true }
    ListModel { id: popups; dynamicRoles: true }
    function appIconSource(app, desktop) {
        let name = String(desktop || "").replace(/\.desktop$/i, "");
        if (/chatgpt|codex/i.test(String(app || "") + " " + name)) name = "codex-desktop";
        if (!name) name = String(app || "").toLowerCase().replace(/\s+/g, "-");
        return name ? Quickshell.iconPath(name) : "";
    }
    function ignored(app, desktop) { return /polter[- ]?type|mullvad/i.test((app || "") + " " + (desktop || "")); }
    function pruneChatGptHistory() {
        let cutoff = Date.now() - 60000;
        let changed = false;
        for (let i = history.count - 1; i >= 0; i--) {
            let row = history.get(i);
            if (/chatgpt/i.test(row.app || "") && row.time <= cutoff) {
                history.remove(i);
                changed = true;
            }
        }
        if (changed) persist();
    }
    FileView {
        id: saved
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-notifications.json"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        try {
            for (let row of JSON.parse(saved.text() || "[]")) {
                if (ignored(row.app, "") || (!row.title && !row.body)) continue;
                row.liveId = 0; history.append(row); nextId = Math.max(nextId, row.id + 1);
            }
        } catch (e) { console.warn("Notification history", e); }
        loaded = true;
        pruneChatGptHistory();
        historyRevision++;
        persist();
    }
    Timer { interval: 1000; running: service.loaded; repeat: true; onTriggered: service.pruneChatGptHistory() }
    function persist() {
        historyRevision++;
        if (!loaded) return;
        let rows = [];
        for (let i = 0; i < history.count; i++) {
            let row = history.get(i);
            rows.push({id: row.id, liveId: 0, app: row.app, desktop: row.desktop || "", icon: row.icon.startsWith("image://") ? "" : row.icon, title: row.title, body: row.body, time: row.time});
        }
        saved.setText(JSON.stringify(rows));
    }
    function hidePopup(id) {
        for (let i = 0; i < popups.count; i++) if (popups.get(i).id === id) popups.setProperty(i, "closing", true);
    }
    function hidePopupByToken(token) {
        for (let i = 0; i < popups.count; i++) if (popups.get(i).token === token) { popups.setProperty(i, "closing", true); return; }
    }
    function hidePopupByLiveId(liveId) {
        for (let i = 0; i < popups.count; i++) if (popups.get(i).liveId === liveId) popups.setProperty(i, "closing", true);
    }
    function removePopup(token) {
        for (let i = 0; i < popups.count; i++) if (popups.get(i).token === token) { popups.remove(i); return; }
    }
    function dismiss(id) {
        let target = null;
        for (let model of [history, popups]) {
            for (let i = 0; i < model.count; i++) if (model.get(i).id === id) {
                target = target || live[model.get(i).liveId];
                if (model === popups) service.hidePopupByToken(model.get(i).token);
                else model.remove(i);
                break;
            }
        }
        if (target) target.dismiss();
        persist();
    }
    function dismissGroup(app) {
        let ids = [];
        for (let i = 0; i < history.count; i++) if (history.get(i).app === app) ids.push(history.get(i).id);
        for (let id of ids) dismiss(id);
    }
    function openNotification(id) {
        let row = null;
        for (let model of [history, popups]) {
            for (let i = 0; i < model.count; i++) if (model.get(i).id === id) { row = model.get(i); break; }
            if (row) break;
        }
        if (!row) return;
        let notification = live[row.liveId];
        let defaultAction = (notification?.actions || []).find(a => a.identifier === "default");
        if (defaultAction) defaultAction.invoke();
        let desktop = row.desktop || "";
        if (!defaultAction && desktop) Quickshell.execDetached(["gio", "launch", desktop]);
        Quickshell.execDetached(["desktop-focus", "--app", row.app || "", "--desktop", desktop]);
    }
    function expirePopup(id, token) {
        for (let i = 0; i < popups.count; i++) if (popups.get(i).id === id && (token === undefined || popups.get(i).token === token)) {
            let row = popups.get(i);
            if (live[row.liveId]) live[row.liveId].expire();
            hidePopupByToken(row.token); return;
        }
    }
    function clear() {
        for (let notification of server.trackedNotifications.values.slice()) notification.dismiss();
        for (let i = 0; i < popups.count; i++) popups.setProperty(i, "closing", true);
        history.clear(); persist();
    }
    function snapshot() {
        let rows = [];
        for (let i = 0; i < history.count; i++) { let row = history.get(i); rows.push({id: row.id, title: row.title, app: row.app, time: row.time}); }
        return rows;
    }
    function popupSnapshot() { let rows = []; for (let i = 0; i < popups.count; i++) rows.push({id: popups.get(i).id, app: popups.get(i).app, title: popups.get(i).title, timeout: popups.get(i).timeout}); return rows; }
    NotificationServer {
        id: server
        persistenceSupported: true
        bodySupported: true
        imageSupported: true
        actionsSupported: true
        keepOnReload: true
        onNotification: notification => {
            notification.tracked = true;
            if (service.ignored(notification.appName, notification.desktopEntry)) { notification.dismiss(); return; }
            if (!notification.summary && !notification.body) { notification.tracked = false; return; }
            let previous = -1;
            for (let i = 0; i < history.count; i++) if (history.get(i).liveId === notification.id) { previous = i; break; }
            if (previous < 0 && notification.lastGeneration) {
                for (let i = 0; i < history.count; i++) {
                    let row = history.get(i);
                    if (row.app === notification.appName && row.title === notification.summary && row.body === notification.body) { previous = i; break; }
                }
            }
            let timestamp = previous >= 0 ? history.get(previous).time : Date.now();
            let row = {id: previous >= 0 ? history.get(previous).id : service.nextId++, liveId: notification.id, app: notification.appName, desktop: notification.desktopEntry || "", icon: notification.appIcon || notification.image, title: notification.summary, body: notification.body, time: timestamp};
            live[notification.id] = notification;
            if (!notification.transient) {
                if (previous >= 0) history.set(previous, row); else history.insert(0, row);
            }
            if (!notification.lastGeneration && !service.doNotDisturb) {
                service.hidePopup(row.id);
                popups.insert(0, Object.assign({}, row, {timeout: notification.expireTimeout === 0 ? 0 : (notification.expireTimeout > 0 ? notification.expireTimeout : 6000), token: service.nextPopupToken++, closing: false}));
                while (popups.count > 3) { let old = popups.get(popups.count - 1); service.expirePopup(old.id, old.token); }
            }
            // ponytail: keep the newest 200 entries; older history can be archived if needed.
            while (history.count > 200) { let old = history.get(history.count - 1); if (live[old.liveId]) live[old.liveId].expire(); history.remove(history.count - 1); }
            service.persist();
        }
    }
    Instantiator {
        model: server.trackedNotifications
        delegate: QtObject {
            required property var modelData
            property var connection: Connections {
                target: modelData
                function onClosed() {
                    // Client-requested closure also removes its visible toast.
                    service.hidePopupByLiveId(modelData.id);
                    delete service.live[modelData.id];
                }
                function onSummaryChanged() { sync(); }
                function onBodyChanged() { sync(); }
                function sync() {
                    for (let model of [history, popups]) for (let i = 0; i < model.count; i++) if (model.get(i).liveId === modelData.id) { model.setProperty(i, "title", modelData.summary); model.setProperty(i, "body", modelData.body); }
                    service.persist();
                }
            }
        }
    }
}
