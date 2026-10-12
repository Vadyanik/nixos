import QtQuick
import Quickshell.Io

Item {
    id: poll
    visible: false
    property var command: []
    property int interval: 1000
    property bool json: true
    property var value: ({text: ""})
    property bool pending: false
    function refresh() {
        if (process.running) pending = true;
        else process.running = true;
    }
    Process {
        id: process
        command: poll.command
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { poll.value = poll.json ? JSON.parse(text) : {text: text.trim()}; }
                catch (e) { console.warn("Invalid module output", poll.command[0], e); }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) console.warn("Module failed", poll.command[0], code);
            if (poll.pending) { poll.pending = false; poll.refresh(); }
        }
    }
    Timer { interval: poll.interval; running: poll.interval > 0; repeat: true; onTriggered: poll.refresh() }
}
