pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Which panels and overlays are open, and on which screen, plus what drives them from outside: the
// IPC targets, the Escape bind and the "shell-modal" submap.
Singleton {
    id: root

    // The bar's panels use it to link to their fuller Settings page.
    signal settingsRequested(string page, string screenName)
    function openSettings(page, screenName) { root.settingsRequested(page, screenName) }
    // Super+O: open on the focused monitor at the last page seen, or close.
    function toggleSettings() { root.settingsRequested("", root.focusedScreenName()) }

    // Pills never take the keyboard, so while a panel is open a temporary Hyprland
    // bind sends Escape to "dismiss". It removes itself when pressed, so a dead
    // shell steals Escape once at most.
    signal dismissRequested()
    function dismissPanels() { root.dismissRequested() }

    // Keyed "<widget>:<screen>".
    property var openPanels: ({})
    readonly property bool anyPanelOpen: Object.keys(root.openPanels).length > 0

    function setPanelOpen(key, open) {
        var next = Object.assign({}, root.openPanels)
        if (open) next[key] = true
        else delete next[key]
        root.openPanels = next
    }

    onAnyPanelOpenChanged: escapeBind.sync()

    QtObject {
        id: escapeBind
        property bool applied: false

        function sync() {
            if (escapeProc.running) { escapeRetry.restart(); return }
            if (escapeBind.applied === root.anyPanelOpen) return
            escapeBind.applied = root.anyPanelOpen
            escapeProc.command = ["hyprctl", "eval", root.anyPanelOpen
                ? 'pcall(hl.unbind, "Escape"); hl.bind("Escape", function() '
                  + 'hl.dispatch(hl.dsp.global("quickshell:dismiss")); pcall(hl.unbind, "Escape") end)'
                : 'pcall(hl.unbind, "Escape")']
            escapeProc.running = true
        }
    }

    Process {
        id: escapeProc
        running: false
    }

    Timer {
        id: escapeRetry
        interval: 60
        onTriggered: escapeBind.sync()
    }

    // qs ipc call media toggle | open | close, on the focused monitor.
    signal mediaRequested(string how, string screenName)

    IpcHandler {
        target: "media"
        function toggle(): void { root.mediaRequested("toggle", root.focusedScreenName()) }
        function open(): void { root.mediaRequested("open", root.focusedScreenName()) }
        function close(): void { root.mediaRequested("close", "") }
    }

    // qs ipc call notifications toggle | open | close | clear (clear empties it without opening).
    signal notificationsRequested(string how, string screenName)

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.notificationsRequested("toggle", root.focusedScreenName()) }
        function open(): void { root.notificationsRequested("open", root.focusedScreenName()) }
        function close(): void { root.notificationsRequested("close", "") }
        function clear(): void { Notifications.dismissAll() }
    }

    function focusedScreenName() {
        var m = Hyprland.focusedMonitor
        return m ? m.name : ""
    }

    // qs ipc call settings open sound, on the focused monitor.
    IpcHandler {
        target: "settings"
        function open(page: string): void {
            var m = Hyprland.focusedMonitor
            root.openSettings(page.length > 0 ? page : "displays", m ? m.name : "")
        }
        function toggle(): void { root.toggleSettings() }
    }

    // Lives here because both the control panel and a global shortcut open it.
    property bool keybindsOpen: false

    // Latched on open, so the sheet stays put when the pointer moves to the other monitor.
    property string keybindsScreen: ""

    onKeybindsOpenChanged: {
        root.syncSubmap()
        if (!root.keybindsOpen) return
        var monitor = Hyprland.focusedMonitor
        root.keybindsScreen = monitor ? monitor.name : ""
        // The file watches usually cover this; re-reading on open is a cheap guarantee.
        Keybinds.refreshHyprBinds()
        Keybinds.refreshYaziBinds()
    }

    function toggleKeybinds() {
        root.keybindsOpen = !root.keybindsOpen
    }

    // qs ipc call keybinds toggle | open | close.
    IpcHandler {
        target: "keybinds"
        function toggle(): void { root.toggleKeybinds() }
        function open(): void { root.keybindsOpen = true }
        function close(): void { root.keybindsOpen = false }
    }

    // Lives here for the same reasons as the cheatsheet: two openers, pinned to its screen.
    property bool wallpapersOpen: false
    property string wallpapersScreen: ""

    onWallpapersOpenChanged: {
        root.syncSubmap()
        if (!root.wallpapersOpen) return
        var monitor = Hyprland.focusedMonitor
        root.wallpapersScreen = monitor ? monitor.name : ""
        // Picks up files added while the shell was running.
        Wallpaper.refreshWallpaperList()
        Wallpaper.refreshVideoWallpapers()
    }

    function toggleWallpapers() {
        root.wallpapersOpen = !root.wallpapersOpen
    }

    // Lives here for the same reasons: a global shortcut opens it, and it stays on its screen.
    property bool launcherOpen: false
    property string launcherScreen: ""

    onLauncherOpenChanged: {
        root.syncSubmap()
        if (!root.launcherOpen) return
        var monitor = Hyprland.focusedMonitor
        root.launcherScreen = monitor ? monitor.name : ""
    }

    function toggleLauncher() {
        root.launcherOpen = !root.launcherOpen
    }

    // Super+Tab: up on every screen at once; the keyboard follows the pointer.
    property bool overviewOpen: false
    property string overviewScreen: ""
    // Closing to go to a workspace: every screen's overview closes and lets go of the keyboard.
    property bool overviewLeaving: false

    // A window dragged in the overview, shared by every screen: the source screen keeps the pointer
    // grab, the one under the pointer draws it and reports where it would land.
    // overviewDrag     { address, toplevel, cls, from, w, h, homeW, homeH, fx, fy }
    // overviewDragAt   the pointer, in layout coordinates
    // overviewDropAt   { screen, key, id, isNew, scale }, from that screen
    // overviewDropped  { address, screen, key }, once it is let go there
    property var overviewDrag: null
    property point overviewDragAt: Qt.point(0, 0)
    property var overviewDropAt: null
    property var overviewDropped: null

    onOverviewOpenChanged: {
        root.syncSubmap()
        if (!root.overviewOpen) return
        var monitor = Hyprland.focusedMonitor
        root.overviewScreen = monitor ? monitor.name : ""
        roundingProc.running = true
    }

    // Hyprland's corner rounding, for the overview's windows; re-read on each
    // open, -1 until the first answer.
    property int overviewRounding: -1

    Process {
        id: roundingProc
        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var v = JSON.parse(text).int
                    if (typeof v === "number" && v >= 0) root.overviewRounding = v
                } catch (e) {}
            }
        }
    }

    function toggleOverview() {
        if (!root.overviewOpen) {
            root.launcherOpen = false
            root.overviewLeaving = false
            root.overviewDrag = null
            root.overviewDropAt = null
            root.overviewDropped = null
        }
        root.overviewOpen = !root.overviewOpen
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggleOverview() }
        function open(): void { if (!root.overviewOpen) root.toggleOverview() }
        function close(): void { root.overviewOpen = false }
    }

    // Super+D. Pinned to the screen it opened on, and edits that screen's widgets.
    property bool widgetsOpen: false
    property string widgetsScreen: ""

    onWidgetsOpenChanged: {
        root.syncSubmap()
        if (!root.widgetsOpen) return
        var monitor = Hyprland.focusedMonitor
        root.widgetsScreen = monitor ? monitor.name : ""
    }

    function toggleWidgets() {
        if (!root.widgetsOpen) {
            root.launcherOpen = false
            root.overviewOpen = false
        }
        root.widgetsOpen = !root.widgetsOpen
    }

    IpcHandler {
        target: "widgets"
        function toggle(): void { root.toggleWidgets() }
        function open(): void { if (!root.widgetsOpen) root.toggleWidgets() }
        function close(): void { root.widgetsOpen = false }
    }

    // While one is up Hyprland sits in its "shell-modal" submap (hyprland.lua), so binds
    // can't reach the windows behind. Re-synced on every change (Super+Tab/Space drop the
    // submap themselves) and reset at startup.
    readonly property bool modalOpen: root.overviewOpen || root.launcherOpen || root.wallpapersOpen
                                      || root.keybindsOpen || root.widgetsOpen

    // Debounced and serialised: two hyprctl calls close together could land in either order and
    // leave the submap set with nothing open.
    function syncSubmap() {
        submapSync.restart()
    }

    Timer {
        id: submapSync
        interval: 40
        onTriggered: {
            if (submapProc.running) {
                submapSync.restart()
                return
            }
            submapProc.command = ["hyprctl", "eval", "hl.dispatch(hl.dsp.submap('"
                                  + (root.modalOpen ? "shell-modal" : "reset") + "'))"]
            submapProc.running = true
        }
    }

    Process {
        id: submapProc
        running: false
        // The state may have changed while it ran.
        onExited: {
            var want = root.modalOpen ? "shell-modal" : "default"
            submapCheck.command = ["hyprctl", "submap"]
            submapCheck.want = want
            submapCheck.running = true
        }
    }

    // Verify: if Hyprland's submap disagrees with the shell's state, set it again.
    Process {
        id: submapCheck
        property string want: "default"
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var now = text.trim()
                var want = root.modalOpen ? "shell-modal" : "default"
                if (now !== want) submapSync.restart()
            }
        }
    }

    Timer {
        running: true
        interval: 0
        onTriggered: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.submap('reset'))"])
    }

    // Text to start the field with, taken by the launcher as it opens.
    property string launcherPreset: ""

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleLauncher() }
        // Open with the field already holding `query` ("" for empty).
        function open(query: string): void {
            root.launcherPreset = query
            root.launcherOpen = true
        }
        function close(): void { root.launcherOpen = false }
    }
}
