pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The desktop widgets: the kinds, which are on which monitor and where, and whether a desktop can
// be seen. They live under the windows and are placed in the widget picker (Super+D); the layout is
// in desktop-widgets.json, written when a widget is added, moved or removed, never mid-drag.
Singleton {
    id: root

    // The kinds: `file` is the component under desktop/widgets/. Each is laid out for its own w and
    // h, so resizing scales the whole widget (its `size`) instead of stretching it.
    readonly property var categories: ["Clock", "Calendar", "Weather", "Media", "System"]

    readonly property var catalog: [
        { kind: "clock-pill", name: "Pill", category: "Clock", file: "PillClock",
          description: "The time and the day on one line, like the bar.", w: 352, h: 72 },
        { kind: "clock-digital", name: "Digital", category: "Clock", file: "DigitalClock",
          description: "The time large, the day under it.", w: 288, h: 120 },
        { kind: "clock-analog", name: "Analog", category: "Clock", file: "AnalogClock",
          description: "Hands on a dial, a tick for every hour.", w: 208, h: 208 },
        { kind: "calendar-month", name: "Month", category: "Calendar", file: "MonthCalendar",
          description: "The month, turned with the arrows or the wheel.", w: 288, h: 304 },
        { kind: "calendar-week", name: "Week", category: "Calendar", file: "WeekCalendar",
          description: "This week on one strip.", w: 288, h: 112 },
        { kind: "weather-now", name: "Now", category: "Weather", file: "WeatherNow",
          description: "The sky outside, humidity and wind.", w: 288, h: 128 },
        { kind: "weather-forecast", name: "Forecast", category: "Weather", file: "WeatherForecast",
          description: "Highs and lows for the next five days.", w: 288, h: 200 },
        { kind: "media", name: "Now playing", category: "Media", file: "NowPlaying",
          description: "Cover, progress and the controls.", w: 288, h: 336 },
        { kind: "visualizer", name: "Visualizer", category: "Media", file: "Visualizer",
          description: "What is playing, as a spectrum.", w: 368, h: 144 },
        { kind: "system", name: "Resources", category: "System", file: "SystemMeters",
          description: "CPU, memory and GPU, as they work.", w: 320, h: 248 },
        { kind: "machine", name: "This machine", category: "System", file: "MachineInfo",
          description: "What it runs, and what it runs on.", w: 320, h: 256 }
    ]

    function spec(kind) {
        for (var i = 0; i < root.catalog.length; i++)
            if (root.catalog[i].kind === kind) return root.catalog[i]
        return null
    }

    // [{ id, kind, screen, x, y, size, glass }]: x and y in the monitor's logical pixels from its
    // top-left. `size` scales the kind's w and h; older widgets without one draw at 1. `glass` is
    // the card's own glass opacity; without one it uses the shell's.
    readonly property var placed: adapter.widgets

    // How small and big a widget can get: the smallest text is 10px (8px at the low end), and
    // covers and avatars loaded at 512 and 128px still have enough pixels at the high end.
    readonly property real minSize: 0.8
    readonly property real maxSize: 2

    function sizeOf(w) { return w && w.size > 0 ? w.size : 1 }

    // The alpha of a widget's glass, each its own. Floor 0.35: the desktop
    // layer rule only blurs pixels at alpha 0.3 or more (ignore_alpha in
    // hyprland.lua), and under it the card would turn clear, not frosted.
    readonly property real minGlass: 0.35
    readonly property real maxGlass: 1
    readonly property real defaultGlass: 0.9

    function glassOf(w) { return w && w.glass > 0 ? w.glass : root.defaultGlass }

    function setGlass(id, a) {
        var g = Math.round(Math.max(root.minGlass, Math.min(root.maxGlass, a)) * 20) / 20
        adapter.widgets = root.placed.map(w => w.id === id ? Object.assign({}, w, { glass: g }) : w)
    }

    function onScreen(screenName) {
        return root.placed.filter(w => w.screen === screenName && root.spec(w.kind) !== null)
    }

    function countOf(kind) {
        return root.placed.filter(w => w.kind === kind).length
    }

    function newId() {
        return "w" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
    }

    // `id` is for a caller that has to know it before the widget exists (the picker's spring-in).
    function add(kind, screenName, x, y, id) {
        id = id || root.newId()
        adapter.widgets = root.placed.concat([{ id: id, kind: kind, screen: screenName,
                                                x: Math.round(x), y: Math.round(y), size: 1 }])
        return id
    }

    function move(id, x, y) {
        adapter.widgets = root.placed.map(w => w.id === id
            ? Object.assign({}, w, { x: Math.round(x), y: Math.round(y) }) : w)
    }

    // In twentieths, so sizes form a short list and two made "the same size" by hand are.
    function resize(id, size) {
        var s = Math.round(Math.max(root.minSize, Math.min(root.maxSize, size)) * 20) / 20
        adapter.widgets = root.placed.map(w => w.id === id ? Object.assign({}, w, { size: s }) : w)
    }

    function remove(id) {
        adapter.widgets = root.placed.filter(w => w.id !== id)
    }

    // Where a clicked-in widget goes: the first gap it fits, from the top right,
    // above `areaH` (the shelf's top).
    function freeSpot(screenName, w, h, areaW, areaH, top) {
        var margin = 24
        var gap = 16
        var others = root.onScreen(screenName).map(o => {
            var s = root.spec(o.kind)
            var k = root.sizeOf(o)
            return { x: o.x, y: o.y, w: s.w * k, h: s.h * k }
        })
        function clear(x, y) {
            for (var i = 0; i < others.length; i++) {
                var o = others[i]
                if (x < o.x + o.w + gap && x + w + gap > o.x && y < o.y + o.h + gap && y + h + gap > o.y)
                    return false
            }
            return true
        }
        for (var x = areaW - margin - w; x >= margin; x -= 16)
            for (var y = top; y + h <= areaH - margin; y += 16)
                if (clear(x, y)) return { x: x, y: y }
        // Full: on top of the rest, at the first column, to be dragged away.
        return { x: Math.max(margin, areaW - margin - w), y: top }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/desktop-widgets.json"
        blockLoading: true
        watchChanges: true
        atomicWrites: true

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: adapter
            property var widgets: []
        }
    }

    // Whether a monitor's desktop shows: widgets that redraw all the time (spectrum, meters)
    // stop while a tiled window covers the desktop; floating ones are let be. Read off
    // Hyprland's events once they settle.
    property var covered: ({})

    function isCovered(screenName) { return root.covered[screenName] === true }

    Timer {
        id: coverRefresh
        interval: 150
        onTriggered: {
            Hyprland.refreshToplevels()
            coverApply.restart()
        }
    }

    Timer {
        id: coverApply
        interval: 200
        onTriggered: {
            var next = {}
            var ms = Hyprland.monitors.values
            for (var i = 0; i < ms.length; i++) {
                var ws = ms[i].activeWorkspace
                var tops = ws && ws.toplevels ? ws.toplevels.values : []
                var tiled = false
                for (var t = 0; t < tops.length && !tiled; t++) {
                    var o = tops[t].lastIpcObject || {}
                    // Unknown counts as tiled: better a still meter than a
                    // spectrum drawing for nobody.
                    if (o.floating !== true) tiled = true
                }
                next[ms[i].name] = tiled
            }
            root.covered = next
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow": case "closewindow": case "movewindowv2": case "changefloatingmode":
            case "workspacev2": case "focusedmonv2": case "monitoraddedv2": case "monitorremovedv2":
                coverRefresh.restart()
            }
        }
    }

    Component.onCompleted: coverRefresh.restart()
}
