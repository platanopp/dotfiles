pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The installed Steam games for the launcher (steam_games.py reads Steam's files),
// read on open at most once a minute.
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
