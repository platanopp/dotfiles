pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root


    // From the environment at once; whoami below only confirms it. It used to
    // start empty, and the clock's panel showed a hard-coded name meanwhile.
    property string username: Quickshell.env("USER") || ""
    property string wifiSsid: ""
    property string wifiIp: ""
    property bool wifiRadioEnabled: true
    property bool btEnabled: false
    property int btConnectedCount: 0
    property real volumePercent: 50
    property bool volumeMuted: false
    // The connected network's signal (0-100), for the bar's icon; -1 when
    // not on Wi-Fi. ethernetUp: a wired connection, which the bar shows
    // instead of a crossed-out Wi-Fi icon.
    property int wifiSignal: -1
    property bool ethernetUp: false
    property var wallpaperFiles: []
    property string selectedWallpaper: ""
    // The crop hyprpaper is showing for selectedWallpaper -- the picture at
    // the framing the user chose, cut to the screen's shape. Empty until the
    // first answer arrives. See wallpaperStill.
    property string renderedWallpaper: ""
    // Kept as aliases onto Theme so existing bindings recolor with the
    // wallpaper; new code should read Theme directly.
    readonly property string themeAccent: Theme.accent
    readonly property string themeBgHex: Theme.background.toString().substring(1)
    property var wifiNetworks: []
    property string wifiExpandedSsid: ""
    property string wifiStatusMessage: ""
    property bool wifiConnecting: false
    property string currentTime: root.formatTime(new Date())

    // 24-hour or 12-hour, from Settings -> Shell.
    function formatTime(d) {
        return Qt.formatDateTime(d, ShellSettings.clock24h ? "hh:mm" : "h:mm AP")
    }

    Connections {
        target: ShellSettings
        function onClock24hChanged() { root.currentTime = root.formatTime(new Date()) }
    }
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

    function toggleVolumeMute() {
        volumeSetProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        volumeSetProc.running = true
        root.volumeMuted = !root.volumeMuted
    }

    // "PipeWire ALSA [osu!]" is how a Wine game's stream is named; the part
    // in brackets is the name worth showing.
    function streamName(n) {
        var m = /\[(.+)\]\s*$/.exec(n || "")
        return m ? m[1] : (n || "Unknown")
    }

    // Asks the control panel on that screen to open Settings at a page --
    // for the bar's own panels, which link to their fuller page.
    signal settingsRequested(string page, string screenName)
    function openSettings(page, screenName) { root.settingsRequested(page, screenName) }

    // qs ipc call settings open sound -- on the focused monitor.
    IpcHandler {
        target: "settings"
        function open(page: string): void {
            var m = Hyprland.focusedMonitor
            root.openSettings(page.length > 0 ? page : "displays", m ? m.name : "")
        }
    }

    function forgetBluetoothDevice(mac, name) {
        root.btActionInProgress = true
        root.btStatusMessage = "Forgetting " + name + "..."
        btActionProc.command = ["bash", "-lc", "bluetoothctl remove \"$1\" 2>&1", "_", mac]
        btActionProc.running = true
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
        root.stopVideoWallpaper()
        root.selectedWallpaper = path
        // The old crop belongs to the old picture; until the new one is
        // rendered, the original is the closer answer.
        root.renderedWallpaper = ""
        // No focus given: keep whatever framing this wallpaper already has.
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path]
        wallpaperCropProc.running = true
    }

    function setWallpaperFraming(path, focusX, focusY) {
        root.stopVideoWallpaper()
        root.selectedWallpaper = path
        // The old crop belongs to the old picture; until the new one is
        // rendered, the original is the closer answer.
        root.renderedWallpaper = ""
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
        if (!wifiScanProc.running) wifiScanProc.running = true
    }

    readonly property bool wifiScanning: wifiScanProc.running
    readonly property bool btScanning: btScanProc.running

    function disconnectWifi(ssid) {
        root.wifiConnecting = true
        root.wifiStatusMessage = "Disconnecting..."
        wifiConnectProc.command = ["bash", "-lc", "nmcli connection down id \"$1\" 2>&1 && echo DISCONNECTED", "_", ssid]
        wifiConnectProc.running = true
    }

    function parseWifiScan(text) {
        // The scan, then "--saved--" and the names of saved Wi-Fi
        // connections: a saved network connects without asking again.
        var halves = text.split("--saved--")
        var savedNames = (halves[1] || "").split("\n").map(l => l.trim()).filter(l => l.length > 0)
        var lines = halves[0].trim().length > 0 ? halves[0].trim().split("\n") : []
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
                secure: parts[3] !== "--" && parts[3].length > 0,
                saved: savedNames.indexOf(ssid) !== -1
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

    function connectToWifi(ssid, password, secure, saved) {
        root.wifiConnecting = true
        root.wifiStatusMessage = "Connecting to " + ssid + "..."
        if (saved) {
            wifiConnectProc.command = ["bash", "-lc", "nmcli connection up id \"$1\" 2>&1", "_", ssid]
        } else if (secure) {
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
                name: parts[3].length > 0 ? parts[3] : parts[0],
                icon: parts[4] || ""
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

    // The logged-in user's picture, from where Linux keeps one: ~/.face (what
    // display managers read), ~/.face.icon, or AccountsService's copy. Empty
    // when there is none, and the control panel shows the initial instead.
    property string avatarPath: ""
    // Bumped on every change: the file keeps its name, so an Image showing it
    // must be told to read it again (see avatarSource).
    property int avatarVersion: 0
    // For Images: cleared for one frame on a change, so a picture shown with
    // cache: false reloads rather than keeping the old one.
    readonly property string avatarSource: root.avatarPath.length > 0 && root.avatarVersion >= 0
        ? "file://" + root.avatarPath : ""
    property string avatarError: ""
    property bool avatarBusy: false

    function setAvatar(path) { root.avatarCmd(["set", path]) }
    function removeAvatar() { root.avatarCmd(["remove"]) }

    function avatarCmd(args) {
        if (avatarSetProc.running) return
        root.avatarBusy = true
        root.avatarError = ""
        avatarSetProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/avatar.py"].concat(args)
        avatarSetProc.running = true
    }

    Process {
        id: avatarSetProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.avatarBusy = false
                var d
                try { d = JSON.parse(text) } catch (e) { root.avatarError = "Could not change the picture"; return }
                if (!d.ok) { root.avatarError = d.error || "Could not change the picture"; return }
                root.avatarPath = ""
                root.avatarVersion++
                avatarProc.running = true
            }
        }
    }

    Process {
        id: avatarProc
        running: true
        command: ["sh", "-c", "for f in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [ -s \"$f\" ] && { printf '%s' \"$f\"; exit 0; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root.avatarPath = text.trim()
        }
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
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/net_status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = text.replace(/\n$/, "").split("\t")
                root.wifiSsid = (f[0] || "").trim()
                var sig = parseInt(f[1])
                root.wifiSignal = root.wifiSsid.length > 0 && !isNaN(sig) ? sig : -1
                root.ethernetUp = f[2] === "1"
            }
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
        command: ["bash", "-lc", "nmcli dev wifi rescan >/dev/null 2>&1; sleep 1; LC_ALL=C nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list; echo --saved--; LC_ALL=C nmcli -t -f NAME,TYPE connection show | awk -F: '$NF==\"802-11-wireless\"{print $1}'"]
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
                if (out.indexOf("DISCONNECTED") !== -1) {
                    root.wifiStatusMessage = ""
                    root.wifiExpandedSsid = ""
                    wifiProc.running = true
                    wifiScanProc.running = true
                } else if (out.toLowerCase().indexOf("error") !== -1) {
                    var low = out.toLowerCase()
                    root.wifiStatusMessage = low.indexOf("secrets were required") !== -1 || low.indexOf("password") !== -1
                        ? "Wrong password"
                        : low.indexOf("no network with ssid") !== -1 ? "That network is out of range"
                        : "Could not connect"
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

    // The crop in use, for the lock screen, read at startup the same way the
    // wallpaper itself is: nothing re-renders it just because the shell came
    // back up.
    Process {
        id: renderedWallpaperProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py", "rendered"]
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim()
                if (path.length > 0) root.renderedWallpaper = path
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
                root.buildWallpaperThumbs()
            }
        }
    }

    // ── Wallpaper thumbnails ─────────────────────────────────────────────
    //
    // The carousel keeps a dozen panels alive and each was decoding its own
    // full-size original; the 8K PNG in that folder costs ~380ms by itself,
    // and the whole folder is two seconds. Qt's sourceSize caps the output,
    // not the work, so the panels sat on their placeholder long enough to
    // read as a black gap.
    //
    // Cached JPEGs at carousel height decode 34x faster (2107ms -> 62ms for
    // the folder). Rebuilt whenever the file list changes; the script keys on
    // mtime and size, so it only does work for what actually changed.
    property var wallpaperThumbs: ({})

    function buildWallpaperThumbs() {
        wallpaperThumbsProc.running = true
    }

    // Falls back to the original: a file the script could not read still
    // shows, just slowly, rather than leaving a hole in the carousel.
    function wallpaperThumb(path) {
        return root.wallpaperThumbs[path] || path
    }

    Process {
        id: wallpaperThumbsProc
        running: false
        // nice + ionice: the pass costs a few seconds of CPU and a burst of
        // reads the first time it sees a folder, and it runs at shell startup
        // when everything else is also competing. Nothing waits on it -- the
        // carousel falls back to originals until the map arrives -- so it can
        // afford to go last.
        command: ["nice", "-n", "19", "ionice", "-c", "3", "python3",
                  Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_thumbs.py",
                  "build"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpaperThumbs = JSON.parse(text)
                } catch (e) {
                    root.wallpaperThumbs = ({})
                }
            }
        }
    }

    // ── Video wallpapers ─────────────────────────────────────────────────
    //
    // Played by mpvpaper, on the layer above hyprpaper's; the image wallpaper
    // stays set underneath and is what shows again when the video stops. See
    // scripts/video_wallpaper.py, which owns the process and remembers which
    // video is up across sessions.
    readonly property string videoWallpaperScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/video_wallpaper.py"

    // Paths, in the order the picker shows them.
    property var videoWallpaperFiles: []
    // path -> { thumb, poster }: a still at carousel height for the picker,
    // and one at full size for the lock screen.
    property var videoWallpaperFrames: ({})
    // The video playing as the wallpaper, or "" when it is an image.
    property string activeVideoWallpaper: ""

    function refreshVideoWallpapers() {
        if (!videoListProc.running) videoListProc.running = true
    }

    function videoWallpaperThumb(path) {
        var f = root.videoWallpaperFrames[path]
        return f && f.thumb ? f.thumb : ""
    }

    function setVideoWallpaper(path) {
        root.activeVideoWallpaper = path
        videoControlProc.command = ["python3", root.videoWallpaperScript, "apply", path]
        videoControlProc.running = true
    }

    function stopVideoWallpaper() {
        if (root.activeVideoWallpaper === "") return
        root.activeVideoWallpaper = ""
        videoControlProc.command = ["python3", root.videoWallpaperScript, "stop"]
        videoControlProc.running = true
    }

    // A still of whatever the wallpaper is, for things that draw it behind
    // themselves -- the lock screen, mostly. With a video up that is its
    // poster frame: a lock surface has no business playing a video behind a
    // password field, and the image underneath would be the wrong picture.
    //
    // For an image it is the rendered crop, not the user's own file. The
    // lock covers its screen, so handed the original it cropped it again at
    // the centre -- and a wallpaper framed off-centre in the picker showed a
    // different part of itself on the lock than on the desktop.
    // ── Keyboard colours from the wallpaper ─────────────────────────────
    //
    // A Wooting keyboard painted from whatever wallpaper is up (see
    // scripts/keyboard_rgb.py): letters in the dominant colour, the rest in
    // the picture's other tones. Follows wallpaperStill, so a video
    // wallpaper colours it from its poster frame.
    property var keyboardRgbStatus: ({ connected: false })
    // The colours in use: { dominant, others } as hex, for the Settings page.
    property var keyboardRgbPalette: null
    property string keyboardRgbError: ""

    readonly property string keyboardRgbScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/keyboard_rgb.py"

    function applyKeyboardRgb() {
        if (!ShellSettings.keyboardRgb || root.wallpaperStill.length === 0) return
        keyboardRgbDebounce.restart()
    }

    function resetKeyboardRgb() {
        keyboardRgbProc.command = ["python3", root.keyboardRgbScript, "reset"]
        keyboardRgbProc.running = true
        root.keyboardRgbPalette = null
    }

    function refreshKeyboardRgb() {
        if (!keyboardRgbStatusProc.running) keyboardRgbStatusProc.running = true
    }

    onWallpaperStillChanged: root.applyKeyboardRgb()

    // qs ipc call keyboard apply -- say, bound to a key, after switching
    // profiles on the keyboard (a profile switch covers these colours).
    IpcHandler {
        target: "keyboard"
        function apply(): void { root.applyKeyboardRgb() }
        function reset(): void { root.resetKeyboardRgb() }
    }

    Connections {
        target: ShellSettings
        function onKeyboardRgbChanged() {
            if (ShellSettings.keyboardRgb) root.applyKeyboardRgb()
            else root.resetKeyboardRgb()
        }
        function onKeyboardRgbBrightnessChanged() { root.applyKeyboardRgb() }
    }

    // A wallpaper change settles (the crop is rendered, the video's poster is
    // cut) before the keyboard follows; one write, not several.
    Timer {
        id: keyboardRgbDebounce
        interval: 600
        onTriggered: {
            if (keyboardRgbProc.running) { keyboardRgbDebounce.restart(); return }
            keyboardRgbProc.command = ["python3", root.keyboardRgbScript, "apply",
                                       root.wallpaperStill, String(ShellSettings.keyboardRgbBrightness)]
            keyboardRgbProc.running = true
        }
    }

    Process {
        id: keyboardRgbProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try { d = JSON.parse(text) } catch (e) { return }
                root.keyboardRgbError = d.ok ? "" : (d.error || "")
                if (d.ok && d.dominant) root.keyboardRgbPalette = { dominant: d.dominant, others: d.others, keys: d.keys || ({}) }
            }
        }
    }

    Process {
        id: keyboardRgbStatusProc
        running: true
        command: ["python3", root.keyboardRgbScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.keyboardRgbStatus = JSON.parse(text) } catch (e) {}
            }
        }
    }

    readonly property string wallpaperStill: {
        if (root.activeVideoWallpaper !== "") {
            var f = root.videoWallpaperFrames[root.activeVideoWallpaper]
            if (f && f.poster) return f.poster
        }
        return root.renderedWallpaper !== "" ? root.renderedWallpaper
                                             : root.selectedWallpaper
    }

    Process {
        id: videoListProc
        // At startup as well as on open, for the same reason as the image
        // list: the picker centres on what is in use, and it needs the list
        // and the current video to do that. It is also where the remembered
        // video comes back from, so the ring is right after a restart.
        running: true
        command: ["nice", "-n", "19", "python3",
                  Quickshell.env("HOME") + "/.config/quickshell/scripts/video_wallpaper.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var data
                try {
                    data = JSON.parse(text)
                } catch (e) {
                    return
                }
                var files = [], frames = {}
                for (var i = 0; i < data.videos.length; i++) {
                    var v = data.videos[i]
                    files.push(v.path)
                    frames[v.path] = { thumb: v.thumb, poster: v.poster }
                }
                root.videoWallpaperFrames = frames
                // Same reason as the image list: an equal list assigned again
                // is still a new array, and it would reset the carousel.
                if (files.join("\n") !== root.videoWallpaperFiles.join("\n"))
                    root.videoWallpaperFiles = files
                root.activeVideoWallpaper = data.current || ""
            }
        }
    }

    // Brings the remembered video back when a session starts. Safe to run on
    // every shell reload: the script leaves a video that is already playing
    // alone instead of restarting it from the top.
    Process {
        id: videoRestoreProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/video_wallpaper.py",
                  "restore"]
    }

    Process {
        id: videoControlProc
        running: false
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
                root.renderedWallpaper = rendered
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
            otdStateProc.running = true
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
            root.currentTime = root.formatTime(new Date())
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
        root.refreshVideoWallpapers()
    }

    function toggleWallpapers() {
        root.wallpapersOpen = !root.wallpapersOpen
    }

    // The application launcher. Same reason as the two above for living here
    // rather than in the component: it is opened from a global shortcut, and
    // it has to stay on the screen it was summoned on rather than follow the
    // pointer to the other monitor.
    property bool launcherOpen: false
    property string launcherScreen: ""

    onLauncherOpenChanged: {
        if (!root.launcherOpen) return
        var monitor = Hyprland.focusedMonitor
        root.launcherScreen = monitor ? monitor.name : ""
    }

    function toggleLauncher() {
        root.launcherOpen = !root.launcherOpen
    }

    // ── Modo mando ─────────────────────────────────────────────────
    //
    // gamepad-mode.service maps a controller onto the pointer and the desktop
    // -- left stick moves the cursor, the triggers click, the d-pad changes
    // workspace. It runs for the whole session, so the mapping is there at the
    // desk and not only inside a Sunshine stream.
    //
    // The daemon owns the mode. This side reads what it wrote and asks it to
    // flip; it never sets the mode itself, so the tile, L3 + R3 and the
    // notification are all describing one thing.
    //
    //   stopped   the service is not running, so there is nothing to flip
    //   waiting   running, with no controller plugged in
    //   off       controller present, acting as a plain gamepad
    //   on        controller present, driving the desktop
    property string gamepadMode: "stopped"

    readonly property bool gamepadModeActive: root.gamepadMode === "on"
    readonly property bool gamepadConnected:
        root.gamepadMode === "on" || root.gamepadMode === "off"

    readonly property string gamepadStatePath: {
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR")
        return (runtimeDir && runtimeDir.length > 0 ? runtimeDir : "/tmp")
             + "/gamepad-mode.state"
    }

    // A signal to the daemon rather than a write to the state file. With no
    // pad connected there is no mode to be in, and the daemon answers that
    // with a notification and stays where it was -- writing "on" from here
    // would claim a change that did not happen.
    function toggleGamepadMode() {
        gamepadToggleProc.running = true
    }

    // ── Driver de tablet ─────────────────────────────────────────────────
    //
    // opentabletdriver.service lee la tablet por HID crudo y publica un
    // dispositivo virtual propio. Mientras corre es el unico que maneja el
    // lapiz: una regla de udev marca el dispositivo del kernel con
    // LIBINPUT_IGNORE_DEVICE para que el compositor no reciba dos posiciones
    // a la vez.
    //
    // Apagarlo desde aca deja la tablet sin funcionar del todo, no la devuelve
    // a un modo basico. Por eso el detalle del tile lo dice en vez de un "Off"
    // que se leeria como algo reversible sin consecuencia.
    property bool otdRunning: false

    function toggleOtd() {
        otdToggleProc.command = ["bash", "-c", "systemctl --user "
            + (root.otdRunning ? "stop" : "start") + " opentabletdriver.service"]
        otdToggleProc.running = true
        // Optimista, como los demas toggles de este archivo: se confirma a los
        // 900ms en vez de dejar el tile quieto esperando a systemd.
        root.otdRunning = !root.otdRunning
        otdRefreshTimer.restart()
    }

    Process { id: otdToggleProc; running: false }

    Process {
        id: otdStateProc
        running: false
        // bash -c y no -lc: el resto del archivo usa shell de login por
        // costumbre, y eso sourcea /etc/profile entero para correr un
        // systemctl. No hay motivo para sumar otro.
        command: ["bash", "-c", "systemctl --user is-active opentabletdriver.service"]
        stdout: StdioCollector {
            onStreamFinished: root.otdRunning = text.trim() === "active"
        }
    }

    Timer {
        id: otdRefreshTimer
        interval: 900
        onTriggered: otdStateProc.running = true
    }

    Process {
        id: gamepadToggleProc
        running: false
        command: [Quickshell.env("HOME") + "/.config/quickshell/scripts/gamepad-mode.sh",
                  "toggle"]
    }



    // ── Display settings ─────────────────────────────────────────────────
    //
    // Everything the Settings window's Displays and Colour pages show comes
    // from one script, because the three things it drives speak three
    // different languages: hyprctl for modes and layout, nvibrant for
    // saturation, hyprsunset for the colour matrix. Each command returns the
    // whole snapshot, so the UI never has to ask twice.
    property var displayState: ({
        monitors: [], vibrance: ({}),
        colour: ({ temperature: 6000, brightness: 100, gamma: 1.0 }),
        colour_active: false, vrr: 0
    })

    readonly property string displayScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/display_control.py"

    // Queued, because there is one process and a command given while it is
    // still busy used to be dropped without a word: setting `running` on a
    // Process that is already running does nothing. Picking a resolution and
    // then a scale straight after lost the scale.
    property var displayQueue: []

    function displayCmd(args) {
        root.displayQueue = root.displayQueue.concat([args])
        root.displayNext()
    }

    function displayNext() {
        if (displayProc.running || root.displayQueue.length === 0) return
        var next = root.displayQueue[0]
        root.displayQueue = root.displayQueue.slice(1)
        displayProc.command = ["python3", root.displayScript].concat(next)
        displayProc.running = true
    }

    function refreshDisplay()                  { displayCmd(["list"]) }

    // Focus the monitor the pointer is on. Used before spawning anything from
    // the launcher: follow_mouse cannot do it while a layer surface holds the
    // keyboard, so the first window would land on the previously focused
    // screen. Fire-and-forget, on its own process so it never blocks the UI.
    function focusCursorMonitor() {
        focusCursorProc.command = ["python3", root.displayScript, "focus-cursor-monitor"]
        focusCursorProc.running = true
    }

    Process {
        id: focusCursorProc
        running: false
    }
    function setDisplayMode(out, mode)         { displayCmd(["set-mode", out, mode]) }
    function setDisplayScale(out, s)           { displayCmd(["set-scale", out, String(s)]) }
    function setDisplayVrr(v)                  { displayCmd(["set-vrr", String(v)]) }
    function setDisplayVibrance(out, v)        { displayCmd(["set-vibrance", out, String(Math.round(v))]) }
    function setDisplayTemperature(k)          { displayCmd(["set-temperature", String(Math.round(k))]) }
    function setDisplayBrightness(b)           { displayCmd(["set-brightness", String(Math.round(b))]) }
    // An exponent, not a percentage: must not be rounded to an integer.
    function setDisplayGamma(g)                { displayCmd(["set-gamma", g.toFixed(3)]) }
    function setDisplayPosition(out, x, y) {
        displayCmd(["set-position", out, String(Math.round(x)), String(Math.round(y))])
    }

    // ── Keep or revert ───────────────────────────────────────────────────
    //
    // A resolution or scale the screen cannot show leaves it black, and then
    // there is no way to reach the control that would undo it. So those two
    // are applied on approval: the new setting goes on at once, and unless it
    // is kept within fifteen seconds the old one comes back -- the same
    // safety every desktop's display settings have.
    //
    // Lives here rather than in the Settings page so the countdown survives
    // the page, or the whole window, being closed with the question open.
    property var displayRevert: null      // { name, mode, scale }
    property int displayRevertLeft: 0

    function monitorByName(name) {
        var ms = root.displayState.monitors || []
        for (var i = 0; i < ms.length; i++)
            if (ms[i].name === name) return ms[i]
        return null
    }

    function remembrance(m) {
        return { name: m.name, mode: m.width + "x" + m.height + "@" + m.refresh, scale: m.scale }
    }

    function proposeDisplayMode(name, mode) {
        var m = root.monitorByName(name)
        if (!m) return
        // Only the first change of a run is remembered: reverting should go
        // back to what worked, not to the previous experiment.
        if (!root.displayRevert || root.displayRevert.name !== name)
            root.displayRevert = root.remembrance(m)
        root.setDisplayMode(name, mode)
        root.displayRevertLeft = 15
        displayRevertTimer.restart()
    }

    function proposeDisplayScale(name, scale) {
        var m = root.monitorByName(name)
        if (!m) return
        if (!root.displayRevert || root.displayRevert.name !== name)
            root.displayRevert = root.remembrance(m)
        root.setDisplayScale(name, scale)
        root.displayRevertLeft = 15
        displayRevertTimer.restart()
    }

    function keepDisplayChanges() {
        displayRevertTimer.stop()
        root.displayRevert = null
        root.displayRevertLeft = 0
    }

    function revertDisplayChanges() {
        displayRevertTimer.stop()
        var r = root.displayRevert
        root.displayRevert = null
        root.displayRevertLeft = 0
        if (!r) return
        root.setDisplayMode(r.name, r.mode)
        root.setDisplayScale(r.name, r.scale)
    }

    Timer {
        id: displayRevertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.displayRevertLeft -= 1
            if (root.displayRevertLeft <= 0) root.revertDisplayChanges()
        }
    }

    function parseDisplay(text) {
        try {
            root.displayState = JSON.parse(text)
        } catch (e) {
            // A failed command still leaves the last good snapshot on screen,
            // which beats blanking the panel on one bad parse.
        }
    }

    Process {
        id: displayProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseDisplay(text)
        }
        onExited: root.displayNext()
    }

    // ── Hyprland options ─────────────────────────────────────────────────
    //
    // For the Settings window's Look and Input pages. scripts/hypr_settings.py
    // owns the rules: a fixed list of options, each checked against its type
    // and range; written to gui-settings.lua, never to hyprland.lua; run live
    // and put back if Hyprland refuses it; committed to ~/dotfiles when it
    // took. This side only asks and shows the answer.
    property var hyprOptions: ({})
    // { repo, hash, when, subject, unpushed } for the sidebar's footer.
    property var dotfilesGit: ({ repo: false })
    // The last set/reset: { ok, error?, commit: { committed, hash? } }, with
    // `at` so the same answer twice still reads as new.
    property var hyprLast: null

    readonly property string hyprScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/hypr_settings.py"

    property var hyprQueue: []

    function hyprCmd(args) {
        root.hyprQueue = root.hyprQueue.concat([args])
        root.hyprNext()
    }

    function hyprNext() {
        if (hyprProc.running || root.hyprQueue.length === 0) return
        var next = root.hyprQueue[0]
        root.hyprQueue = root.hyprQueue.slice(1)
        hyprProc.mode = next[0]
        hyprProc.command = ["python3", root.hyprScript].concat(next)
        hyprProc.running = true
    }

    function refreshHypr() { root.hyprCmd(["get"]) }

    // Shown at once, confirmed or undone by the refresh that follows.
    function setHypr(key, value) {
        var o = root.hyprOptions[key]
        if (o) {
            var next = Object.assign({}, root.hyprOptions)
            next[key] = Object.assign({}, o, { value: value, overridden: true })
            root.hyprOptions = next
        }
        root.hyprCmd(["set", key, String(value)])
        root.hyprCmd(["get"])
    }

    function resetHypr(key) {
        root.hyprCmd(["reset", key])
        root.hyprCmd(["get"])
    }

    Process {
        id: hyprProc
        property string mode: "get"
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try {
                    d = JSON.parse(text)
                } catch (e) {
                    return
                }
                if (hyprProc.mode === "get") {
                    root.hyprOptions = d.options || ({})
                    root.dotfilesGit = d.git || ({ repo: false })
                } else {
                    d.at = Date.now()
                    root.hyprLast = d
                    // The bar parks its pills off the outer gap.
                    root.refreshGaps()
                }
            }
        }
        onExited: root.hyprNext()
    }

    // ── About: the machine, and its backup ───────────────────────────────
    //
    // scripts/about.py for the facts about this machine; scripts/backup.py
    // for the backup of its configuration, in whatever repository Settings ->
    // Shell's backupRepo names (~/dotfiles unless changed) -- made on request
    // if this user has none yet.
    property var aboutInfo: ({})
    property var backupStatus: ({ repo: false })
    property bool backupBusy: false
    // The last action: { action, ok, error?, committed?, at }
    property var backupLast: null

    function refreshAbout() {
        if (!aboutInfoProc.running) aboutInfoProc.running = true
        root.backupCmd("status")
    }

    // status | init | backup | push | github
    function backupCmd(action) {
        if (backupProc.running) return
        root.backupBusy = action !== "status"
        backupProc.action = action
        backupProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/backup.py",
                              action, ShellSettings.backupRepo]
        backupProc.running = true
    }

    Process {
        id: aboutInfoProc
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/about.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.aboutInfo = JSON.parse(text) } catch (e) {}
            }
        }
    }

    Process {
        id: backupProc
        property string action: "status"
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try { d = JSON.parse(text) } catch (e) { return }
                if (backupProc.action === "status") {
                    root.backupStatus = d
                    return
                }
                if (d.status) root.backupStatus = d.status
                root.backupLast = { action: backupProc.action, ok: d.ok, error: d.error || "",
                                    committed: d.committed !== false, at: Date.now() }
            }
        }
        onExited: root.backupBusy = false
    }

    // ── Idle and lock timing ─────────────────────────────────────────────
    //
    // For the Settings window's Power & idle page. The numbers live in
    // hypridle.conf and idle-screens.sh, where they always did; the script
    // only reads and rewrites them.
    property var idleSettings: ({ screensOff: 900, lock: 1200, xiaomiMode: "ddc-off" })

    readonly property string idleScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/idle_settings.py"

    property var idleQueue: []

    function idleCmd(args) {
        root.idleQueue = root.idleQueue.concat([args])
        root.idleNext()
    }

    function idleNext() {
        if (idleProc.running || root.idleQueue.length === 0) return
        var next = root.idleQueue[0]
        root.idleQueue = root.idleQueue.slice(1)
        idleProc.command = ["python3", root.idleScript].concat(next)
        idleProc.running = true
    }

    function refreshIdle() { root.idleCmd(["get"]) }

    // The lock is set as a delay after the screens go off, but hypridle times
    // every listener from the last input -- so it is stored as their sum, and
    // moving the screens-off time carries the lock along with it.
    function setScreensOff(seconds) {
        var delay = Math.max(0, root.idleSettings.lock - root.idleSettings.screensOff)
        root.idleCmd(["set-screens-off", String(seconds)])
        root.idleCmd(["set-lock", String(seconds + delay)])
    }

    function setLockDelay(seconds) {
        root.idleCmd(["set-lock", String(root.idleSettings.screensOff + seconds)])
    }

    function setXiaomiMode(mode) { root.idleCmd(["set-xiaomi-mode", mode]) }

    Process {
        id: idleProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.idleSettings = JSON.parse(text)
                } catch (e) {
                }
            }
        }
        onExited: root.idleNext()
    }

    // ── Power profile ────────────────────────────────────────────────────
    //
    // power-profiles-daemon is the counterpart of Windows' power plans, but it
    // comes up on "balanced" every boot. The script next door remembers the
    // choice and re-applies it; this side only reads and asks.
    //
    // The active profile is read back from the daemon rather than assumed to
    // be whatever the bar last asked for: powerprofilesctl is also used from a
    // terminal, and the daemon can degrade the profile on its own.
    property string powerProfile: ""
    property string powerProfileLabel: ""
    property string powerProfileIcon: "\uf0fc5"
    property var powerProfiles: []

    readonly property string powerProfileScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/power_profile.py"

    function refreshPowerProfiles() {
        powerProfilesProc.command = ["python3", root.powerProfileScript, "list"]
        powerProfilesProc.running = true
    }

    function setPowerProfile(name) {
        if (name === root.powerProfile) return
        powerProfilesProc.command = ["python3", root.powerProfileScript, "set", name]
        powerProfilesProc.running = true
    }

    // On shell start: re-apply the last choice and pick the state up in one
    // pass, since "restore" returns the listing too.
    function restorePowerProfile() {
        powerProfilesProc.command = ["python3", root.powerProfileScript, "restore"]
        powerProfilesProc.running = true
    }

    function parsePowerProfiles(text) {
        try {
            var d = JSON.parse(text)
            root.powerProfile = d.active || ""
            root.powerProfileLabel = d.label || d.active || ""
            root.powerProfileIcon = d.icon || "\uf0fc5"
            root.powerProfiles = d.profiles || []
        } catch (e) {
            root.powerProfiles = []
        }
    }

    Process {
        id: powerProfilesProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parsePowerProfiles(text)
        }
    }

    // Once, on shell start. Delayed because the daemon may not be on the bus
    // yet when quickshell comes up with the session, and a set against an
    // absent bus fails silently.
    Timer {
        running: true
        interval: 1500
        repeat: false
        onTriggered: root.restorePowerProfile()
    }

    FileView {
        id: gamepadStateFile
        path: root.gamepadStatePath
        watchChanges: true
        preload: true
        printErrors: false
        // text() still holds the previous contents inside onFileChanged; the
        // new mode arrives in onLoaded, once the reload lands.
        onFileChanged: reload()
        onLoaded: root.gamepadMode = gamepadStateFile.text().trim()
        // No file at all: the daemon removes it on its way out.
        onLoadFailed: root.gamepadMode = "stopped"
    }

    // ── Lock ─────────────────────────────────────────────────────────────
    //
    // The lock is a surface this shell draws itself now -- see LockEngine and
    // LockScreen -- so there is nothing left to fade around it.
    //
    // What used to be here was a curtain and a script. veila's lock came up
    // through ext-session-lock, which the compositor swaps in whole and draws
    // above every layer quickshell can reach: there was no frame with both the
    // desktop and the lock on screen, so the change was a hard cut in both
    // directions and veila had no setting that softened it. LockOverlay covered
    // the cut with a black window, and scripts/lock_session.sh watched logind's
    // LockedHint to find the two edges of a lock it could not see. A surface
    // this shell owns animates itself, and reports its own edges, so the
    // curtain, the script, the phase machine and their three timers all went.
    //
    // Everything that locks still comes through here rather than calling
    // LockEngine straight: the Hyprland bind, the control panel's button and
    // its suspend all want one entry point.
    function lockSession() {
        LockEngine.lock()
    }

    // Screens under a black cover instead of powered off -- see BlankOverlay.
    // Written by the `screens` ipc target in shell.qml.
    property var blankedScreens: []

    // Set while a lock is on its way to a suspend, so the machine only goes
    // down once the screen is actually covered -- otherwise a moment of the
    // desktop is the last thing on the panels, and on the way back up the lock
    // arrives late over a session that is already visible.
    property bool suspendAfterLock: false

    function suspendSession() {
        // Already covered: nothing to wait for.
        if (LockEngine.secured) {
            suspendProc.running = true
            return
        }
        root.suspendAfterLock = true
        LockEngine.lock()
    }

    // `secured` and not `locked`: the second is only the request this shell
    // made, while the first is the compositor answering that the surface is
    // really in front of the session. Suspending on the request would race the
    // frame the lock is drawn on.
    Connections {
        target: LockEngine

        function onSecuredChanged() {
            if (!LockEngine.secured) return
            if (!root.suspendAfterLock) return
            root.suspendAfterLock = false
            suspendProc.running = true
        }

        // A lock that let go without ever suspending must not leave the flag
        // set -- it would put the machine down the next time anything locked.
        function onLockedChanged() {
            if (!LockEngine.locked) root.suspendAfterLock = false
        }
    }

    Process {
        id: suspendProc
        running: false
        command: ["systemctl", "suspend"]
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
