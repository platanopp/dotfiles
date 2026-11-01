pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// OpenTabletDriver, for Settings -> Input and the control panel's tile:
// whether its daemon is running, and starting or stopping it.
Singleton {
    id: root

    // opentabletdriver.service reads the tablet as raw HID and publishes its own
    // virtual device; a udev rule hides the kernel's device, so turning the service off
    // leaves the pen dead (the tile says so).
    property bool otdRunning: false

    function toggleOtd() {
        otdToggleProc.command = ["bash", "-c", "systemctl --user "
            + (root.otdRunning ? "stop" : "start") + " opentabletdriver.service"]
        otdToggleProc.running = true
        // Optimistic, like the other toggles: confirmed 900ms later instead
        // of leaving the tile still while systemd answers.
        root.otdRunning = !root.otdRunning
        otdRefreshTimer.restart()
    }

    Process { id: otdToggleProc; running: false }

    Process {
        id: otdStateProc
        running: false
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

    // Read once a minute too: the service can be started or stopped from a
    // terminal, and nothing announces it.
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: otdStateProc.running = true
    }
}
