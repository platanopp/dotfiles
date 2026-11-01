pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Frequency bands for whatever the speakers play, from spectrum.py, which runs
// only while subscribed: subscribe()/unsubscribe(), since several media widgets
// would fight over a `running` binding.
Singleton {
    id: root

    // Half a ring's worth; the widget mirrors these around the circle.
    readonly property int bandCount: 24

    // One value per band, 0..1, low frequencies first.
    property var bands: root.emptyBands()

    property int subscribers: 0
    readonly property bool active: subscribers > 0

    function emptyBands() {
        var a = []
        for (var i = 0; i < bandCount; i++) a.push(0)
        return a
    }

    function subscribe() { root.subscribers++ }
    function unsubscribe() { if (root.subscribers > 0) root.subscribers-- }

    // Collapse rather than freeze on the last frame when nobody is watching.
    onActiveChanged: {
        if (root.active) {
            linger.stop()
        } else {
            root.bands = root.emptyBands()
            linger.restart()
        }
    }

    // The helper outlives its last watcher by a few seconds, so a brief look away
    // (the overview over the visualizer) doesn't restart Python, numpy and the
    // capture. Frames are dropped meanwhile.
    Timer {
        id: linger
        interval: 10000
    }

    Process {
        running: root.active || linger.running
        command: ["python3", Quickshell.shellPath("scripts/spectrum.py")]

        stdout: SplitParser {
            onRead: function(data) {
                if (!root.active) return
                var parts = data.trim().split(" ")
                if (parts.length !== root.bandCount) return
                var out = []
                for (var i = 0; i < parts.length; i++) {
                    var v = parseInt(parts[i], 10)
                    out.push(isNaN(v) ? 0 : v / 100)
                }
                root.bands = out
            }
        }
    }
}
