pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Monitors, for Settings -> Displays and Colour: modes, scale, layout, VRR, vibrance and
// the colour filter, all through scripts/display_control.py, plus the keep-or-revert
// countdown after a mode or scale change.
Singleton {
    id: root

    // Display settings: one script drives hyprctl (modes, layout), nvibrant (saturation) and
    // hyprsunset (colour matrix), and every command returns the whole snapshot.
    property var displayState: ({
        monitors: [], vibrance: ({}),
        colour: ({ temperature: 6000, brightness: 100, gamma: 1.0 }),
        colour_active: false, vrr: 0
    })

    readonly property string displayScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/display_control.py"

    // Queued: setting `running` on a busy Process does nothing, so a scale picked
    // right after a resolution was lost.
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

    // Plays back what Settings chose (mode, position, scale, vibrance, colour filter),
    // since none of it survives on its own. At shell start and whenever a monitor is
    // plugged back in; answers with the whole state.
    function restoreDisplay()                  { displayCmd(["restore"]) }

    Component.onCompleted: root.restoreDisplay()

    // Re-read when Hyprland adds or removes a monitor, once the hotplug burst settles; an arriving
    // monitor also gets its saved settings back.
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

    // Focus the pointer's monitor before the launcher spawns anything: follow_mouse
    // can't while a layer holds the keyboard. Straight to Hyprland's Lua: going
    // through Python cost 80ms per launch.
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

    // Keep or revert: a resolution or scale the screen cannot show leaves it black, so it
    // reverts unless kept within fifteen seconds. Lives here so the countdown survives
    // the Settings page or window closing.
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
        // Only the first change of a run is remembered, so reverting goes back to what worked.
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
            // A failed command keeps the last good snapshot on screen
            // rather than blanking the panel.
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
