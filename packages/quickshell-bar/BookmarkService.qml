import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: service
    required property string scripts
    property var result: ({sections: [], path: "", error: ""})
    property bool pending: false
    function refresh() { if (loader.running) pending = true; else loader.running = true; }
    function openId(id) { Quickshell.execDetached(["python3", scripts + "librewolf_bookmarks.py", "--open", id]); }
    function snapshot() { return {path: result.path, profile: result.profile, error: result.error, sections: result.sections.map(g => ({title: g.title, count: g.bookmarks.length, icons: g.bookmarks.filter(b => b.icon.length).length})), count: result.sections.reduce((n, g) => n + g.bookmarks.length, 0)}; }
    Process {
        id: loader
        command: ["python3", service.scripts + "librewolf_bookmarks.py"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { service.result = JSON.parse(text); } catch (e) { console.warn("Bookmarks", e); } } }
        onExited: { if (service.pending) { service.pending = false; service.refresh(); } }
    }
    FileView {
        path: service.result.path || ""
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); debounce.restart(); }
    }
    FileView {
        path: service.result.path ? service.result.path + "-wal" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); debounce.restart(); }
    }
    Timer { id: debounce; interval: 500; onTriggered: service.refresh() }
    Timer { interval: 10000; repeat: true; running: true; onTriggered: service.refresh() }
}
