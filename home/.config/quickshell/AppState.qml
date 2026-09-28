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

    function toggleWifiRadio() {
        wifiToggleProc.command = ["bash", "-c", "nmcli radio wifi " + (root.wifiRadioEnabled ? "off" : "on")]
        wifiToggleProc.running = true
        root.wifiRadioEnabled = !root.wifiRadioEnabled
        wifiRadioRefreshTimer.restart()
    }

    function toggleBluetoothPower() {
        btToggleProc.command = ["bash", "-c", "bluetoothctl power " + (root.btEnabled ? "off" : "on")]
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
    // Open on the focused monitor at the page last seen, or close if open --
    // Super+O (the "settings" global shortcut in shell.qml).
    function toggleSettings() { root.settingsRequested("", root.focusedScreenName()) }

    // ── Escape closes the bar's panels ───────────────────────────────────
    //
    // The pills never take the keyboard: switching a layer surface's keyboard
    // mode while it is up clears its focus grab and shuts the panel (see
    // ControlPanel), and a pill that kept the keyboard would leave it stuck
    // there after closing. So Escape comes from Hyprland instead: while any
    // panel is open, a bind for Escape is added that fires the "dismiss"
    // global shortcut (shell.qml), and it is taken away again when the last
    // panel closes. The rest of the keyboard and every other bind are left
    // alone. The bind also removes itself when pressed, so even with the
    // shell gone it can steal Escape once at most.
    signal dismissRequested()
    function dismissPanels() { root.dismissRequested() }

    // Which panels are open, by "<widget>:<screen>".
    property var openPanels: ({})
    readonly property bool anyPanelOpen: Object.keys(root.openPanels).length > 0

    function setPanelOpen(key, open) {
        var next = Object.assign({}, root.openPanels)
        if (open) next[key] = true
        else delete next[key]
        root.openPanels = next
    }

    onAnyPanelOpenChanged: escapeBind.sync()

    QtObject {
        id: escapeBind
        property bool applied: false

        function sync() {
            if (escapeProc.running) { escapeRetry.restart(); return }
            if (escapeBind.applied === root.anyPanelOpen) return
            escapeBind.applied = root.anyPanelOpen
            escapeProc.command = ["hyprctl", "eval", root.anyPanelOpen
                ? 'pcall(hl.unbind, "Escape"); hl.bind("Escape", function() '
                  + 'hl.dispatch(hl.dsp.global("quickshell:dismiss")); pcall(hl.unbind, "Escape") end)'
                : 'pcall(hl.unbind, "Escape")']
            escapeProc.running = true
        }
    }

    Process {
        id: escapeProc
        running: false
    }

    Timer {
        id: escapeRetry
        interval: 60
        onTriggered: escapeBind.sync()
    }

    // The media panel on the focused monitor: qs ipc call media toggle |
    // open | close -- for a key bind, say.
    signal mediaRequested(string how, string screenName)

    IpcHandler {
        target: "media"
        function toggle(): void { root.mediaRequested("toggle", root.focusedScreenName()) }
        function open(): void { root.mediaRequested("open", root.focusedScreenName()) }
        function close(): void { root.mediaRequested("close", "") }
    }

    // The notification centre on the focused monitor's control pill:
    // qs ipc call notifications toggle | open | close | clear -- for a key
    // bind, say. `clear` empties the centre without opening it.
    signal notificationsRequested(string how, string screenName)

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.notificationsRequested("toggle", root.focusedScreenName()) }
        function open(): void { root.notificationsRequested("open", root.focusedScreenName()) }
        function close(): void { root.notificationsRequested("close", "") }
        function clear(): void { Notifications.dismissAll() }
    }

    function focusedScreenName() {
        var m = Hyprland.focusedMonitor
        return m ? m.name : ""
    }

    // qs ipc call settings open sound -- on the focused monitor.
    IpcHandler {
        target: "settings"
        function open(page: string): void {
            var m = Hyprland.focusedMonitor
            root.openSettings(page.length > 0 ? page : "displays", m ? m.name : "")
        }
        function toggle(): void { root.toggleSettings() }
    }

    function forgetBluetoothDevice(mac, name) {
        root.btActionInProgress = true
        root.btStatusMessage = "Forgetting " + name + "..."
        btActionProc.command = ["bash", "-c", "bluetoothctl remove \"$1\" 2>&1", "_", mac]
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
        wifiConnectProc.command = ["bash", "-c", "nmcli connection down id \"$1\" 2>&1 && echo DISCONNECTED", "_", ssid]
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
            wifiConnectProc.command = ["bash", "-c", "nmcli connection up id \"$1\" 2>&1", "_", ssid]
        } else if (secure) {
            wifiConnectProc.command = ["bash", "-c", "nmcli device wifi connect \"$1\" password \"$2\" 2>&1", "_", ssid, password]
        } else {
            wifiConnectProc.command = ["bash", "-c", "nmcli device wifi connect \"$1\" 2>&1", "_", ssid]
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
        setSinkProc.command = ["bash", "-c", "wpctl set-default " + id]
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
            btActionProc.command = ["bash", "-c", "bluetoothctl connect \"$1\" 2>&1", "_", mac]
        } else {
            // Through scripts/bt_pair.py, which holds an agent open for the
            // pairing: plain `bluetoothctl pair` has none to answer the device,
            // and an encrypted-link device (an Xbox controller) is dropped.
            btActionProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/bt_pair.py", mac]
        }
        btActionProc.running = true
    }

    function disconnectBluetoothDevice(mac, name) {
        root.btActionInProgress = true
        root.btStatusMessage = "Disconnecting " + name + "..."
        btActionProc.command = ["bash", "-c", "bluetoothctl disconnect \"$1\" 2>&1", "_", mac]
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

    // Framing: zoom (1: the largest square the picture holds) and the
    // square's centre as fractions of the picture (see scripts/avatar.py).
    function setAvatar(path, zoom, x, y) {
        root.avatarCmd(zoom === undefined ? ["set", path]
                                          : ["set", path, String(zoom), String(x), String(y)])
    }
    // Frame the picture ~/.face was cut from again.
    function adjustAvatar(zoom, x, y) { root.avatarCmd(["adjust", String(zoom), String(x), String(y)]) }
    function removeAvatar() { root.avatarCmd(["remove"]) }

    // The picture to frame and the framing in use: { path, zoom, x, y }.
    property var avatarFraming: ({ path: "" })
    function refreshAvatarFraming() { if (!avatarFramingProc.running) avatarFramingProc.running = true }

    Process {
        id: avatarFramingProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/avatar.py", "source"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.avatarFraming = JSON.parse(text) } catch (e) {}
            }
        }
    }

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
                root.refreshAvatarFraming()
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
        command: ["bash", "-c", "printf '%s|%s' \"$(uname -n)\" \"$(. /etc/os-release 2>/dev/null && printf '%s' \"$PRETTY_NAME\")\""]
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
        command: ["bash", "-c", "cut -d' ' -f1 /proc/uptime"]
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
        command: ["bash", "-c", "export LC_ALL=C; dev=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"wifi\" && $3==\"connected\"{print $1; exit}'); nmcli -t -f IP4.ADDRESS device show \"$dev\" | cut -d: -f2 | cut -d/ -f1"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiIp = text.trim()
        }
    }

    Process {
        id: btPoweredProc
        running: false
        command: ["bash", "-c", "LC_ALL=C bluetoothctl show | awk '/Powered/{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: root.btEnabled = text.trim() === "yes"
        }
    }

    Process {
        id: btConnectedProc
        running: false
        command: ["bash", "-c", "LC_ALL=C bluetoothctl devices Connected | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: root.btConnectedCount = parseInt(text.trim()) || 0
        }
    }

    Process {
        id: wifiRadioProc
        running: false
        command: ["bash", "-c", "LC_ALL=C nmcli radio wifi"]
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
        command: ["bash", "-c", "nmcli dev wifi rescan >/dev/null 2>&1; sleep 1; LC_ALL=C nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list; echo --saved--; LC_ALL=C nmcli -t -f NAME,TYPE connection show | awk -F: '$NF==\"802-11-wireless\"{print $1}'"]
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
        command: ["bash", "-c", "bash \"$HOME/.config/quickshell/scripts/bt_scan.sh\""]
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
        command: ["bash", "-c", "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort"]
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
    // A Wooting keyboard lit with whatever wallpaper is up, the picture laid
    // over the keys (see scripts/keyboard_rgb.py). Follows wallpaperStill,
    // so a video wallpaper lights it with its poster frame.
    property var keyboardRgbStatus: ({ connected: false })
    // The colours in use: { keys: { "row,col": hex } }, for the Settings page.
    property var keyboardRgbPalette: null
    property string keyboardRgbError: ""
    // The profile the keyboard is on (0-3), -1 until known.
    property int keyboardProfileActive: -1

    readonly property string keyboardRgbScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/keyboard_rgb.py"

    // `animate`: sweep from the old colours to the new (a wallpaper change);
    // without it they switch at once (brightness, a reapply).
    function applyKeyboardRgb(animate) {
        if (!ShellSettings.keyboardRgb || root.wallpaperStill.length === 0) return
        keyboardRgbDebounce.animate = keyboardRgbDebounce.animate || animate === true
        keyboardRgbDebounce.restart()
    }

    function resetKeyboardRgb() {
        root.keyboardRgbSend({ cmd: "reset" })
        root.keyboardRgbPalette = null
    }

    function refreshKeyboardRgb() { root.keyboardRgbSend({ cmd: "status" }) }

    // One line of JSON to the script's `serve` loop, which stays connected
    // to the keyboard: finding it costs two seconds, paid once per session
    // instead of before every change.
    function keyboardRgbSend(obj) {
        if (!keyboardRgbProc.running) keyboardRgbProc.running = true
        keyboardRgbProc.write(JSON.stringify(obj) + "\n")
    }

    onWallpaperStillChanged: root.applyKeyboardRgb(ShellSettings.keyboardRgbAnimate)

    // qs ipc call keyboard apply -- say, bound to a key, after switching
    // profiles on the keyboard (a profile switch covers these colours).
    IpcHandler {
        target: "keyboard"
        function apply(): void { root.applyKeyboardRgb(false) }
        function sweep(): void { root.applyKeyboardRgb(true) }
        function reset(): void { root.resetKeyboardRgb() }
        // What was last sent, key by key ("row,col": colour) -- or the error.
        function status(): string {
            var p = root.keyboardRgbPalette
            return JSON.stringify(p ? p.keys : { error: root.keyboardRgbError })
        }
    }

    Connections {
        target: ShellSettings
        function onKeyboardRgbChanged() {
            if (ShellSettings.keyboardRgb) root.applyKeyboardRgb(ShellSettings.keyboardRgbAnimate)
            else root.resetKeyboardRgb()
        }
        function onKeyboardRgbBrightnessChanged() { root.applyKeyboardRgb(false) }
        function onKeyboardRgbProfileChanged() {
            root.keyboardRgbSend({ cmd: "target", profile: ShellSettings.keyboardRgbProfile })
        }
    }

    // A wallpaper change settles (the crop is rendered, the video's poster is
    // cut) before the keyboard follows; one write, not several.
    Timer {
        id: keyboardRgbDebounce
        property bool animate: false
        interval: 500
        onTriggered: {
            root.keyboardRgbSend({ cmd: "apply", image: root.wallpaperStill,
                                   brightness: ShellSettings.keyboardRgbBrightness,
                                   animate: keyboardRgbDebounce.animate })
            keyboardRgbDebounce.animate = false
        }
    }

    Process {
        id: keyboardRgbProc
        running: true
        stdinEnabled: true
        command: ["python3", root.keyboardRgbScript, "serve"]
        stdout: SplitParser {
            onRead: line => {
                var d
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.cmd === "profile") {
                    root.keyboardProfileActive = d.active
                    return
                }
                // Keyboards plugged in or out: keep the list current without
                // losing the rest of the last status.
                if (d.cmd === "devices") {
                    var st = Object.assign({}, root.keyboardRgbStatus)
                    st.devices = d.devices
                    st.connected = d.devices.length > 0
                    root.keyboardRgbStatus = st
                    return
                }
                if (d.cmd === "status") {
                    root.keyboardRgbStatus = d
                    if (d.active !== null && d.active !== undefined) root.keyboardProfileActive = d.active
                    return
                }
                root.keyboardRgbError = d.ok ? "" : (d.error || "")
                if (d.cmd === "apply" && d.ok && d.keys) root.keyboardRgbPalette = { keys: d.keys }
            }
        }
        // Asked once it is up, so Settings knows whether there is a keyboard.
        onStarted: {
            keyboardRgbProc.write(JSON.stringify({ cmd: "target", profile: ShellSettings.keyboardRgbProfile }) + "\n")
            keyboardRgbProc.write(JSON.stringify({ cmd: "status" }) + "\n")
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
                wallpaperSetProc.command = ["bash", "-c", "P=\"$1\"; hyprctl hyprpaper preload \"$P\" >/dev/null 2>&1; hyprctl hyprpaper wallpaper \",$P,cover\"; printf 'splash = false\\nwallpaper {\\n    monitor =\\n    path = %s\\n    fit_mode = cover\\n}\\n' \"$P\" > \"$HOME/.config/hypr/hyprpaper.conf\"", "_", rendered]
                wallpaperSetProc.running = true
            }
        }
    }

    Process {
        id: micMutedProc
        running: false
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo true || echo false"]
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
        command: ["bash", "-c", "bat=$(ls /sys/class/power_supply/ | grep -m1 '^BAT'); if [ -n \"$bat\" ]; then cat \"/sys/class/power_supply/$bat/capacity\"; else echo none; fi"]
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
        command: ["bash", "-c", "read cpu a b c idle rest < /proc/stat; t1=$((a+b+c+idle)); i1=$idle; sleep 0.4; read cpu a b c idle rest < /proc/stat; t2=$((a+b+c+idle)); i2=$idle; dt=$((t2-t1)); di=$((i2-i1)); if [ \"$dt\" -gt 0 ]; then echo $(( (100*(dt-di))/dt )); else echo 0; fi"]
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
        command: ["bash", "-c", "free | awk '/Mem:/{printf \"%d\", ($3/$2)*100}'"]
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
        command: ["bash", "-c", "df --output=pcent / | tail -1 | tr -d '% '"]
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
        command: ["bash", "-c", "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf \"%d\", $1/1000}'"]
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

    // ── Network, Bluetooth and the rest of the bar's status ──────────────
    //
    // Read when something says it changed, not on a clock. This was one
    // timer starting eight processes every 15 seconds -- and one of them,
    // `nmcli dev wifi`, set off a full Wi-Fi scan each time the last was over
    // 30 seconds old (see net_status.sh). Now NetworkManager and BlueZ are
    // listened to, and a slow poll only catches what they do not announce:
    // the Wi-Fi signal drifting, the tablet driver, a battery if there is one.
    // The microphone is not here at all: pactl subscribe (below) covers it.
    function refreshNetwork() {
        if (!wifiProc.running) wifiProc.running = true
        if (!wifiIpProc.running) wifiIpProc.running = true
        if (!wifiRadioProc.running) wifiRadioProc.running = true
    }

    function refreshBluetooth() {
        if (!btPoweredProc.running) btPoweredProc.running = true
        if (!btConnectedProc.running) btConnectedProc.running = true
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        property bool first: true
        onTriggered: {
            root.refreshNetwork()
            root.refreshBluetooth()
            otdStateProc.running = true
            // Once, and then only while a battery exists: a desktop answers
            // "none" and there is nothing to keep asking about.
            if (first || root.batteryPresent) batteryProc.running = true
            if (first) micMutedProc.running = true
            first = false
        }
    }

    // `nmcli monitor` prints a line for every change NetworkManager makes:
    // connecting, dropping, the radio switched, a cable in.
    Process {
        id: networkEvents
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: line => { if (!networkEventThrottle.running) networkEventThrottle.start() }
        }
        onExited: networkEventsRestart.restart()
    }

    Timer {
        id: networkEventsRestart
        interval: 5000
        onTriggered: networkEvents.running = true
    }

    // Read once per burst: a connection coming up is a dozen lines.
    Timer {
        id: networkEventThrottle
        interval: 400
        onTriggered: root.refreshNetwork()
    }

    // BlueZ over D-Bus: powered on and off, devices connecting. A scan in
    // progress streams signal updates, which the throttle holds to a read
    // every 400ms rather than one per signal.
    Process {
        id: bluetoothEvents
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.bluez"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("Powered") === -1 && line.indexOf("Connected") === -1
                        && line.indexOf("InterfacesRemoved") === -1) return
                if (!bluetoothEventThrottle.running) bluetoothEventThrottle.start()
            }
        }
        onExited: bluetoothEventsRestart.restart()
    }

    Timer {
        id: bluetoothEventsRestart
        interval: 5000
        onTriggered: bluetoothEvents.running = true
    }

    Timer {
        id: bluetoothEventThrottle
        interval: 400
        onTriggered: root.refreshBluetooth()
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
        onTriggered: audioEvents.running = true
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
        root.syncSubmap()
        if (!root.launcherOpen) return
        var monitor = Hyprland.focusedMonitor
        root.launcherScreen = monitor ? monitor.name : ""
    }

    function toggleLauncher() {
        root.launcherOpen = !root.launcherOpen
    }

    // The workspace overview (Super+Tab): every workspace, with its windows.
    // Pinned to the screen it was opened on, like the launcher.
    property bool overviewOpen: false
    property string overviewScreen: ""

    onOverviewOpenChanged: {
        root.syncSubmap()
        if (!root.overviewOpen) return
        var monitor = Hyprland.focusedMonitor
        root.overviewScreen = monitor ? monitor.name : ""
    }

    function toggleOverview() {
        if (!root.overviewOpen) root.launcherOpen = false
        root.overviewOpen = !root.overviewOpen
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggleOverview() }
        function open(): void { if (!root.overviewOpen) root.toggleOverview() }
        function close(): void { root.overviewOpen = false }
    }

    // The launcher and the overview put Hyprland in its "shell-modal"
    // submap while either is up (hyprland.lua), where Super+drag and the
    // other binds do nothing -- they reached the windows behind the overlay.
    // Set again on every change of either: Super+Tab or Super+Space drop
    // the submap themselves, and one may be opening as the other closes.
    // Reset once as the shell starts, in case one died with it set.
    readonly property bool modalOpen: root.overviewOpen || root.launcherOpen

    function syncSubmap() {
        Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.submap('"
                                 + (root.modalOpen ? "shell-modal" : "reset") + "'))"])
    }

    Timer {
        running: true
        interval: 0
        onTriggered: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.submap('reset'))"])
    }

    // Text to start the field with, taken by the launcher as it opens.
    property string launcherPreset: ""

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleLauncher() }
        // Open with the field already holding `query` ("" for empty).
        function open(query: string): void {
            root.launcherPreset = query
            root.launcherOpen = true
        }
        function close(): void { root.launcherOpen = false }
    }

    // ── Screen recording ─────────────────────────────────────────────────
    //
    // One monitor at a time, as Settings -> Recording says (by default 1080p
    // 60 fps H.264 MP4 with the computer's sound), encoded on the GPU
    // (scripts/screen_record.sh). Started and
    // stopped from the control panel's Record tile, the red dot the control
    // pill shows while it runs, Super+Shift+R, or `qs ipc call record ...`.
    // Stopped with SIGINT, which is what makes the recorder finish the file.
    readonly property bool recording: recordProc.running
    property string recordingFile: ""
    property string recordingMonitor: ""
    property real recordingSince: 0
    property int recordingSeconds: 0

    function startRecording(monitor) {
        if (recordProc.running) return
        root.recordingFile = ""
        root.recordingMonitor = monitor || root.focusedScreenName()
        recordProc.command = [Quickshell.env("HOME") + "/.config/quickshell/scripts/screen_record.sh",
                              "--monitor", root.recordingMonitor,
                              "--height", ShellSettings.recordResolution,
                              "--fps", String(ShellSettings.recordFps),
                              "--quality", ShellSettings.recordQuality,
                              "--codec", ShellSettings.recordCodec,
                              "--audio", ShellSettings.recordAudio,
                              "--cursor", ShellSettings.recordCursor ? "yes" : "no",
                              "--dir", ShellSettings.recordFolder]
        root.recordingSince = Date.now()
        root.recordingSeconds = 0
        recordProc.running = true
    }

    // Where recordings are going, for the Settings page.
    readonly property string recordingFolder: ShellSettings.recordFolder.length > 0
        ? ShellSettings.recordFolder
        : Quickshell.env("HOME") + "/Vídeos/Recordings"

    // A folder picked in a dialog (zenity); cancelling it changes nothing.
    function chooseRecordingFolder() {
        if (folderPickProc.running) return
        folderPickProc.running = true
    }

    Process {
        id: folderPickProc
        running: false
        command: ["zenity", "--file-selection", "--directory", "--title=Where recordings are saved",
                  "--filename=" + root.recordingFolder + "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = text.trim()
                if (d.length > 0) ShellSettings.set("recordFolder", d)
            }
        }
    }

    function stopRecording() {
        if (recordProc.running) recordProc.signal(2)
    }

    // Record, with a count of three first, shown on the control pill where
    // the recording's time then runs -- nothing over the screen, so the
    // three seconds are there to get to what is to be recorded. Pressing
    // record again during the count, or the pill, calls it off. Stop, if
    // recording already.
    function toggleRecording(monitor) {
        if (recordProc.running) root.stopRecording()
        else if (root.recordCountdown > 0) root.cancelRecordingCountdown()
        else root.countdownRecording(monitor)
    }

    // 3, 2, 1 while counting; 0 otherwise.
    property int recordCountdown: 0
    property string recordCountdownMonitor: ""

    function countdownRecording(monitor) {
        if (recordProc.running || root.recordCountdown > 0) return
        root.recordCountdownMonitor = monitor || root.focusedScreenName()
        root.recordCountdown = 3
        countdownTick.restart()
    }

    function cancelRecordingCountdown() {
        countdownTick.stop()
        root.recordCountdown = 0
    }

    Timer {
        id: countdownTick
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.recordCountdown > 1) {
                root.recordCountdown -= 1
                return
            }
            countdownTick.stop()
            root.recordCountdown = 0
            root.startRecording(root.recordCountdownMonitor)
        }
    }


    // "4:07", or "1:02:33" past the hour.
    function recordingClock(sec) {
        var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
        var ss = (s < 10 ? "0" : "") + s
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
    }

    Process {
        id: recordProc
        running: false
        stdout: SplitParser {
            // The script's first line is the file it records to.
            onRead: line => { if (root.recordingFile === "") root.recordingFile = line.trim() }
        }
        stderr: StdioCollector { id: recordErr }
        onExited: (code, status) => {
            var file = root.recordingFile
            var short = file.replace(Quickshell.env("HOME"), "~")
            if (file.length > 0 && root.recordingSeconds >= 1) {
                // Saved: said so, with a button that opens it.
                Quickshell.execDetached(["bash", "-c",
                    'a=$(notify-send -a "Screen recorder" -i video-x-generic -A open=Open "Recording saved" "$2"); '
                    + '[ "$a" = open ] && xdg-open "$1"', "_", file, short])
            } else {
                var why = recordErr.text.trim().split("\n").pop()
                Quickshell.execDetached(["notify-send", "-a", "Screen recorder", "-i", "dialog-error",
                                         "Recording failed", why.length > 0 ? why : "The recorder stopped at once."])
            }
            root.recordingSince = 0
        }
    }

    // The clock the tile and the pill show; only runs while recording.
    Timer {
        interval: 1000
        repeat: true
        running: recordProc.running
        onTriggered: root.recordingSeconds = Math.floor((Date.now() - root.recordingSince) / 1000)
    }

    IpcHandler {
        target: "record"
        function toggle(): void { root.toggleRecording("") }
        // With the count first, as the tile and the shortcut do.
        function start(): void { root.countdownRecording("") }
        function stop(): void { root.stopRecording() }
        function status(): string { return recordProc.running ? "recording " + root.recordingFile : "idle" }
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
    // screen. Straight to Hyprland's Lua, which knows the cursor's monitor:
    // it went through display_control.py, and starting Python cost 80ms on
    // every launch.
    function focusCursorMonitor() {
        Quickshell.execDetached(["hyprctl", "eval",
            "local m = hl.get_monitor_at_cursor(); if m then hl.dispatch(hl.dsp.focus({ monitor = m.name })) end"])
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
