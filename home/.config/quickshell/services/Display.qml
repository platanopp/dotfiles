pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Monitors, for Settings -> Displays and Colour: modes, scale, layout, VRR,
// vibrance and the colour filter, all through scripts/display_control.py.
// Plus the keep-or-revert countdown after a mode or scale change.
Singleton {
    id: root

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

    // What Settings -> Displays and Colour chose -- mode, position and scale
    // per monitor, vibrance, the colour filter -- played back: nothing of it
    // survives on its own (Hyprland re-reads its config, nvibrant resets with
    // the driver, hyprsunset starts fresh), and the script saves every choice
    // for exactly this. Once as the shell starts, which is the session
    // starting, and again whenever a monitor is plugged back in. It answers
    // with the whole state, like `list`.
    function restoreDisplay()                  { displayCmd(["restore"]) }

    Component.onCompleted: root.restoreDisplay()

    // Monitors come and go -- a cable pulled, a screen that drops its link in
    // standby -- and the list was only read when Settings opened, so an
    // unplugged screen stayed on the Displays page. Read again whenever
    // Hyprland says one was added or removed, once the burst of events a
    // hotplug brings has settled; a monitor that arrived also gets its saved
    // settings back.
    property bool hotplugAdded: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "monitoradded": case "monitoraddedv2":
                root.hotplugAdded = true
                hotplugSettle.restart()
                break
            case "monitorremoved": case "monitorremovedv2":
                hotplugSettle.restart()
            }
        }
    }

    Timer {
        id: hotplugSettle
        interval: 600
        onTriggered: {
            if (root.hotplugAdded) root.restoreDisplay()
            else root.refreshDisplay()
            root.hotplugAdded = false
        }
    }

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
}
