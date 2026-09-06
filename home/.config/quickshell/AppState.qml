pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root


    property string username: ""
    property string wifiSsid: ""
    property string wifiIp: ""
    property bool wifiRadioEnabled: true
    property bool btEnabled: false
    property int btConnectedCount: 0
    property real volumePercent: 50
    property var wallpaperFiles: []
    property string selectedWallpaper: ""
    // Kept as aliases onto Theme so existing bindings recolor with the
    // wallpaper; new code should read Theme directly.
    readonly property string themeAccent: Theme.accent
    readonly property string themeBgHex: Theme.background.toString().substring(1)
    property var wifiNetworks: []
    property string wifiExpandedSsid: ""
    property string wifiStatusMessage: ""
    property bool wifiConnecting: false
    property string currentTime: Qt.formatDateTime(new Date(), "hh:mm")
    // Pinned to en_US rather than left to the system locale, so the bar reads
    // the same whatever LANG happens to be set to.
    property string currentDate: new Date().toLocaleDateString(Qt.locale("en_US"), "d MMMM")
    // Backed by the in-process notification server rather than dunst.
    readonly property bool dndEnabled: Notifications.dnd
    property var audioSinks: []
    property var audioStreams: []
    property bool audioStreamsDragging: false
    property real cpuPercent: 0
    property real ramPercent: 0
    property real diskPercent: 0
    property real tempCelsius: 0
    property bool micMuted: false
    property bool batteryPresent: false
    property real batteryPercent: 0

    property string hostname: ""
    property string distro: ""
    property real uptimeSeconds: 0

    readonly property string uptimeText: {
        var total = Math.floor(root.uptimeSeconds)
        if (total <= 0) return ""
        var days = Math.floor(total / 86400)
        var hours = Math.floor((total % 86400) / 3600)
        var minutes = Math.floor((total % 3600) / 60)
        if (days > 0) return days + "d " + hours + "h"
        if (hours > 0) return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    function toggleMicMute() {
        micToggleProc.command = ["bash", "-lc", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"]
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
        cueProc.command = ["bash", "-lc",
            "exec setsid pw-play --volume=0.5 \"/usr/share/sounds/freedesktop/stereo/$1.oga\" >/dev/null 2>&1 &",
            "_", name]
        cueProc.running = true
    }

    Process {
        id: cueProc
        running: false
    }

    function toggleWifiRadio() {
        wifiToggleProc.command = ["bash", "-lc", "nmcli radio wifi " + (root.wifiRadioEnabled ? "off" : "on")]
        wifiToggleProc.running = true
        root.wifiRadioEnabled = !root.wifiRadioEnabled
        wifiRadioRefreshTimer.restart()
    }

    function toggleBluetoothPower() {
        btToggleProc.command = ["bash", "-lc", "bluetoothctl power " + (root.btEnabled ? "off" : "on")]
        btToggleProc.running = true
        root.btEnabled = !root.btEnabled
        btRefreshTimer.restart()
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

    function refreshWallpaperList() {
        wallpaperListProc.running = true
    }

    // Applying a wallpaper goes through the cropper, always.
    //
    // hyprpaper can only cover, contain or tile, and all three pick the
    // framing themselves. So the shell hands it an image already cut to the
    // screen's shape at the point the user chose, and what hyprpaper is left
    // to do is put a picture of exactly the right size on the screen.
    //
    // selectedWallpaper stays the user's own file, not the crop: it is what
    // the picker matches its "in use" ring against, and the crop is an
    // implementation detail living in a cache directory.
    readonly property string wallpaperCropScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py"

    function setWallpaper(path) {
        root.selectedWallpaper = path
        // No focus given: keep whatever framing this wallpaper already has.
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path]
        wallpaperCropProc.running = true
    }

    function setWallpaperFraming(path, focusX, focusY) {
        root.selectedWallpaper = path
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path,
                                     String(focusX), String(focusY)]
        wallpaperCropProc.running = true
    }

    // Geometry of the wallpaper being framed, so the editor knows how much
    // room the crop has to move and which way. Empty until a probe lands.
    property var wallpaperCropInfo: null

    function probeWallpaperCrop(path) {
        root.wallpaperCropInfo = null
        wallpaperProbeProc.command = ["python3", root.wallpaperCropScript, "get", path]
        wallpaperProbeProc.running = true
    }

    function scanWifiNetworks() {
        wifiScanProc.running = true
    }

    function parseWifiScan(text) {
        var lines = text.trim().length > 0 ? text.trim().split("\n") : []
        var byS = {}
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split(":")
            if (parts.length < 4) continue
            var ssid = parts[1]
            if (ssid.length === 0) continue
            var signal = parseInt(parts[2]) || 0
            var entry = {
                ssid: ssid,
                inUse: parts[0] === "*",
                signal: signal,
                secure: parts[3] !== "--" && parts[3].length > 0
            }
            // A multi-band AP shows up once per band. Keep the strongest, but
            // carry the in-use flag across: if the connected band is the
            // weaker one, dropping it left the network looking disconnected.
            var existing = byS[ssid]
            if (!existing) {
                byS[ssid] = entry
            } else if (signal > existing.signal) {
                entry.inUse = entry.inUse || existing.inUse
                byS[ssid] = entry
            } else if (entry.inUse) {
                existing.inUse = true
            }
        }
        var list = Object.values(byS)
        list.sort(function(a, b) {
            if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
            return b.signal - a.signal
        })
        root.wifiNetworks = list
    }

    function toggleWifiExpand(ssid) {
        root.wifiExpandedSsid = (root.wifiExpandedSsid === ssid) ? "" : ssid
        root.wifiStatusMessage = ""
    }

    function connectToWifi(ssid, password, secure) {
        root.wifiConnecting = true
        root.wifiStatusMessage = "Connecting to " + ssid + "..."
        if (secure) {
            wifiConnectProc.command = ["bash", "-lc", "nmcli device wifi connect \"$1\" password \"$2\" 2>&1", "_", ssid, password]
        } else {
            wifiConnectProc.command = ["bash", "-lc", "nmcli device wifi connect \"$1\" 2>&1", "_", ssid]
        }
        wifiConnectProc.running = true
    }

    function toggleDnd() {
        Notifications.dnd = !Notifications.dnd
    }

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
        setSinkProc.command = ["bash", "-lc", "wpctl set-default " + id]
        setSinkProc.running = true
        audioSinksRefreshTimer.restart()
    }

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

    // The stream list is polled only while something is showing it, and more
    // than one panel now does -- the audio panel and the media widget, once
    // per monitor. A count rather than a flag, so the last one to close is
    // the one that stops the polling.
    property int audioStreamWatchers: 0

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

    property var bluetoothDevices: []
    property string btStatusMessage: ""
    property bool btActionInProgress: false

    function scanBluetoothDevices() {
        btScanProc.running = true
    }

    function parseBtScan(text) {
        var lines = text.trim().length > 0 ? text.trim().split("\n") : []
        var list = []
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|")
            if (parts.length < 4) continue
            list.push({
                mac: parts[0],
                paired: parts[1] === "yes",
                connected: parts[2] === "yes",
                name: parts[3].length > 0 ? parts[3] : parts[0]
            })
        }
        list.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        root.bluetoothDevices = list
    }

    function connectBluetoothDevice(mac, name, paired) {
        root.btActionInProgress = true
        root.btStatusMessage = "Connecting to " + name + "..."
        if (paired) {
            btActionProc.command = ["bash", "-lc", "bluetoothctl connect \"$1\" 2>&1", "_", mac]
        } else {
            btActionProc.command = ["bash", "-lc", "bluetoothctl pair \"$1\" 2>&1; bluetoothctl trust \"$1\" 2>&1; bluetoothctl connect \"$1\" 2>&1", "_", mac]
        }
        btActionProc.running = true
    }

    function disconnectBluetoothDevice(mac, name) {
        root.btActionInProgress = true
        root.btStatusMessage = "Disconnecting " + name + "..."
        btActionProc.command = ["bash", "-lc", "bluetoothctl disconnect \"$1\" 2>&1", "_", mac]
        btActionProc.running = true
    }

    Process {
        id: whoamiProc
        command: ["whoami"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.username = text.trim()
        }
    }

    Process {
        id: sysInfoProc
        running: true
        command: ["bash", "-lc", "printf '%s|%s' \"$(uname -n)\" \"$(. /etc/os-release 2>/dev/null && printf '%s' \"$PRETTY_NAME\")\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.split("|")
                root.hostname = parts[0] ? parts[0].trim() : ""
                root.distro = parts.length > 1 ? parts[1].trim() : ""
            }
        }
    }

    Process {
        id: uptimeProc
        running: false
        command: ["bash", "-lc", "cut -d' ' -f1 /proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseFloat(text.trim())
                if (!isNaN(v)) root.uptimeSeconds = v
            }
        }
    }

    Process {
        id: wifiProc
        running: false
        command: ["bash", "-lc", "LC_ALL=C nmcli -t -f active,ssid dev wifi | awk -F: '$1==\"yes\"{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiSsid = text.trim()
        }
    }

    Process {
        id: wifiIpProc
        running: false
        command: ["bash", "-lc", "export LC_ALL=C; dev=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"wifi\" && $3==\"connected\"{print $1; exit}'); nmcli -t -f IP4.ADDRESS device show \"$dev\" | cut -d: -f2 | cut -d/ -f1"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiIp = text.trim()
        }
    }

    Process {
        id: btPoweredProc
        running: false
        command: ["bash", "-lc", "LC_ALL=C bluetoothctl show | awk '/Powered/{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: root.btEnabled = text.trim() === "yes"
        }
    }

    Process {
        id: btConnectedProc
        running: false
        command: ["bash", "-lc", "LC_ALL=C bluetoothctl devices Connected | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: root.btConnectedCount = parseInt(text.trim()) || 0
        }
    }

    Process {
        id: wifiRadioProc
        running: false
        command: ["bash", "-lc", "LC_ALL=C nmcli radio wifi"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiRadioEnabled = text.trim() === "enabled"
        }
    }

    Process {
        id: wifiToggleProc
        running: false
    }

    Process {
        id: btToggleProc
        running: false
    }

    Process {
        id: wifiScanProc
        running: false
        command: ["bash", "-lc", "nmcli dev wifi rescan >/dev/null 2>&1; sleep 1; LC_ALL=C nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list"]
        stdout: StdioCollector {
            onStreamFinished: root.parseWifiScan(text)
        }
    }

    Process {
        id: wifiConnectProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var out = text.trim()
                if (out.toLowerCase().indexOf("error") !== -1) {
                    root.wifiStatusMessage = "Could not connect (check the password)"
                } else {
                    root.wifiStatusMessage = "Connected"
                    root.wifiExpandedSsid = ""
                    wifiProc.running = true
                    wifiIpProc.running = true
                    wifiScanProc.running = true
                }
                root.wifiConnecting = false
            }
        }
    }

    Process {
        id: btScanProc
        running: false
        command: ["bash", "-lc", "bash \"$HOME/.config/quickshell/scripts/bt_scan.sh\""]
        stdout: StdioCollector {
            onStreamFinished: root.parseBtScan(text)
        }
    }

    Process {
        id: btActionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var out = text.trim().toLowerCase()
                if (out.indexOf("fail") !== -1 || out.indexOf("error") !== -1) {
                    root.btStatusMessage = "Could not complete the action"
                } else {
                    root.btStatusMessage = "Done"
                }
                root.btActionInProgress = false
                btPoweredProc.running = true
                btConnectedProc.running = true
                btScanProc.running = true
            }
        }
    }

    Timer {
        id: wifiRadioRefreshTimer
        interval: 600
        onTriggered: wifiRadioProc.running = true
    }

    Timer {
        id: btRefreshTimer
        interval: 600
        onTriggered: btPoweredProc.running = true
    }

    Process {
        id: volumeGetProc
        running: false
        command: ["bash", "-lc", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2*100)}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(text.trim())
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

    // Which wallpaper is actually up. selectedWallpaper was only ever set by
    // setWallpaper, so across a shell restart nothing was marked as current
    // and the picker had no item to open on. hyprpaper's own config is the
    // answer: setWallpaper writes it, and it is what survives the restart.
    Process {
        id: currentWallpaperProc
        running: true
        // Asked of the cropper, not of hyprpaper: hyprpaper.conf now names a
        // rendered crop in the cache, and the picker needs the file in the
        // user's own folder that it was cut from.
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py", "current"]
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim()
                if (path.length > 0) root.selectedWallpaper = path
            }
        }
    }

    Process {
        id: wallpaperListProc
        // Read at startup, not only when something asks. The picker centres
        // itself on the wallpaper in use, and it cannot find it in a list
        // that is still empty -- it opened on the first file in the folder
        // and the model arriving a moment later kept it there.
        running: true
        command: ["bash", "-lc", "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                var trimmed = text.trim()
                var files = trimmed.length > 0 ? trimmed.split("\n") : []
                // Assigning an equal list is not a no-op: it is a new array,
                // so every view bound to it rebuilds. The picker refreshes on
                // the way open and would have thrown away which item was
                // centred to land back on the first file in the folder.
                if (files.length === root.wallpaperFiles.length
                        && files.join("\n") === root.wallpaperFiles.join("\n"))
                    return
                root.wallpaperFiles = files
            }
        }
    }

    Process {
        id: wallpaperSetProc
        running: false
    }

    Process {
        id: wallpaperProbeProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpaperCropInfo = JSON.parse(text)
                } catch (e) {
                    root.wallpaperCropInfo = null
                }
            }
        }
    }

    // Renders the crop, then points hyprpaper at what came out. Two steps
    // rather than one shell line because the second needs the first's answer.
    Process {
        id: wallpaperCropProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var rendered = ""
                try {
                    rendered = JSON.parse(text).rendered || ""
                } catch (e) {
                    rendered = ""
                }
                if (rendered.length === 0) return
                wallpaperSetProc.command = ["bash", "-lc", "P=\"$1\"; hyprctl hyprpaper preload \"$P\" >/dev/null 2>&1; hyprctl hyprpaper wallpaper \",$P,cover\"; printf 'splash = false\\nwallpaper {\\n    monitor =\\n    path = %s\\n    fit_mode = cover\\n}\\n' \"$P\" > \"$HOME/.config/hypr/hyprpaper.conf\"", "_", rendered]
                wallpaperSetProc.running = true
            }
        }
    }

    Process {
        id: micMutedProc
        running: false
        command: ["bash", "-lc", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo true || echo false"]
        stdout: StdioCollector {
            onStreamFinished: root.micMuted = text.trim() === "true"
        }
    }

    Process {
        id: micToggleProc
        running: false
    }

    Process {
        id: batteryProc
        running: false
        command: ["bash", "-lc", "bat=$(ls /sys/class/power_supply/ | grep -m1 '^BAT'); if [ -n \"$bat\" ]; then cat \"/sys/class/power_supply/$bat/capacity\"; else echo none; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim()
                if (t === "none" || t === "") {
                    root.batteryPresent = false
                } else {
                    var v = parseInt(t)
                    if (!isNaN(v)) {
                        root.batteryPresent = true
                        root.batteryPercent = v
                    }
                }
            }
        }
    }

    Process {
        id: audioSinksProc
        running: false
        command: ["bash", "-lc", "bash \"$HOME/.config/quickshell/scripts/audio_sinks.sh\""]
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
        id: cpuProc
        running: false
        command: ["bash", "-lc", "read cpu a b c idle rest < /proc/stat; t1=$((a+b+c+idle)); i1=$idle; sleep 0.4; read cpu a b c idle rest < /proc/stat; t2=$((a+b+c+idle)); i2=$idle; dt=$((t2-t1)); di=$((i2-i1)); if [ \"$dt\" -gt 0 ]; then echo $(( (100*(dt-di))/dt )); else echo 0; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(text.trim())
                if (!isNaN(v)) root.cpuPercent = v
            }
        }
    }

    Process {
        id: ramProc
        running: false
        command: ["bash", "-lc", "free | awk '/Mem:/{printf \"%d\", ($3/$2)*100}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(text.trim())
                if (!isNaN(v)) root.ramPercent = v
            }
        }
    }

    Process {
        id: diskProc
        running: false
        command: ["bash", "-lc", "df --output=pcent / | tail -1 | tr -d '% '"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(text.trim())
                if (!isNaN(v)) root.diskPercent = v
            }
        }
    }

    Process {
        id: tempProc
        running: false
        command: ["bash", "-lc", "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf \"%d\", $1/1000}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(text.trim())
                if (!isNaN(v)) root.tempCelsius = v
            }
        }
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

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            wifiProc.running = true
            wifiIpProc.running = true
            wifiRadioProc.running = true
            btPoweredProc.running = true
            btConnectedProc.running = true
            micMutedProc.running = true
            batteryProc.running = true
            uptimeProc.running = true
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            volumeGetProc.running = true
            cpuProc.running = true
            ramProc.running = true
            diskProc.running = true
            tempProc.running = true
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.currentTime = Qt.formatDateTime(new Date(), "hh:mm")
            root.currentDate = new Date().toLocaleDateString(Qt.locale("en_US"), "d MMMM")
        }
    }

    // ── Atajos de Hyprland ───────────────────────────────────────────────
    //
    // Read out of the config file rather than `hyprctl binds`: with a Lua
    // config every bind reports the dispatcher "__lua" and an opaque
    // callback index, so the compositor can list the keys but cannot say
    // what a single one of them does. scripts/hypr_binds.lua runs the config
    // against a stub `hl` table instead, which gets the loops, the locals and
    // any required file along with everything else.
    readonly property string hyprConfigPath: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"

    // [{ name, binds: [{ keys, action, command }] }]
    property var hyprBindGroups: []
    property int hyprBindCount: 0
    property string hyprBindsError: ""

    // Keys the config points at this shell's cheatsheet, read back out of
    // that config so the control panel's hint follows a rebind instead of
    // repeating a combination written in the QML.
    property string hyprOverlayKeys: ""

    // The cheatsheet overlay. Lives here because two unrelated things open
    // it: the control panel's button and the Hyprland global shortcut.
    property bool keybindsOpen: false

    // Monitor the cheatsheet was summoned on, latched on the way open.
    //
    // The overlay used to just render on whichever monitor was focused, but
    // focus follows the mouse here (input:follow_mouse = 1), so moving the
    // pointer to the other screen carried the sheet along with it -- off the
    // work it was opened to explain. Pinned instead until it closes.
    property string keybindsScreen: ""

    onKeybindsOpenChanged: {
        if (!root.keybindsOpen) return
        var monitor = Hyprland.focusedMonitor
        root.keybindsScreen = monitor ? monitor.name : ""
        // The file watches normally have this covered; re-reading on the way
        // in is the cheap guarantee that what gets shown is what is on disk.
        root.refreshHyprBinds()
        root.refreshYaziBinds()
    }

    function toggleKeybinds() {
        root.keybindsOpen = !root.keybindsOpen
    }

    // The wallpaper picker. Same two reasons as the cheatsheet for living
    // here: the control panel opens it, so does a global shortcut, and it
    // has to stay on the screen it was summoned on rather than follow the
    // pointer to the other monitor.
    property bool wallpapersOpen: false
    property string wallpapersScreen: ""

    onWallpapersOpenChanged: {
        if (!root.wallpapersOpen) return
        var monitor = Hyprland.focusedMonitor
        root.wallpapersScreen = monitor ? monitor.name : ""
        // Cheap, and it means a file dropped into the folder while the shell
        // was running is there the first time the picker is opened.
        root.refreshWallpaperList()
    }

    function toggleWallpapers() {
        root.wallpapersOpen = !root.wallpapersOpen
    }

    // ── Lock transition ──────────────────────────────────────────────────
    //
    // Phases, in order: "" idle, "closing" while the screen fades to black
    // with the lock request in flight, "locked" while veila holds the screen,
    // "opening" while the fade comes back off. LockOverlay draws all of it.
    //
    // Everything that locks comes through here rather than running `veila
    // lock` for itself -- the Hyprland bind, the control panel's button, its
    // suspend -- because the fade has to be finished before veila is asked,
    // and a caller that shells out directly gets the hard cut back.
    property string lockPhase: ""

    // Set when the lock is on the way to a suspend, so the machine only goes
    // down once the screen is actually covered. The old bind slept 0.3s and
    // hoped; this waits for veila to say it is up.
    property bool suspendAfterLock: false

    function lockSession() {
        if (root.lockPhase !== "") return
        root.lockPhase = "closing"
        lockRequestDelay.restart()
        lockWatchdog.restart()
    }

    function suspendSession() {
        // Already covered: nothing left to fade, so go straight down.
        if (root.lockPhase === "locked") {
            suspendProc.running = true
            return
        }
        // Mid-transition in either direction: dropped rather than queued
        // behind it. lockSession() would no-op and leave the flag set, and a
        // flag left set suspends the machine the next time anything locks.
        if (root.lockPhase !== "") return
        root.suspendAfterLock = true
        root.lockSession()
    }

    // Every way out of the transition, including the ones that are not an
    // orderly unlock. A lock that never came up must not leave the screen
    // black, so this is reachable from more than one direction on purpose and
    // is safe to call twice.
    function endLockTransition() {
        if (root.lockPhase === "" || root.lockPhase === "opening") return
        lockWatchdog.stop()
        root.suspendAfterLock = false
        root.lockPhase = "opening"
        lockSettle.restart()
    }

    // veila is asked only once the curtain is opaque. Asking first lands its
    // surface over a half-faded screen, which is the cut being removed.
    Timer {
        id: lockRequestDelay
        interval: Theme.durLong
        onTriggered: lockProc.running = true
    }

    // The fade out has no natural end -- the script exited before it started
    // -- so idle is restored on a timer matched to it, slightly long so input
    // comes back after the last frame rather than during it.
    Timer {
        id: lockSettle
        interval: Theme.durExtraLong + 60
        onTriggered: root.lockPhase = ""
    }

    // `veila lock --wait-ready` blocks until the lock is up, and a daemon
    // that never gets there would otherwise hold a black screen with no lock
    // behind it.
    Timer {
        id: lockWatchdog
        interval: 8000
        onTriggered: root.endLockTransition()
    }

    Process {
        id: lockProc
        running: false
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/lock_session.sh"]

        stdout: SplitParser {
            onRead: function(line) {
                if (line === "locked") {
                    lockWatchdog.stop()
                    root.lockPhase = "locked"
                    if (root.suspendAfterLock) {
                        root.suspendAfterLock = false
                        suspendProc.running = true
                    }
                } else if (line === "unlocked" || line === "failed") {
                    root.endLockTransition()
                }
            }
        }

        // The script exits with the cycle, so this catches a cycle that ended
        // without saying so: killed, or never started at all.
        onExited: root.endLockTransition()
    }

    Process {
        id: suspendProc
        running: false
        command: ["bash", "-lc", "systemctl suspend"]
    }

    function refreshHyprBinds() {
        if (!hyprBindsProc.running) hyprBindsProc.running = true
    }

    Process {
        id: hyprBindsProc
        running: true
        command: ["lua", Quickshell.env("HOME") + "/.config/quickshell/scripts/hypr_binds.lua",
                  root.hyprConfigPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text)
                    root.hyprBindGroups = parsed.groups || []
                    root.hyprBindCount = parsed.count || 0
                    root.hyprOverlayKeys = parsed.overlayKeys || ""
                    root.hyprBindsError = parsed.error || ""
                } catch (e) {
                    root.hyprBindGroups = []
                    root.hyprBindCount = 0
                    root.hyprOverlayKeys = ""
                    root.hyprBindsError = "Could not read " + root.hyprConfigPath
                }
            }
        }
    }

    // An editor usually writes a config as a rename over the old inode, which
    // can land as several events; the debounce collapses those into one read.
    Timer {
        id: hyprBindsDebounce
        interval: 400
        onTriggered: root.refreshHyprBinds()
    }

    FileView {
        path: root.hyprConfigPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: hyprBindsDebounce.restart()
    }

    // ── Atajos de yazi ───────────────────────────────────────────────────
    //
    // Its own reader and its own section in the sheet: yazi's keymap is TOML
    // and most of what its keyboard does is compiled into the binary rather
    // than written in any file, so nothing about it is shaped like the
    // Hyprland side. See scripts/yazi_binds.py.
    property var yaziBindGroups: []
    property int yaziBindCount: 0
    property string yaziBindsError: ""

    readonly property string yaziKeymapPath:
        Quickshell.env("HOME") + "/.config/yazi/keymap.toml"

    function refreshYaziBinds() {
        if (!yaziBindsProc.running) yaziBindsProc.running = true
    }

    Process {
        id: yaziBindsProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/yazi_binds.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text)
                    root.yaziBindGroups = parsed.groups || []
                    root.yaziBindCount = parsed.count || 0
                    root.yaziBindsError = parsed.error || ""
                } catch (e) {
                    root.yaziBindGroups = []
                    root.yaziBindCount = 0
                    root.yaziBindsError = "Could not read yazi's keymap"
                }
            }
        }
    }

    FileView {
        path: root.yaziKeymapPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: yaziBindsDebounce.restart()
    }

    Timer {
        id: yaziBindsDebounce
        interval: 400
        onTriggered: root.refreshYaziBinds()
    }

    // Second path to the same refresh: a rename-over can cost the watch above
    // its inode, and this fires whenever Hyprland itself picks the file up.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "configreloaded") return
            hyprBindsDebounce.restart()
            // The gaps can have moved with it, and the bar is meant to line up
            // with the windows whatever they are now.
            root.refreshGaps()
        }
    }

    // ── Window gaps ──────────────────────────────────────────────────────
    //
    // Asked of Hyprland rather than repeated here. The bar sits at the same
    // inset as the windows underneath it, and an inset written down in two
    // configs is one that will eventually disagree with itself -- silently,
    // as a few pixels of misalignment nobody can place.
    //
    // The defaults are Hyprland's own, so the bar is only ever wrong for the
    // moment before the first answer arrives.
    property int gapTop: 20
    property int gapRight: 30
    property int gapBottom: 30
    property int gapLeft: 30

    function refreshGaps() {
        if (!gapsProc.running) gapsProc.running = true
    }

    // hyprctl reports gaps_out as a CSS shorthand string, so it expands the
    // way CSS margins do: one value for all sides, two for vertical and
    // horizontal, three for top / sides / bottom, four for each in turn.
    function parseGaps(text) {
        var css = ""
        try {
            css = (JSON.parse(text).css || "").trim()
        } catch (e) {
            return
        }
        if (css.length === 0) return

        var parts = css.split(/\s+/)
        var n = []
        for (var i = 0; i < parts.length; i++) {
            var v = parseInt(parts[i])
            if (isNaN(v)) return
            n.push(v)
        }

        if (n.length === 1) n = [n[0], n[0], n[0], n[0]]
        else if (n.length === 2) n = [n[0], n[1], n[0], n[1]]
        else if (n.length === 3) n = [n[0], n[1], n[2], n[1]]
        else if (n.length !== 4) return

        root.gapTop = n[0]
        root.gapRight = n[1]
        root.gapBottom = n[2]
        root.gapLeft = n[3]
    }

    Process {
        id: gapsProc
        running: true
        command: ["hyprctl", "getoption", "general:gaps_out", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.parseGaps(text)
        }
    }

    // ── Captura rápida en Obsidian ───────────────────────────────────────
    //
    // Straight at the vault's Markdown, not at Obsidian. Its only API is a
    // community plugin that answers while the app is running, which is the
    // wrong half of the time for a box you hit on the way past -- and the
    // vault is plain files anyway. See scripts/obsidian_capture.py.
    property var obsidianEntries: []
    property int obsidianTotal: 0
    property string obsidianVaultName: ""
    property string obsidianNote: ""
    property string obsidianPath: ""
    property string obsidianError: ""

    readonly property string obsidianScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/obsidian_capture.py"

    // Both the read and the write print the note's new state, so they land
    // here and the list never has to be re-fetched after an entry is added.
    function applyObsidianState(text) {
        try {
            var parsed = JSON.parse(text)
            if (parsed.error) {
                root.obsidianError = parsed.error
                root.obsidianEntries = []
                root.obsidianTotal = 0
                return
            }
            root.obsidianError = ""
            root.obsidianEntries = parsed.entries || []
            root.obsidianTotal = parsed.total || 0
            root.obsidianVaultName = parsed.vaultName || ""
            root.obsidianNote = parsed.note || ""
            root.obsidianPath = parsed.path || ""
        } catch (e) {
            root.obsidianError = "Could not read the note"
            root.obsidianEntries = []
            root.obsidianTotal = 0
        }
    }

    function refreshObsidianNotes() {
        if (!obsidianReadProc.running) obsidianReadProc.running = true
    }

    // Notes typed while a save is still in flight wait their turn rather
    // than being dropped: typing faster than the disk is not a reason to
    // lose what someone wrote.
    property var obsidianQueue: []

    function addObsidianNote(text) {
        var trimmed = text.trim()
        if (trimmed.length === 0) return

        if (obsidianAddProc.running) {
            var queued = root.obsidianQueue.slice()
            queued.push(trimmed)
            root.obsidianQueue = queued
            return
        }

        // Argument vector, never a shell line: whatever gets typed in the
        // box is a note, not something to be parsed for quotes.
        obsidianAddProc.command = ["python3", root.obsidianScript, "--add", trimmed]
        obsidianAddProc.running = true
    }

    function drainObsidianQueue() {
        if (root.obsidianQueue.length === 0 || obsidianAddProc.running) return
        var queued = root.obsidianQueue.slice()
        var next = queued.shift()
        root.obsidianQueue = queued
        obsidianAddProc.command = ["python3", root.obsidianScript, "--add", next]
        obsidianAddProc.running = true
    }

    function openObsidianNote() {
        if (root.obsidianVaultName.length === 0) return
        var file = root.obsidianNote.replace(/\.md$/, "")
        obsidianOpenProc.command = ["xdg-open",
            "obsidian://open?vault=" + encodeURIComponent(root.obsidianVaultName)
            + "&file=" + encodeURIComponent(file)]
        obsidianOpenProc.running = true
    }

    Process {
        id: obsidianReadProc
        running: true
        command: ["python3", root.obsidianScript]
        stdout: StdioCollector {
            onStreamFinished: root.applyObsidianState(text)
        }
    }

    Process {
        id: obsidianAddProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyObsidianState(text)
        }
        onRunningChanged: if (!running) root.drainObsidianQueue()
    }

    Process {
        id: obsidianOpenProc
        running: false
    }

    // Obsidian and LiveSync write this note too, so the widget follows the
    // file rather than trusting its own last write to still be the latest.
    // The path comes from the script, which resolves the vault out of
    // Obsidian's registry -- so a vault moved from inside the app is picked
    // up here without the shell knowing where it went.
    FileView {
        path: root.obsidianPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: obsidianDebounce.restart()
    }

    Timer {
        id: obsidianDebounce
        interval: 400
        onTriggered: root.refreshObsidianNotes()
    }

}
