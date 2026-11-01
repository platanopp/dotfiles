pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The layout of the keyboard last typed on (Hyprland's "main" one), for the
// status pill and the toast. The Akko and the Redragon list their two layouts
// in opposite order (hyprland.lua), so the main keyboard is what counts.
Singleton {
    id: root

    // xkb's description, e.g. "English (intl., with AltGr dead keys)".
    property string name: ""
    // More than one layout set up; with one, nothing to show or switch.
    property bool multiple: false
    readonly property bool english: name.indexOf("English") === 0
    readonly property string code: name === "" ? "" : english ? "US"
                                 : name.indexOf("Spanish") === 0 ? "LA" : name.slice(0, 2).toUpperCase()
    readonly property string label: english ? "English (US)"
                                  : name.indexOf("Spanish") === 0 ? "Spanish (Latin America)" : name

    // A change after the first reading, for the toast.
    signal switched()

    function switchNext() { switchProc.running = true }

    Connections {
        target: Hyprland
        // One event per keyboard on a switch; read once after the burst.
        function onRawEvent(event) {
            if (event.name === "activelayout") readLater.restart()
        }
    }

    Timer {
        id: readLater
        interval: 60
        onTriggered: devicesProc.running ? readLater.restart() : devicesProc.running = true
    }

    Process {
        id: devicesProc
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var kb
                try {
                    kb = JSON.parse(text).keyboards.find(k => k.main)
                } catch (e) {
                    return
                }
                if (!kb) return
                root.multiple = kb.layout.indexOf(",") >= 0
                if (kb.active_keymap === root.name) return
                var first = root.name === ""
                root.name = kb.active_keymap
                if (!first) root.switched()
            }
        }
    }

    Process {
        id: switchProc
        command: ["hyprctl", "switchxkblayout", "all", "next"]
    }
}
