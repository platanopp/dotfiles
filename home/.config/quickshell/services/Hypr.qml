pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Hyprland's settings as the shell sees them: the window gaps the bar lines up with, and the
// options Settings -> Look and Input change.
Singleton {
    id: root

    // Hyprland options: hypr_settings.py owns the rules (a fixed, type-checked list written to
    // gui-settings.lua, never hyprland.lua; applied live, rolled back if refused, committed to
    // ~/dotfiles). This side asks and shows.
    property var hyprOptions: ({})
    // { repo, hash, when, subject, unpushed } for the sidebar's footer.
    property var dotfilesGit: ({ repo: false })
    // The last set/reset: { ok, error?, commit: { committed, hash? } }, with `at` so
    // the same answer twice reads as new.
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

    // A stand-in until the first answer, so pages can bind before it arrives.
    function option(key) { return root.hyprOptions[key] || ({ value: 0, overridden: false }) }
    function optionValue(key, fallback) {
        var o = root.hyprOptions[key]
        return o && o.value !== null && o.value !== undefined ? o.value : fallback
    }

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

    // Window gaps, asked of Hyprland rather than repeated here, so the bar can't drift from the
    // windows' inset. The defaults are Hyprland's own, wrong only until the first answer.
    property int gapTop: 20
    property int gapRight: 30
    property int gapBottom: 30
    property int gapLeft: 30

    function refreshGaps() {
        if (!gapsProc.running) gapsProc.running = true
    }

    // gaps_out is a CSS shorthand string: one value for all sides, two for vertical/horizontal,
    // three for top/sides/bottom, four for each.
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

    // Gaps can change with a config reload.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.refreshGaps()
        }
    }
}
