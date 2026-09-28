pragma Singleton
import QtQuick
import Quickshell
import qs.config

// The time and date the bar shows.
Singleton {
    id: root

    property string currentTime: root.formatTime(new Date())
    // Pinned to en_US rather than left to the system locale, so the bar reads
    // the same whatever LANG happens to be set to.
    property string currentDate: new Date().toLocaleDateString(Qt.locale("en_US"), "d MMMM")

    // 24-hour or 12-hour, from Settings -> Shell.
    function formatTime(d) {
        return Qt.formatDateTime(d, ShellSettings.clock24h ? "hh:mm" : "h:mm AP")
    }

    Connections {
        target: ShellSettings
        function onClock24hChanged() { root.currentTime = root.formatTime(new Date()) }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.currentTime = root.formatTime(new Date())
            root.currentDate = new Date().toLocaleDateString(Qt.locale("en_US"), "d MMMM")
        }
    }
}
