pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Frequency bands for whatever the speakers are playing, fed by spectrum.py.
//
// Capturing audio costs CPU, so the helper only runs while something is
// actually looking at it. Consumers call subscribe()/unsubscribe() rather than
// binding `running` directly: with one bar per monitor there can be several
// media widgets, and they would otherwise fight over the same property.
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
    onActiveChanged: if (!root.active) root.bands = root.emptyBands()

    Process {
        running: root.active
        command: ["python3", Quickshell.shellPath("spectrum.py")]

        stdout: SplitParser {
            onRead: function(data) {
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
