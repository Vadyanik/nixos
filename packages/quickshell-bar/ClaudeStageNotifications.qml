import QtQuick
import Quickshell

Item {
    id: monitor
    property var five: ({})
    property var weekly: ({})
    property var previous: ({})
    property var limits: ({})
    property var resetTimes: ({})
    property var notify: (title, body) => Quickshell.execDetached(["notify-send", "--app-name=Claude", "--expire-time=8000", "--", title, body])
    function observe(window, value) {
        value = value || {};
        let stage = value.class || "";
        // Unavailable data is not a score stage; retain the last valid stage.
        if (!["excess", "surplus", "full", "warn", "low", "critical"].includes(stage)) return;
        let before = previous[window];
        if (before === stage) return;
        let updated = Object.assign({}, previous);
        updated[window] = stage;
        previous = updated;
        // Establish a quiet baseline at startup/reload.
        if (!before) return;
        let index = window === "five" ? 0 : 1;
        let details = (value.tooltip || "").split("\n").slice(index * 2, index * 2 + 2).join("\n").trim().replace(/^(5h|Weekly): /, "Score: ");
        notify(window === "five" ? "Five Hour Limit" : "Weekly Limit", before.toUpperCase() + " → " + stage.toUpperCase() + (details ? "\n" + details : ""));
    }
    function checkResets(now) {
        let updated = Object.assign({}, resetTimes);
        for (let window of ["five", "weekly"]) {
            let reset = updated[window] || 0;
            if (reset > 0 && reset <= now) {
                updated[window] = 0;
                notify(window === "five" ? "Five Hour Limit Reset" : "Weekly Limit Reset", window === "five" ? "The five-hour usage window has reset." : "The weekly usage window has reset.");
            }
        }
        resetTimes = updated;
    }
    function observeResets(data, now) {
        data = data || {};
        checkResets(now);
        let updated = Object.assign({}, resetTimes);
        for (let window of [{name: "five", duration: 300}, {name: "weekly", duration: 10080}]) {
            let limit = [data.primary, data.secondary].find(l => l?.windowDurationMins === window.duration);
            // Arm only future deadlines; do not announce old resets on startup.
            if (limit?.resetsAt > now) updated[window.name] = limit.resetsAt;
        }
        resetTimes = updated;
    }
    SystemClock { precision: SystemClock.Seconds; onDateChanged: monitor.checkResets(date.getTime() / 1000) }
    onLimitsChanged: observeResets(limits, Date.now() / 1000)
    onFiveChanged: observe("five", five)
    onWeeklyChanged: observe("weekly", weekly)
}
