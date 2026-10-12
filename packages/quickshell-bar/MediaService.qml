import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: service
    required property string scripts
    required property var compositor
    property string selected: ""
    property bool controlOpen: false
    property bool doNotDisturb: false
    property var nowPlaying: ({})
    property var knownTracks: ({})
    Component.onCompleted: {
        let initial = {};
        for (let p of Mpris.players.values) initial[p.dbusName] = trackKey(p);
        knownTracks = initial;
    }
    readonly property var trackedPlayer: Mpris.players.values.find(p => p.dbusName === selected) || Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    // Chromium can leave an empty, stopped MPRIS session with its app icon as art.
    // Keep controls for real playback while metadata loads, but ignore idle shells.
    readonly property var availablePlayers: Mpris.players.values.filter(p => !isTeamsPlayback(p) && (hasTrack(p) || p.isPlaying || p.canTogglePlaying))
    readonly property var player: availablePlayers.find(p => p.dbusName === selected) || availablePlayers.find(p => p.isPlaying) || availablePlayers[0] || null
    function hasTrack(p) { return String(p?.trackTitle || "").trim().length > 0; }
    function displayTitle(p) { return hasTrack(p) ? p.trackTitle : (p?.identity || "Media playback"); }
    function isTeamsPlayback(p) { return /\bmicrosoft\s*teams\b|\bteams\b/i.test([p?.identity, p?.desktopEntry, p?.dbusName, p?.trackTitle, p?.trackArtist].join(" ")); }
    function trackKey(p) { return [p.trackTitle, p.trackArtist, p.trackArtUrl].join("\u0000"); }
    function focusPlayer(playerId) {
        const p = Mpris.players.values.find(candidate => candidate.dbusName === playerId);
        if (p) Quickshell.execDetached(["bash", service.scripts + "focus_mpris_player.sh", p.identity || "", p.desktopEntry || "", p.dbusName || ""]);
    }
    function normalized(value) { return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, ""); }
    function playerIsFocused(p) {
        const active = compositor.focusedWindow || {};
        if (!p || !(active.class || active.app_id)) return false;
        const activeClass = normalized(active.class || active.app_id);
        const busName = String(p.dbusName || "").replace(/\.instance\d+$/, "").replace(/^org\.mpris\.MediaPlayer2\./, "");
        const candidates = [normalized(p.identity), normalized(p.desktopEntry), normalized(busName)].filter(value => value.length > 2);
        if (active.pid && new RegExp("\\.instance" + active.pid + "$").test(p.dbusName || "")) return true;
        return candidates.some(value => activeClass === value || activeClass.includes(value) || value.includes(activeClass));
    }
    function observe(p) {
        if (!p) return;
        const key = trackKey(p);
        const previous = knownTracks[p.dbusName];
        let updated = Object.assign({}, knownTracks);
        updated[p.dbusName] = key;
        knownTracks = updated;
        if (previous !== undefined && previous !== key && p.isPlaying) showTrack(p);
    }
    function playbackChanged(p) {
        if (p?.isPlaying) {
            const key = trackKey(p);
            if (knownTracks[p.dbusName] !== key) showTrack(p);
        }
    }
    function showTrack(p) {
        if (isTeamsPlayback(p)) { if (nowPlaying.player === p.dbusName) hideTrack(); return; }
        if (controlOpen || doNotDisturb || !p.isPlaying || !hasTrack(p)) return;
        if (playerIsFocused(p)) { hideTrack(); return; }
        let updated = Object.assign({}, knownTracks);
        updated[p.dbusName] = trackKey(p);
        knownTracks = updated;
        nowPlaying = {title: p.trackTitle, artist: p.trackArtist || "", art: p.trackArtUrl || "", key: trackKey(p), player: p.dbusName};
        popupTimer.restart();
    }
    function hideTrack() { popupTimer.stop(); nowPlaying = {}; }
    Connections {
        target: service.trackedPlayer
        function onPostTrackChanged() { service.observe(service.trackedPlayer); }
        function onIsPlayingChanged() { service.playbackChanged(service.trackedPlayer); }
    }
    Connections {
        target: service.compositor
        function onFocusedWindowChanged() {
            const toastPlayer = Mpris.players.values.find(p => p.dbusName === service.nowPlaying.player);
            if (toastPlayer && service.playerIsFocused(toastPlayer)) service.hideTrack();
        }
    }
    Timer { id: popupTimer; interval: 5000; onTriggered: service.hideTrack() }
    onControlOpenChanged: if (controlOpen) hideTrack()
    onDoNotDisturbChanged: if (doNotDisturb) hideTrack()
    function cycle(direction) {
        let players = availablePlayers;
        if (!players.length) return;
        let index = players.indexOf(player);
        selected = players[(index + direction + players.length) % players.length].dbusName;
    }
    function snapshot() { return player ? {title: player.trackTitle, artist: player.trackArtist, art: player.trackArtUrl, playing: player.isPlaying, position: player.position, length: player.length, player: player.dbusName, identity: player.identity, desktopEntry: player.desktopEntry, playerFocused: playerIsFocused(player), canPrevious: player.canGoPrevious, canNext: player.canGoNext, canToggle: player.canTogglePlaying, canSeek: player.canSeek, positionSupported: player.positionSupported, lengthSupported: player.lengthSupported} : {}; }
}
