pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The Steam games installed here, for the launcher (scripts/steam_games.py
// reads them off Steam's own files). Read when the launcher opens, at most
// once a minute, so a game installed since shows up without anything
// polling in between.
Singleton {
    id: root

    // [{ id, name, icon, run, kind, update }]
    property var games: []
    property real readAt: 0

    function refresh() {
        if (reader.running || Date.now() - root.readAt < 60000) return
        reader.running = true
    }

    Process {
        id: reader
        running: false
        command: ["python3", Quickshell.shellPath("scripts/steam_games.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.games = JSON.parse(text)
                    root.readAt = Date.now()
                } catch (e) {
                    // Keep the last good list.
                }
            }
        }
    }

    // Made on first use -- the launcher's first opening -- which is past the
    // signal below for that opening.
    Component.onCompleted: root.refresh()

    Connections {
        target: Panels
        function onLauncherOpenChanged() {
            if (Panels.launcherOpen) root.refresh()
        }
    }
}
