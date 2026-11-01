pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Sound: output volume and mute, the microphone, devices and per-app streams, via wpctl and pactl.
// `pactl subscribe` reports changes, so the poll at the bottom is only a safety net.
Singleton {
    id: root

    // Output: the default output's level and mute (the sound panel's slider, the bar
    // icon's scroll, the media panel).
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
        // The first move of a drag is sent at once; the timer rate-limits the rest and
        // delivers the last (volumeThrottle).
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
                // Mid-drag this reading is already stale, and applying it would pull the
                // handle back under the pointer.
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

    // A throttle, not a debounce: a restarting debounce never fired during a drag, so the
    // sound lagged until release. The first move goes at once, then one per interval, and the
    // timer runs until the last value is sent.
    Timer {
        id: volumeThrottle
        interval: 45
        repeat: true
        property int pendingValue: 50
        // -1 rather than 0, so the first send happens even at zero.
        property int sentValue: -1

        function send() {
            // A tick can land while the previous wpctl still runs, and Process ignores a command
            // set then; leave sentValue behind and the next tick retries.
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

    // Output devices: where the sound goes, and which is the default.
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
            list.push({ id: parts[0], name: parts[1], isDefault: parts[2] === "1",
                        volume: parts.length > 3 ? parseInt(parts[3]) : 100 })
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

    // One device's own level (with All outputs on, Settings -> Sound),
    // throttled like the master slider.
    function setSinkVolume(id, percent) {
        sinkVolumeThrottle.pendingId = String(id)
        sinkVolumeThrottle.pendingValue = Math.max(0, Math.min(150, Math.round(percent)))
        if (!sinkVolumeThrottle.running) {
            sinkVolumeThrottle.send()
            sinkVolumeThrottle.start()
        }
    }

    Process {
        id: sinkVolumeProc
        running: false
    }

    Timer {
        id: sinkVolumeThrottle
        interval: 45
        repeat: true
        property string pendingId: ""
        property int pendingValue: 0
        property string sentId: ""
        property int sentValue: -1

        function send() {
            if (sinkVolumeProc.running)
                return
            sinkVolumeProc.command = ["wpctl", "set-volume", sinkVolumeThrottle.pendingId,
                                      sinkVolumeThrottle.pendingValue + "%"]
            sinkVolumeProc.running = true
            sinkVolumeThrottle.sentId = sinkVolumeThrottle.pendingId
            sinkVolumeThrottle.sentValue = sinkVolumeThrottle.pendingValue
        }

        onTriggered: {
            if (sinkVolumeThrottle.pendingId === sinkVolumeThrottle.sentId
                    && sinkVolumeThrottle.pendingValue === sinkVolumeThrottle.sentValue) {
                sinkVolumeThrottle.stop()
                return
            }
            sinkVolumeThrottle.send()
        }
    }

    Timer {
        id: audioSinksRefreshTimer
        interval: 400
        onTriggered: audioSinksProc.running = true
    }

    // All outputs at once (Settings -> Sound): a PipeWire module combining every device
    // (audio_all_outputs.sh). It dies with PipeWire, so the choice lives in ShellSettings and is
    // restored at start and after restarts.
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
        // The device list and volume then show the combined output (or the one it
        // went back to) as the default.
        onExited: {
            audioSinksProc.running = true
            if (!volumeGetProc.running) volumeGetProc.running = true
        }
    }

    // Microphone mute, from the bar, the control panel, Settings and a global
    // shortcut; each toggle plays a cue.
    property bool micMuted: false

    function toggleMicMute() {
        micToggleProc.command = ["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"]
        micToggleProc.running = true
        root.micMuted = !root.micMuted
        // Cued off the new state rather than a re-read, so the sound isn't
        // a poll behind the key press.
        root.playCue(root.micMuted ? "device-removed" : "device-added")
    }

    // A short freedesktop sound: device-added/removed rise and fall, so the direction is audible.
    // Detached, so a second press within the 0.22s cue is heard rather than cancelling the first.
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

    // Read once at start; pactl subscribe (audioEvents) keeps it current.
    Component.onCompleted: {
        micMutedProc.running = true
        if (root.allOutputs) root.applyAllOutputs(true)
    }

    Process {
        id: micToggleProc
        running: false
    }

    // Input devices and the microphone's level, for Settings -> Sound.
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

    // wpctl answers before PipeWire moves the default, so re-read a moment later.
    Timer {
        id: audioSourcesRefresh
        interval: 400
        onTriggered: root.refreshAudioSources()
    }

    // Per-app streams, for the per-app sliders in the sound panel, the media
    // panel and Settings -> Sound.
    property var audioStreams: []
    property bool audioStreamsDragging: false

    // Polled only while something shows it (the audio panel, the media widget per monitor): a
    // count, so the last to close stops it.
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
        // The first watcher sees the list as it was when last closed, so refresh now.
        if (root.audioStreamWatchers === 1)
            root.refreshAudioStreams()
    }

    function unwatchAudioStreams() {
        root.audioStreamWatchers = Math.max(0, root.audioStreamWatchers - 1)
    }

    // "PipeWire ALSA [osu!]" is how a Wine game's stream is named; the
    // bracketed part is worth showing.
    function streamName(n) {
        var m = /\[(.+)\]\s*$/.exec(n || "")
        return m ? m[1] : (n || "Unknown")
    }

    // Which sink input a media player feeds, via the process owning its MPRIS bus name. Null when
    // the stream has gone (a paused browser drops it).
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

        // Fallback when the bus lookup missed: a loose name match ("Spotify"
        // identity against "spotify" node).
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

    // Throttled like the master slider: a debounce only moved the app's volume once you let go.
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

    // Re-read while shown, since volumes change from outside. Paused mid-drag, or a
    // stale poll snaps the slider back.
    Timer {
        id: audioStreamsPollTimer
        interval: 1500
        repeat: true
        running: root.audioStreamWatchers > 0
        onTriggered: if (!root.audioStreamsDragging) root.refreshAudioStreams()
    }

    // Audio changes as they happen: `pactl subscribe` prints a line per sink, source or stream
    // change, and a burst (a slider drag, an app starting) is read once.
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

    // A slow poll in case an event is lost.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        // Volume only; the CPU, memory, disk and temperature gauges once polled here are gone.
        onTriggered: volumeGetProc.running = true
    }
}
