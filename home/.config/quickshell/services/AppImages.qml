pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The AppImages in ~/Applications, put in the launcher each time it opens
// (scripts/appimage_sync.py) -- the way SteamGames reads the Steam library.
//
// The script writes each new AppImage a .desktop file and icon, and removes
// them when the file goes; DesktopEntries notices those files by itself, so
// a new app joins the list a moment after the launcher opens. Nothing is
// read back here.
Singleton {
    id: root

    property real syncedAt: 0

    // At most every few seconds, against opening and closing in a burst. A
    // run with nothing new is about 30ms in its own process, so there is no
    // reason for Steam's minute.
    function refresh() {
        if (sync.running || Date.now() - root.syncedAt < 5000) return
        root.syncedAt = Date.now()
        sync.running = true
    }

    Process {
        id: sync
        running: false
        command: ["python3", Quickshell.shellPath("scripts/appimage_sync.py")]
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: Panels
        function onLauncherOpenChanged() {
            if (Panels.launcherOpen) root.refresh()
        }
    }
}
