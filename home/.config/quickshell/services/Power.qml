pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.lock

// Power and the session: the battery (if any), the power profile, the idle
// timeouts, and locking and suspending.
Singleton {
    id: root

    // Battery, read from /sys: whether there is one, and its charge.
    property bool batteryPresent: false
    property real batteryPercent: 0

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

    // Once, then only while a battery exists: a desktop answers "none".
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        property bool first: true
        onTriggered: {
            if (first || root.batteryPresent) batteryProc.running = true
            first = false
        }
    }

    // Idle and lock timing, for Settings -> Power & idle. The numbers live in hypridle.conf and
    // idle-screens.sh; the script only reads and rewrites them.
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

    // The lock is a delay after the screens go off, but hypridle times every listener from the last
    // input, so it is stored as their sum and moves with the screens-off time.
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

    // Power profile: power-profiles-daemon starts on "balanced" every boot, so the script
    // remembers the choice and re-applies it. Read back from the daemon, which can also change
    // from a terminal or degrade on its own.
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

    // On shell start: re-apply the last choice and read the state in one pass
    // ("restore" returns the listing).
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

    // Once, delayed: the daemon may not be on the bus yet at session start, and a
    // set against it fails silently.
    Timer {
        running: true
        interval: 1500
        repeat: false
        onTriggered: root.restorePowerProfile()
    }

    // Lock: the lock is this shell's own surface (LockEngine, LockScreen), which animates
    // itself. Everything that locks (the Hyprland bind, the control panel and its suspend) still
    // comes through here, as one entry point.
    function lockSession() {
        LockEngine.lock()
    }

    // Screens under a black cover instead of powered off (BlankOverlay),
    // written by the `screens` ipc target.
    property var blankedScreens: []

    // Set while a lock leads to a suspend, so the machine goes down only once the screen is
    // covered: otherwise the desktop shows on wake before the lock arrives.
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

    // `secured`, not `locked`: the compositor's answer that the surface is in
    // front, not just this shell's request.
    Connections {
        target: LockEngine

        function onSecuredChanged() {
            if (!LockEngine.secured) return
            if (!root.suspendAfterLock) return
            root.suspendAfterLock = false
            suspendProc.running = true
        }

        // A lock released without suspending must clear the flag, or the next lock would suspend.
        function onLockedChanged() {
            if (!LockEngine.locked) root.suspendAfterLock = false
        }
    }

    Process {
        id: suspendProc
        running: false
        command: ["systemctl", "suspend"]
    }
}
