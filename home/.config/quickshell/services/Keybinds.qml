pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// What the keybinds sheet lists: Hyprland's binds, read out of its Lua
// config, and Yazi's, out of its keymap. Both files are watched, so the sheet
// follows an edit.
Singleton {
    id: root

    // ── Hyprland's binds ─────────────────────────────────────────────────
    //
    // Read out of the config file rather than `hyprctl binds`: with a Lua
    // config every bind reports the dispatcher "__lua" and an opaque
    // callback index, so the compositor can list the keys but cannot say
    // what a single one of them does. scripts/hypr_binds.lua runs the config
    // against a stub `hl` table instead, which gets the loops, the locals and
    // any required file along with everything else.
    readonly property string hyprConfigPath: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"

    // [{ name, binds: [{ keys, action, command }] }]
    property var hyprBindGroups: []
    property int hyprBindCount: 0
    property string hyprBindsError: ""

    // Keys the config points at this shell's cheatsheet, read back out of
    // that config so the control panel's hint follows a rebind instead of
    // repeating a combination written in the QML.
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

    // An editor usually writes a config as a rename over the old inode, which
    // can land as several events; the debounce collapses those into one read.
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

    // ── Yazi's binds ─────────────────────────────────────────────────────
    //
    // Its own reader and its own section in the sheet: yazi's keymap is TOML
    // and most of what its keyboard does is compiled into the binary rather
    // than written in any file, so nothing about it is shaped like the
    // Hyprland side. See scripts/yazi_binds.py.
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

    // Second path to the same refresh: a rename-over can cost the watch above
    // its inode, and this fires whenever Hyprland itself picks the file up.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "configreloaded") return
            hyprBindsDebounce.restart()
        }
    }
}
