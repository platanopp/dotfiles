pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// What the keybinds sheet lists: Hyprland's binds from its Lua config and Yazi's from its keymap;
// both files are watched, so the sheet follows an edit.
Singleton {
    id: root

    // Hyprland's binds, read from the config: with Lua, `hyprctl binds` reports every
    // dispatcher as "__lua". scripts/hypr_binds.lua runs the config against a stub `hl`
    // table, loops and required files included.
    readonly property string hyprConfigPath: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"

    // [{ name, binds: [{ keys, action, command }] }]
    property var hyprBindGroups: []
    property int hyprBindCount: 0
    property string hyprBindsError: ""

    // The keys the config binds to this cheatsheet, so the control panel's hint follows a rebind.
    property string hyprOverlayKeys: ""

    function refreshHyprBinds() {
        if (!hyprBindsProc.running) hyprBindsProc.running = true
    }

    Process {
        id: hyprBindsProc
        running: true
        command: ["lua", Quickshell.env("HOME") + "/.config/quickshell/scripts/hypr_binds.lua",
                  root.hyprConfigPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text)
                    root.hyprBindGroups = parsed.groups || []
                    root.hyprBindCount = parsed.count || 0
                    root.hyprOverlayKeys = parsed.overlayKeys || ""
                    root.hyprBindsError = parsed.error || ""
                } catch (e) {
                    root.hyprBindGroups = []
                    root.hyprBindCount = 0
                    root.hyprOverlayKeys = ""
                    root.hyprBindsError = "Could not read " + root.hyprConfigPath
                }
            }
        }
    }

    // An editor writing by rename can fire several events; the debounce makes them one read.
    Timer {
        id: hyprBindsDebounce
        interval: 400
        onTriggered: root.refreshHyprBinds()
    }

    FileView {
        path: root.hyprConfigPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: hyprBindsDebounce.restart()
    }

    // Yazi's binds: its own reader (scripts/yazi_binds.py), since the keymap is TOML and
    // most of yazi's keys are compiled in.
    property var yaziBindGroups: []
    property int yaziBindCount: 0
    property string yaziBindsError: ""

    readonly property string yaziKeymapPath:
        Quickshell.env("HOME") + "/.config/yazi/keymap.toml"

    function refreshYaziBinds() {
        if (!yaziBindsProc.running) yaziBindsProc.running = true
    }

    Process {
        id: yaziBindsProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/yazi_binds.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text)
                    root.yaziBindGroups = parsed.groups || []
                    root.yaziBindCount = parsed.count || 0
                    root.yaziBindsError = parsed.error || ""
                } catch (e) {
                    root.yaziBindGroups = []
                    root.yaziBindCount = 0
                    root.yaziBindsError = "Could not read yazi's keymap"
                }
            }
        }
    }

    FileView {
        path: root.yaziKeymapPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: yaziBindsDebounce.restart()
    }

    Timer {
        id: yaziBindsDebounce
        interval: 400
        onTriggered: root.refreshYaziBinds()
    }

    // A second path to the same refresh: a rename can cost the watch its inode, and
    // this fires when Hyprland reloads.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "configreloaded") return
            hyprBindsDebounce.restart()
        }
    }
}
