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
    // Where shell updates come from (Settings -> About -> Updates): the
    // repository the shell is published in, and its branch.
    readonly property string updateSource: adapter.updateSource
    readonly property string updateBranch: adapter.updateBranch
    // A Wooting keyboard coloured from the wallpaper (scripts/keyboard_rgb.py),
    // and how bright, 10-100.
    readonly property bool keyboardRgb: adapter.keyboardRgb
    readonly property int keyboardRgbBrightness: adapter.keyboardRgbBrightness
    // Sweep to the new colours when the wallpaper changes, or just switch.
    readonly property bool keyboardRgbAnimate: adapter.keyboardRgbAnimate
    // Which of the keyboard's profiles gets the wallpaper (0-3); -1: all.
    // The others keep the colours they were given in Wootility.
    readonly property int keyboardRgbProfile: adapter.keyboardRgbProfile

    // Screen recording (Settings -> Recording, scripts/screen_record.sh).
    // Where recordings go: "" for ~/Videos/Recordings.
    readonly property string recordFolder: adapter.recordFolder
    // The height recorded at, the width following the monitor: "native",
    // "2160", "1440", "1080" or "720".
    readonly property string recordResolution: adapter.recordResolution
    readonly property int recordFps: adapter.recordFps
    // gpu-screen-recorder's scale: "medium", "high", "very_high", "ultra".
    readonly property string recordQuality: adapter.recordQuality
    // "h264" plays everywhere; "hevc" is about half the size.
    readonly property string recordCodec: adapter.recordCodec
    // "none", "system" (what the computer plays), "mic", or "both".
    readonly property string recordAudio: adapter.recordAudio
    readonly property bool recordCursor: adapter.recordCursor

    // Sound out of every output at once (Audio.setAllOutputs).
    readonly property bool audioAllOutputs: adapter.audioAllOutputs

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
            property string updateSource: "https://github.com/platanopp/dotfiles.git"
            property string updateBranch: "main"
            property bool keyboardRgb: true
            property int keyboardRgbBrightness: 100
            property bool keyboardRgbAnimate: true
            property int keyboardRgbProfile: -1
            property string recordFolder: ""
            property string recordResolution: "1080"
            property int recordFps: 60
            property string recordQuality: "very_high"
            property string recordCodec: "h264"
            property string recordAudio: "system"
            property bool recordCursor: true
            property bool audioAllOutputs: false
        }
    }
}
