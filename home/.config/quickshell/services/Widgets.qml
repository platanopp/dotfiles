pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The desktop widgets: which kinds there are, which are on which monitor
// and where, and whether a monitor's desktop can be seen at all.
//
// They took the place of four kitty windows parked on the side monitor
// (fastfetch, tty-clock, cava, btop): as windows they tiled and floated with
// everything else, took focus, and had to be pinned in place by rules. These
// live under the windows, in the shell, and are placed by dragging them in
// the widget picker (overlays/WidgetPicker.qml, Super + D).
//
// The layout is kept in desktop-widgets.json beside the config, written when
// a widget is added, dropped or removed -- never while one is being dragged.
Singleton {
    id: root

    // ── The kinds ────────────────────────────────────────────────────────
    //
    // `file` is the component under desktop/widgets/. Sizes are fixed per
    // kind: each is laid out for its size, and a widget that stretched would
    // only be the same thing with more empty space in it.
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

    // ── The layout ───────────────────────────────────────────────────────

    // [{ id, kind, screen, x, y }]; x and y in the monitor's own logical
    // pixels, from its top-left corner.
    readonly property var placed: adapter.widgets

    function onScreen(screenName) {
        return root.placed.filter(w => w.screen === screenName && root.spec(w.kind) !== null)
    }

    function countOf(kind) {
        return root.placed.filter(w => w.kind === kind).length
    }

    // Returns the new widget's id, for the picker to animate it in.
    function add(kind, screenName, x, y) {
        var id = "w" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
        adapter.widgets = root.placed.concat([{ id: id, kind: kind, screen: screenName,
                                                x: Math.round(x), y: Math.round(y) }])
        return id
    }

    function move(id, x, y) {
        adapter.widgets = root.placed.map(w => w.id === id
            ? { id: w.id, kind: w.kind, screen: w.screen, x: Math.round(x), y: Math.round(y) } : w)
    }

    function remove(id) {
        adapter.widgets = root.placed.filter(w => w.id !== id)
    }

    // Where a widget clicked (rather than dragged) in goes: the first gap it
    // fits, searched from the top right, above `areaH` -- the picker passes
    // the top of its shelf, since a widget that landed under the shelf would
    // seem not to have arrived.
    function freeSpot(screenName, w, h, areaW, areaH, top) {
        var margin = 24
        var gap = 16
        var others = root.onScreen(screenName).map(o => {
            var s = root.spec(o.kind)
            return { x: o.x, y: o.y, w: s.w, h: s.h }
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

    // ── Whether a monitor's desktop shows ────────────────────────────────
    //
    // The widgets sit under every window, so most of the time on a monitor
    // in use they are covered. The ones that redraw all the time -- the
    // spectrum, the resource meters -- stop while a tiled window is over the
    // desktop and start again when it is bare (floating windows rarely cover
    // all of it, and are let be). Read off Hyprland's events, a moment after
    // they settle, the way the video wallpaper's pause is.
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
