pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The shell's own preferences, in one JSON file beside the config:
// ~/.config/quickshell/shell-settings.json. The Settings window's Shell page
// writes it; the pieces that used to have these choices hard-coded read it.
//
// Loaded before anything asks (blockLoading), because the lock that runs
// once per boot reads lockAtBoot at the very start of the session -- a value
// arriving a moment later would have been a lock the user switched off.
// A file edited by hand is picked up too (watchChanges).
Singleton {
    id: root

    // "hover": the clock shows the time, and the date while the pointer is on
    // it. "always": both, all the time.
    readonly property string clockDate: adapter.clockDate
    readonly property bool clock24h: adapter.clock24h
    // The bar steps out of the way of a fullscreen window, coming back when
    // the pointer reaches the top edge.
    readonly property bool barHideFullscreen: adapter.barHideFullscreen
    // Lock once per boot, as the session starts -- greetd logs in by itself.
    readonly property bool lockAtBoot: adapter.lockAtBoot
    // The display that gets the lock screen's password field.
    readonly property string lockMonitor: adapter.lockMonitor
    // Where Settings -> About keeps the configuration's backup (a git
    // repository; see scripts/backup.py). "~" is this user's home.
    readonly property string backupRepo: adapter.backupRepo

    function set(key, value) {
        adapter[key] = value
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/shell-settings.json"
        blockLoading: true
        watchChanges: true
        atomicWrites: true

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        // No file yet: the first run. Write the defaults so there is one to
        // edit and to keep in the dotfiles.
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: adapter

            property string clockDate: "hover"
            property bool clock24h: true
            property bool barHideFullscreen: true
            property bool lockAtBoot: true
            property string lockMonitor: "DP-2"
            property string backupRepo: "~/dotfiles"
        }
    }
}
