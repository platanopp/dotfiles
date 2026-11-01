pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth for the bar's icon and panel through bluetoothctl; BlueZ's D-Bus signals say
// when to look again. Not Quickshell.Bluetooth's singleton: files needing that one import
// it qualified (lock/LockEngine.qml).
Singleton {
    id: root

    property bool btEnabled: false
    property int btConnectedCount: 0

    property var bluetoothDevices: []
    property string btStatusMessage: ""
    property bool btActionInProgress: false
    readonly property bool btScanning: btScanProc.running

    function toggleBluetoothPower() {
        btToggleProc.command = ["bash", "-c", "bluetoothctl power " + (root.btEnabled ? "off" : "on")]
        btToggleProc.running = true
        root.btEnabled = !root.btEnabled
        btRefreshTimer.restart()
    }

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
            // Through bt_pair.py, which holds an agent for the pairing: plain `bluetoothctl pair`
            // has none, and an encrypted-link device (an Xbox controller) is dropped.
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

    function forgetBluetoothDevice(mac, name) {
        root.btActionInProgress = true
        root.btStatusMessage = "Forgetting " + name + "..."
        btActionProc.command = ["bash", "-c", "bluetoothctl remove \"$1\" 2>&1", "_", mac]
        btActionProc.running = true
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
        id: btToggleProc
        running: false
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
        id: btRefreshTimer
        interval: 600
        onTriggered: btPoweredProc.running = true
    }

    // Keeping up: read when BlueZ announces a change; the slow poll only catches a missed event.
    function refreshBluetooth() {
        if (!btPoweredProc.running) btPoweredProc.running = true
        if (!btConnectedProc.running) btConnectedProc.running = true
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshBluetooth()
    }

    // BlueZ over D-Bus. A running scan streams updates, throttled to one read every 400ms.
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
}
