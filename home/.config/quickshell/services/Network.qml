pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi and wired state for the bar's icon and the Wi-Fi panel, driven by `nmcli
// monitor` with a slow poll behind it.
Singleton {
    id: root

    property string wifiSsid: ""
    property string wifiIp: ""
    property bool wifiRadioEnabled: true
    // The connected network's signal (0-100), -1 when not on Wi-Fi. ethernetUp: wired, shown
    // instead of a crossed-out Wi-Fi icon.
    property int wifiSignal: -1
    property bool ethernetUp: false
    property var wifiNetworks: []
    property string wifiExpandedSsid: ""
    property string wifiStatusMessage: ""
    property bool wifiConnecting: false
    // What the running connect or disconnect is, for its message.
    property string wifiAction: ""

    readonly property bool wifiScanning: wifiScanProc.running

    // Panels showing the list: while any is open, NetworkManager's events refresh it too.
    property int wifiWatchers: 0
    function watchWifi() { root.wifiWatchers++ }
    function unwatchWifi() { root.wifiWatchers = Math.max(0, root.wifiWatchers - 1) }

    // A result stays a few seconds; an error until the panel opens again.
    function clearWifiStatus() {
        if (!root.wifiConnecting) root.wifiStatusMessage = ""
    }

    Timer {
        id: wifiStatusClear
        interval: 4000
        onTriggered: if (!root.wifiConnecting) root.wifiStatusMessage = ""
    }

    function toggleWifiRadio() {
        wifiToggleProc.command = ["bash", "-c", "nmcli radio wifi " + (root.wifiRadioEnabled ? "off" : "on")]
        wifiToggleProc.running = true
        root.wifiRadioEnabled = !root.wifiRadioEnabled
        wifiRadioRefreshTimer.restart()
    }

    // What NetworkManager already knows, listed at once; then a real scan, which takes the card off
    // its channel for a few seconds, so only when asked.
    function scanWifiNetworks() {
        root.listWifiNetworks()
        if (!wifiScanProc.running) wifiScanProc.running = true
    }

    function listWifiNetworks() {
        if (!wifiListProc.running) wifiListProc.running = true
    }

    // The active connection on the Wi-Fi device, whatever it is named.
    function disconnectWifi() {
        root.wifiConnecting = true
        root.wifiAction = "disconnect"
        root.wifiStatusMessage = "Disconnecting…"
        wifiConnectProc.command = ["bash", "-c", "export LC_ALL=C; "
            + "dev=$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2==\"wifi\" && $3==\"connected\"{print $1; exit}'); "
            + "uuid=$(nmcli -g GENERAL.CON-UUID device show \"$dev\" 2>/dev/null); "
            + "nmcli connection down uuid \"$uuid\" 2>&1 && echo DISCONNECTED"]
        wifiConnectProc.running = true
    }

    // The networks in range as "IN-USE:SIGNAL:SECURITY:SSID", the SSID last and unescaped so a colon
    // in it stays whole; then "--saved--" and each saved Wi-Fi connection as "SSID<TAB>name", since
    // a connection's name need not be its SSID. "rescan" first makes the card look again.
    readonly property string listScript: "export LC_ALL=C; "
        + "[ \"$1\" = rescan ] && { nmcli dev wifi rescan >/dev/null 2>&1; sleep 1; }; "
        + "nmcli -t -e no -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan no; echo --saved--; "
        + "nmcli -t -f UUID,TYPE connection show | awk -F: '$2==\"802-11-wireless\"{print $1}' | "
        + "while read -r u; do nmcli -e no -g 802-11-wireless.ssid,connection.id connection show uuid \"$u\" | paste -s -d '\\t'; done"

    function parseWifiScan(text) {
        var halves = text.split("--saved--")
        var saved = {}
        var savedLines = (halves[1] || "").split("\n")
        for (var k = 0; k < savedLines.length; k++) {
            var pair = savedLines[k].split("\t")
            if (pair.length >= 2 && pair[0].length > 0) saved[pair[0]] = pair.slice(1).join("\t")
        }
        var lines = halves[0].trim().length > 0 ? halves[0].trim().split("\n") : []
        var byS = {}
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split(":")
            if (parts.length < 4) continue
            var ssid = parts.slice(3).join(":")
            if (ssid.length === 0) continue
            var signal = parseInt(parts[1]) || 0
            var entry = {
                ssid: ssid,
                inUse: parts[0] === "*",
                signal: signal,
                secure: parts[2].length > 0 && parts[2] !== "--",
                saved: saved[ssid] !== undefined,
                savedName: saved[ssid] || ""
            }
            // A multi-band AP shows once per band: keep the strongest but carry the in-use flag, or
            // a connected weaker band looked disconnected.
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
        // The same list again would rebuild every row for nothing.
        if (JSON.stringify(list) !== JSON.stringify(root.wifiNetworks)) root.wifiNetworks = list
    }

    function toggleWifiExpand(ssid) {
        root.wifiExpandedSsid = (root.wifiExpandedSsid === ssid) ? "" : ssid
        root.wifiStatusMessage = ""
    }

    // savedName: the saved connection for this network, which connects without asking again.
    function connectToWifi(ssid, password, secure, savedName) {
        root.wifiConnecting = true
        root.wifiAction = "connect"
        root.wifiStatusMessage = "Connecting to " + ssid + "…"
        if (savedName) {
            wifiConnectProc.command = ["bash", "-c", "nmcli connection up id \"$1\" 2>&1", "_", savedName]
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
        id: wifiListProc
        running: false
        command: ["bash", "-c", root.listScript, "_"]
        stdout: StdioCollector {
            onStreamFinished: root.parseWifiScan(text)
        }
    }

    Process {
        id: wifiScanProc
        running: false
        command: ["bash", "-c", root.listScript, "_", "rescan"]
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
                var low = out.toLowerCase()
                if (root.wifiAction === "disconnect") {
                    root.wifiStatusMessage = out.indexOf("DISCONNECTED") !== -1 ? "Disconnected" : "Could not disconnect"
                } else if (low.indexOf("error") !== -1) {
                    root.wifiStatusMessage = low.indexOf("secrets were required") !== -1 || low.indexOf("password") !== -1
                        ? "Wrong password"
                        : low.indexOf("no network with ssid") !== -1 ? "That network is out of range"
                        : "Could not connect"
                } else {
                    root.wifiStatusMessage = "Connected"
                }
                if (!/^Could not|^Wrong|out of range$/.test(root.wifiStatusMessage)) {
                    root.wifiExpandedSsid = ""
                    wifiStatusClear.restart()
                }
                // The list from what NetworkManager knows: a rescan right after connecting would
                // take the card off its new channel.
                wifiProc.running = true
                wifiIpProc.running = true
                root.listWifiNetworks()
                root.wifiConnecting = false
                root.wifiAction = ""
            }
        }
    }

    Timer {
        id: wifiRadioRefreshTimer
        interval: 600
        onTriggered: wifiRadioProc.running = true
    }

    // Keeping up: read when NetworkManager announces a change; the slow poll only catches signal
    // drift. (The old 15s timer ran eight processes, one of them triggering full Wi-Fi scans.)
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
        onTriggered: {
            root.refreshNetwork()
            if (root.wifiWatchers > 0) root.listWifiNetworks()
        }
    }
}
