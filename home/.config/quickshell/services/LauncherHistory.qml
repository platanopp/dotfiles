pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What the launcher has opened, so the most used come first. A singleton, since AppLauncher has a
// copy per monitor. Kept in ~/.local/state: a record of use, not a setting for the dotfiles.
Singleton {
    id: root

    // desktop id -> { count, last } (last in Date.now() ms)
    property var usage: ({})

    // How much a launch is still worth after this many days: half every two
    // weeks, so last month's habit gives way to this week's.
    readonly property real halfLifeDays: 14

    function frecency(id) {
        var u = root.usage[id]
        if (!u) return 0
        var days = (Date.now() - u.last) / 86400000
        return u.count * Math.pow(0.5, days / root.halfLifeDays)
    }

    function record(id) {
        if (!id) return
        var next = Object.assign({}, root.usage)
        var u = next[id] || { count: 0, last: 0 }
        next[id] = { count: u.count + 1, last: Date.now() }
        root.usage = next
        file.setText(JSON.stringify(root.usage))
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/state/quickshell-launcher.json"
        printErrors: false
        // Read before anything is asked: a launch recorded before an async load
        // returned would overwrite the history.
        blockLoading: true
        onLoaded: root.load()
    }

    // Also at once: with blockLoading the text is there immediately, but `loaded`
    // only fires after the first query.
    Component.onCompleted: root.load()

    function load() {
        try {
            var parsed = JSON.parse(file.text() || "{}")
            if (parsed && typeof parsed === "object") root.usage = parsed
        } catch (e) {
            root.usage = {}
        }
    }
}
