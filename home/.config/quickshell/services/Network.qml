pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi and wired state for the bar's icon and the Wi-Fi panel: the
// connection and its signal, the scan list, connecting and disconnecting.
// Driven by `nmcli monitor`, with a slow poll behind it.
Singleton {
    id: root

    property string wifiSsid: ""
    property string wifiIp: ""
    property bool wifiRadioEnabled: true
    // The connected network's signal (0-100), for the bar's icon; -1 when
    // not on Wi-Fi. ethernetUp: a wired connection, which the bar shows
    // instead of a crossed-out Wi-Fi icon.
    property int wifiSignal: -1
    property bool ethernetUp: false
    property var wifiNetworks: []
    property string wifiExpandedSsid: ""
    property string wifiStatusMessage: ""
    property bool wifiConnecting: false

    readonly property bool wifiScanning: wifiScanProc.running

    function toggleWifiRadio() {
        wifiToggleProc.command = ["bash", "-c", "nmcli radio wifi " + (root.wifiRadioEnabled ? "off" : "on")]
        wifiToggleProc.running = true
        root.wifiRadioEnabled = !root.wifiRadioEnabled
        wifiRadioRefreshTimer.restart()
    }

    function scanWifiNetworks() {
        if (!wifiScanProc.running) wifiScanProc.running = true
    }

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

    Timer {
        id: wifiRadioRefreshTimer
        interval: 600
        onTriggered: wifiRadioProc.running = true
    }

    // ── Keeping up ───────────────────────────────────────────────────────
    //
    // Read when something says it changed, not on a clock. This was one
    // timer starting eight processes every 15 seconds -- and one of them,
    // `nmcli dev wifi`, set off a full Wi-Fi scan each time the last was over
    // 30 seconds old (see net_status.sh). Now NetworkManager is listened to,
    // and a slow poll only catches what it does not announce: the signal
    // drifting.
    function refreshNetwork() {
        if (!wifiProc.running) wifiProc.running = true
        if (!wifiIpProc.running) wifiIpProc.running = true
        if (!wifiRadioProc.running) wifiRadioProc.running = true
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshNetwork()
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
}
