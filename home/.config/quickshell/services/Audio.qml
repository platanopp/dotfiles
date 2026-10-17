pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Sound: the output's volume and mute, the microphone, the devices on either
// side, and the per-app streams. wpctl and pactl do the work; `pactl
// subscribe` says when anything changed, so the poll at the bottom is only a
// safety net.
Singleton {
    id: root

    // ── Output: volume and mute ──────────────────────────────────────────
    //
    // The default output's level and mute: the sound panel's slider, the
    // scroll on the bar's sound icon, the media panel.
    property real volumePercent: 50
    property bool volumeMuted: false

    function toggleVolumeMute() {
        volumeSetProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        volumeSetProc.running = true
        root.volumeMuted = !root.volumeMuted
    }

    function setVolume(percent) {
        var clamped = Math.max(0, Math.min(100, Math.round(percent)))
        root.volumePercent = clamped
        volumeThrottle.pendingValue = clamped
        // First move of a drag is sent straight away; the timer then rate
        // limits the rest and delivers the last one. See volumeThrottle.
        if (!volumeThrottle.running) {
            volumeThrottle.send()
            volumeThrottle.start()
        }
    }

    Process {
        id: volumeGetProc
        running: false
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "Volume: 0.71" or "Volume: 0.71 [MUTED]"
                var m = /Volume:\s*([\d.]+)/.exec(text)
                var v = m ? Math.round(parseFloat(m[1]) * 100) : NaN
                if (!volumeSetProc.running) root.volumeMuted = text.indexOf("MUTED") !== -1
                // Mid-drag this reading is already out of date -- it was
                // taken before the moves still in flight -- and applying it
                // would drag the handle backwards under the pointer.
                if (volumeThrottle.running || volumeSetProc.running)
                    return
                if (!isNaN(v)) root.volumePercent = v
            }
        }
    }

    Process {
        id: volumeSetProc
        running: false
    }

    // Dragging the volume slider calls setVolume() on every mouse move, and
    // each one costs a process. This used to be a 150ms debounce that
    // restart()ed on every move -- which never fires *during* a drag, only
    // once the pointer stops, so the sound stayed put while the handle moved
    // and only caught up at the end.
    //
    // A throttle instead: the first move is sent immediately, further moves
    // at most one per interval, and the value the drag ended on is always
    // sent -- the timer keeps running until what was sent matches what is
    // pending, so the last move cannot be the one that gets dropped.
    Timer {
        id: volumeThrottle
        interval: 45
        repeat: true
        property int pendingValue: 50
        // -1 rather than 0, so the first send happens even at zero.
        property int sentValue: -1

        function send() {
            // wpctl is quick, but a tick can still land on top of the
            // previous one; Process ignores a command set while running, so
            // sending now would be a silent no-op. Leave sentValue behind
            // instead and the next tick retries.
            if (volumeSetProc.running)
                return
            volumeSetProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", volumeThrottle.pendingValue + "%"]
            volumeSetProc.running = true
            volumeThrottle.sentValue = volumeThrottle.pendingValue
        }

        onTriggered: {
            if (volumeThrottle.pendingValue === volumeThrottle.sentValue) {
                volumeThrottle.stop()
                return
            }
            volumeThrottle.send()
        }
    }

    // ── Output devices ───────────────────────────────────────────────────
    //
    // Where the sound goes, and which is the default.
    property var audioSinks: []

    function refreshAudioSinks() {
        audioSinksProc.running = true
    }

    function parseAudioSinks(text) {
        var lines = text.trim().length > 0 ? text.trim().split("\n") : []
        var list = []
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|")
            if (parts.length < 3) continue
            list.push({ id: parts[0], name: parts[1], isDefault: parts[2] === "1" })
        }
        root.audioSinks = list
    }

    function setDefaultSink(id) {
        setSinkProc.command = ["bash", "-c", "wpctl set-default " + id]
        setSinkProc.running = true
        audioSinksRefreshTimer.restart()
    }

    Process {
        id: audioSinksProc
        running: false
        command: ["bash", "-c", "bash \"$HOME/.config/quickshell/scripts/audio_sinks.sh\""]
        stdout: StdioCollector {
            onStreamFinished: root.parseAudioSinks(text)
        }
    }

    Process {
        id: setSinkProc
        running: false
    }

    Timer {
        id: audioSinksRefreshTimer
        interval: 400
        onTriggered: audioSinksProc.running = true
    }

    // ── All outputs at once ──────────────────────────────────────────────
    //
    // Settings -> Sound: one combined output that plays through every device
    // (scripts/audio_all_outputs.sh). It is a PipeWire module, gone whenever
    // PipeWire is, so the choice is kept in ShellSettings and put back at
    // start and after PipeWire restarts (audioEvents, below).
    readonly property bool allOutputs: ShellSettings.audioAllOutputs

    function setAllOutputs(on) {
        ShellSettings.set("audioAllOutputs", on)
        root.applyAllOutputs(on)
    }

    function applyAllOutputs(on) {
        allOutputsProc.command = ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/audio_all_outputs.sh",
                                  on ? "on" : "off"]
        allOutputsProc.running = true
    }

    Process {
        id: allOutputsProc
        running: false
        // The device list and the volume then show the combined output (or
        // the one it went back to) as the default.
        onExited: {
            audioSinksProc.running = true
            if (!volumeGetProc.running) volumeGetProc.running = true
        }
    }

    // ── Microphone ───────────────────────────────────────────────────────
    //
    // Mute, from the bar, the control panel, Settings and a global shortcut
    // (shell.qml); each toggle answers with a sound.
    property bool micMuted: false

    function toggleMicMute() {
        micToggleProc.command = ["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"]
        micToggleProc.running = true
        root.micMuted = !root.micMuted
        // Cued off the state we just moved to rather than off a re-read: the
        // sound is the answer to the key press, and waiting for wpctl to be
        // asked back would put it a poll behind the thing it is confirming.
        root.playCue(root.micMuted ? "device-removed" : "device-added")
    }

    // A short sound from the freedesktop theme, by name.
    //
    // device-added and device-removed are a rising and a falling pair, which
    // is the distinction that matters here: muted or not has to be audible
    // without looking, and two sounds that differ only in being sounds would
    // not tell you which way the toggle went.
    //
    // Detached on purpose. The cue is 0.22s and the shortcut can be pressed
    // again inside that, and the second press should be heard rather than
    // cancelling the first -- which is what re-running a tracked Process
    // would do.
    function playCue(name) {
        cueProc.command = ["bash", "-c",
            "exec setsid pw-play --volume=0.5 \"/usr/share/sounds/freedesktop/stereo/$1.oga\" >/dev/null 2>&1 &",
            "_", name]
        cueProc.running = true
    }

    Process {
        id: cueProc
        running: false
    }

    Process {
        id: micMutedProc
        running: false
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo true || echo false"]
        stdout: StdioCollector {
            onStreamFinished: root.micMuted = text.trim() === "true"
        }
    }

    // Read once at start; pactl subscribe (audioEvents, below) keeps it
    // current after that.
    Component.onCompleted: {
        micMutedProc.running = true
        if (root.allOutputs) root.applyAllOutputs(true)
    }

    Process {
        id: micToggleProc
        running: false
    }

    // ── Input devices and the microphone's level ─────────────────────────
    //
    // For the Settings window's Sound page. The bar only ever needed mute;
    // choosing the capture device and its level is new.
    property var audioSources: []
    property real micVolume: 100

    function refreshAudioSources() {
        if (!audioSourcesProc.running) audioSourcesProc.running = true
        if (!micVolumeProc.running) micVolumeProc.running = true
    }

    function setDefaultSource(id) {
        audioSourceSetProc.command = ["wpctl", "set-default", String(id)]
        audioSourceSetProc.running = true
        audioSourcesRefresh.restart()
    }

    function setMicVolume(percent) {
        var v = Math.max(0, Math.min(150, Math.round(percent)))
        root.micVolume = v
        micVolumeSetProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", (v / 100).toFixed(2)]
        micVolumeSetProc.running = true
    }

    Process {
        id: audioSourcesProc
        running: false
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/audio_sources.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().length > 0 ? text.trim().split("\n") : []
                var list = []
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("|")
                    if (parts.length < 3) continue
                    list.push({ id: parts[0], name: parts[1], isDefault: parts[2] === "1" })
                }
                root.audioSources = list
            }
        }
    }

    Process {
        id: micVolumeProc
        running: false
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = /Volume:\s*([0-9.]+)/.exec(text)
                if (m) root.micVolume = Math.round(parseFloat(m[1]) * 100)
            }
        }
    }

    Process { id: audioSourceSetProc; running: false }
    Process { id: micVolumeSetProc; running: false }

    // wpctl answers before PipeWire has moved the default, so the list is
    // read again a moment later rather than straight away.
    Timer {
        id: audioSourcesRefresh
        interval: 400
        onTriggered: root.refreshAudioSources()
    }

    // ── Per-app streams ──────────────────────────────────────────────────
    //
    // What each application is playing, for the per-app sliders in the
    // sound panel, the media panel and Settings -> Sound.
    property var audioStreams: []
    property bool audioStreamsDragging: false

    // The stream list is polled only while something is showing it, and more
    // than one panel now does -- the audio panel and the media widget, once
    // per monitor. A count rather than a flag, so the last one to close is
    // the one that stops the polling.
    property int audioStreamWatchers: 0

    function refreshAudioStreams() {
        audioStreamsProc.running = true
    }

    function parseAudioStreams(text) {
        try {
            root.audioStreams = JSON.parse(text)
        } catch (e) {
            root.audioStreams = []
        }
    }

    function watchAudioStreams() {
        root.audioStreamWatchers++
        // The first watcher opens onto whatever the list was when it last
        // closed, so it is refreshed now instead of a poll interval later.
        if (root.audioStreamWatchers === 1)
            root.refreshAudioStreams()
    }

    function unwatchAudioStreams() {
        root.audioStreamWatchers = Math.max(0, root.audioStreamWatchers - 1)
    }

    // "PipeWire ALSA [osu!]" is how a Wine game's stream is named; the part
    // in brackets is the name worth showing.
    function streamName(n) {
        var m = /\[(.+)\]\s*$/.exec(n || "")
        return m ? m[1] : (n || "Unknown")
    }

    // Which sink input a media player is feeding.
    //
    // The script resolves this through the process that owns the MPRIS bus
    // name, which is exact where it works. It does not work for a player
    // whose stream has gone away -- a paused browser drops it -- so the
    // caller has to handle a null.
    function streamForPlayer(player) {
        if (!player) return null

        var bus = player.dbusName || ""
        var list = root.audioStreams
        for (var i = 0; i < list.length; i++) {
            var owners = list[i].mpris || []
            for (var j = 0; j < owners.length; j++) {
                if (owners[j] === bus) return list[i]
            }
        }

        // Fallback for a player the bus lookup missed: match the names the
        // two sides do agree on. Kept loose on purpose -- "Spotify" the
        // MPRIS identity against "spotify" the node name -- and only used
        // when the exact link found nothing.
        var keys = []
        var entry = (player.desktopEntry || "").toLowerCase()
        var identity = (player.identity || "").toLowerCase()
        if (entry.length > 2) keys.push(entry)
        if (identity.length > 2) keys.push(identity)
        if (keys.length === 0) return null

        for (var k = 0; k < list.length; k++) {
            var name = (list[k].name || "").toLowerCase()
            if (name.length < 3) continue
            for (var m = 0; m < keys.length; m++) {
                if (name === keys[m] || name.indexOf(keys[m]) !== -1
                        || keys[m].indexOf(name) !== -1)
                    return list[k]
            }
        }
        return null
    }

    function resolveAppIcon(candidates) {
        for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i]
            if (!c || c.length === 0) continue
            var p = Quickshell.iconPath(c, true)
            if (p && p.length > 0) return p
        }
        return Quickshell.iconPath("audio-x-generic")
    }

    function setStreamVolume(id, percent) {
        var clamped = Math.max(0, Math.min(150, Math.round(percent)))
        setStreamVolumeProc.command = ["pactl", "set-sink-input-volume", id, clamped + "%"]
        setStreamVolumeProc.running = true
    }

    Process {
        id: setStreamVolumeProc
        running: false
    }

    // The per-app sliders had the same trailing debounce as the master one,
    // and the same symptom: an app's volume only moved once you let go.
    Timer {
        id: streamVolumeThrottle
        interval: 45
        repeat: true
        property string pendingId: ""
        property int pendingValue: 0
        property string sentId: ""
        property int sentValue: -1

        function send() {
            if (setStreamVolumeProc.running)
                return
            root.setStreamVolume(streamVolumeThrottle.pendingId, streamVolumeThrottle.pendingValue)
            streamVolumeThrottle.sentId = streamVolumeThrottle.pendingId
            streamVolumeThrottle.sentValue = streamVolumeThrottle.pendingValue
        }

        onTriggered: {
            if (streamVolumeThrottle.pendingId === streamVolumeThrottle.sentId
                    && streamVolumeThrottle.pendingValue === streamVolumeThrottle.sentValue) {
                streamVolumeThrottle.stop()
                return
            }
            streamVolumeThrottle.send()
        }
    }

    function setStreamVolumeThrottled(id, value) {
        streamVolumeThrottle.pendingId = id
        streamVolumeThrottle.pendingValue = value
        if (!streamVolumeThrottle.running) {
            streamVolumeThrottle.send()
            streamVolumeThrottle.start()
        }
    }

    Process {
        id: audioStreamsProc
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/audio_streams.py"]
        stdout: StdioCollector {
            onStreamFinished: root.parseAudioStreams(text)
        }
    }

    // Volumes also move from outside this shell, so the list is re-read while
    // anything is showing it. Paused mid-drag: a poll landing between a write
    // and pactl catching up reports the old volume and snaps the slider back
    // under the pointer.
    Timer {
        id: audioStreamsPollTimer
        interval: 1500
        repeat: true
        running: root.audioStreamWatchers > 0
        onTriggered: if (!root.audioStreamsDragging) root.refreshAudioStreams()
    }

    // ── Audio changes, as they happen ────────────────────────────────────
    //
    // `pactl subscribe` prints a line whenever a sink, source or stream
    // changes; the volume and mute are read then, rather than asking wpctl
    // every three seconds whether anything moved. A burst of events (a drag
    // on a slider, an app starting) is read once.
    Process {
        id: audioEvents
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("on sink") !== -1 || line.indexOf("on server") !== -1) audioEventDebounce.sink = true
                if (line.indexOf("on source") !== -1 || line.indexOf("on server") !== -1) audioEventDebounce.source = true
                if (audioEventDebounce.sink || audioEventDebounce.source) audioEventDebounce.restart()
            }
        }
        // Should pactl go (PipeWire restarting), start it again shortly.
        onExited: audioEventsRestart.restart()
    }

    Timer {
        id: audioEventsRestart
        interval: 2000
        onTriggered: {
            audioEvents.running = true
            // A new PipeWire has no combined output; put it back.
            if (root.allOutputs) root.applyAllOutputs(true)
        }
    }

    Timer {
        id: audioEventDebounce
        property bool sink: false
        property bool source: false
        interval: 80
        onTriggered: {
            if (audioEventDebounce.sink && !volumeGetProc.running) volumeGetProc.running = true
            if (audioEventDebounce.source && !micMutedProc.running) micMutedProc.running = true
            audioEventDebounce.sink = false
            audioEventDebounce.source = false
        }
    }

    // Belt and braces for the events above: a slow poll in case one is lost.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        // Volume only. CPU, memory, disk and temperature were polled here
        // too, four processes every three seconds, for gauges that have since
        // left the control panel and the clock; nothing reads them now.
        onTriggered: volumeGetProc.running = true
    }
}
