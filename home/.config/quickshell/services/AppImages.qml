pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The AppImages in ~/Applications, synced into the launcher each time it opens
// (appimage_sync.py writes and removes their .desktop files and icons; DesktopEntries
// notices). Nothing is read back here.
Singleton {
    id: root

    property real syncedAt: 0

    // At most every few seconds against bursts; a run with nothing new is ~30ms.
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
