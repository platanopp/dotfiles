pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Which of the shell's panels and overlays are open, and on which screen:
// the bar's pills, Settings, the launcher, the workspace overview, the
// wallpaper picker and the keybinds sheet. Also what opens and closes them
// from outside -- the IPC targets, Escape, and Hyprland's "shell-modal"
// submap while an overlay is up.
Singleton {
    id: root

    // Asks the control panel on that screen to open Settings at a page --
    // for the bar's own panels, which link to their fuller page.
    signal settingsRequested(string page, string screenName)
    function openSettings(page, screenName) { root.settingsRequested(page, screenName) }
    // Open on the focused monitor at the page last seen, or close if open --
    // Super+O (the "settings" global shortcut in shell.qml).
    function toggleSettings() { root.settingsRequested("", root.focusedScreenName()) }

    // ── Escape closes the bar's panels ───────────────────────────────────
    //
    // The pills never take the keyboard: switching a layer surface's keyboard
    // mode while it is up clears its focus grab and shuts the panel (see
    // ControlPanel), and a pill that kept the keyboard would leave it stuck
    // there after closing. So Escape comes from Hyprland instead: while any
    // panel is open, a bind for Escape is added that fires the "dismiss"
    // global shortcut (shell.qml), and it is taken away again when the last
    // panel closes. The rest of the keyboard and every other bind are left
    // alone. The bind also removes itself when pressed, so even with the
    // shell gone it can steal Escape once at most.
    signal dismissRequested()
    function dismissPanels() { root.dismissRequested() }

    // Which panels are open, by "<widget>:<screen>".
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

    // The media panel on the focused monitor: qs ipc call media toggle |
    // open | close -- for a key bind, say.
    signal mediaRequested(string how, string screenName)

    IpcHandler {
        target: "media"
        function toggle(): void { root.mediaRequested("toggle", root.focusedScreenName()) }
        function open(): void { root.mediaRequested("open", root.focusedScreenName()) }
        function close(): void { root.mediaRequested("close", "") }
    }

    // The notification centre on the focused monitor's control pill:
    // qs ipc call notifications toggle | open | close | clear -- for a key
    // bind, say. `clear` empties the centre without opening it.
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

    // qs ipc call settings open sound -- on the focused monitor.
    IpcHandler {
        target: "settings"
        function open(page: string): void {
            var m = Hyprland.focusedMonitor
            root.openSettings(page.length > 0 ? page : "displays", m ? m.name : "")
        }
        function toggle(): void { root.toggleSettings() }
    }

    // The cheatsheet overlay. Lives here because two unrelated things open
    // it: the control panel's button and the Hyprland global shortcut.
    property bool keybindsOpen: false

    // Monitor the cheatsheet was summoned on, latched on the way open.
    //
    // The overlay used to just render on whichever monitor was focused, but
    // focus follows the mouse here (input:follow_mouse = 1), so moving the
    // pointer to the other screen carried the sheet along with it -- off the
    // work it was opened to explain. Pinned instead until it closes.
    property string keybindsScreen: ""

    onKeybindsOpenChanged: {
        root.syncSubmap()
        if (!root.keybindsOpen) return
        var monitor = Hyprland.focusedMonitor
        root.keybindsScreen = monitor ? monitor.name : ""
        // The file watches normally have this covered; re-reading on the way
        // in is the cheap guarantee that what gets shown is what is on disk.
        Keybinds.refreshHyprBinds()
        Keybinds.refreshYaziBinds()
    }

    function toggleKeybinds() {
        root.keybindsOpen = !root.keybindsOpen
    }

    // The wallpaper picker. Same two reasons as the cheatsheet for living
    // here: the control panel opens it, so does a global shortcut, and it
    // has to stay on the screen it was summoned on rather than follow the
    // pointer to the other monitor.
    property bool wallpapersOpen: false
    property string wallpapersScreen: ""

    onWallpapersOpenChanged: {
        root.syncSubmap()
        if (!root.wallpapersOpen) return
        var monitor = Hyprland.focusedMonitor
        root.wallpapersScreen = monitor ? monitor.name : ""
        // Cheap, and it means a file dropped into the folder while the shell
        // was running is there the first time the picker is opened.
        Wallpaper.refreshWallpaperList()
        Wallpaper.refreshVideoWallpapers()
    }

    function toggleWallpapers() {
        root.wallpapersOpen = !root.wallpapersOpen
    }

    // The application launcher. Same reason as the two above for living here
    // rather than in the component: it is opened from a global shortcut, and
    // it has to stay on the screen it was summoned on rather than follow the
    // pointer to the other monitor.
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

    // The workspace overview (Super+Tab): every workspace, with its windows.
    // Pinned to the screen it was opened on, like the launcher.
    property bool overviewOpen: false
    property string overviewScreen: ""

    onOverviewOpenChanged: {
        root.syncSubmap()
        if (!root.overviewOpen) return
        var monitor = Hyprland.focusedMonitor
        root.overviewScreen = monitor ? monitor.name : ""
    }

    function toggleOverview() {
        if (!root.overviewOpen) root.launcherOpen = false
        root.overviewOpen = !root.overviewOpen
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggleOverview() }
        function open(): void { if (!root.overviewOpen) root.toggleOverview() }
        function close(): void { root.overviewOpen = false }
    }

    // The launcher, the overview, the wallpaper picker and the shortcut
    // sheet put Hyprland in its "shell-modal" submap while one is up (hyprland.lua), where Super+drag and the
    // other binds do nothing -- they reached the windows behind the overlay.
    // Set again on every change of either: Super+Tab or Super+Space drop
    // the submap themselves, and one may be opening as the other closes.
    // Reset once as the shell starts, in case one died with it set.
    readonly property bool modalOpen: root.overviewOpen || root.launcherOpen || root.wallpapersOpen
                                      || root.keybindsOpen

    // One call, with where things ended up, a moment after they settle --
    // not one per change: two changes close together (the launcher closing
    // as the overview opens, an overview opened and closed at once) sent two
    // hyprctl processes that could land in either order, and the submap was
    // left set with nothing open. Serialised too: the next waits for the last.
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
        // Once it has run, the state may have moved on again meanwhile.
        onExited: {
            var want = root.modalOpen ? "shell-modal" : "default"
            submapCheck.command = ["hyprctl", "submap"]
            submapCheck.want = want
            submapCheck.running = true
        }
    }

    // And checked: if Hyprland's submap is not what the shell's state says,
    // it is set again.
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
