pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.lock

// Power and the session: the battery (if any), the power profile, the idle
// timeouts, and locking and suspending.
Singleton {
    id: root

    // ── Battery ──────────────────────────────────────────────────────────
    //
    // Read from /sys: whether there is one, and its charge.
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

    // Once, and then only while a battery exists: a desktop answers "none"
    // and there is nothing to keep asking about.
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
}
