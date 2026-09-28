pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The Wooting keyboard lit with the wallpaper: scripts/keyboard_rgb.py lays
// the picture over the keys and stays connected to the keyboard. Settings ->
// Keyboard turns it on and off and picks brightness and profile.
Singleton {
    id: root

    // A Wooting keyboard lit with whatever wallpaper is up, the picture laid
    // over the keys (see scripts/keyboard_rgb.py). Follows wallpaperStill,
    // so a video wallpaper lights it with its poster frame.
    property var keyboardRgbStatus: ({ connected: false })
    // The colours in use: { keys: { "row,col": hex } }, for the Settings page.
    property var keyboardRgbPalette: null
    property string keyboardRgbError: ""
    // The profile the keyboard is on (0-3), -1 until known.
    property int keyboardProfileActive: -1

    readonly property string keyboardRgbScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/keyboard_rgb.py"

    // `animate`: sweep from the old colours to the new (a wallpaper change);
    // without it they switch at once (brightness, a reapply).
    function applyKeyboardRgb(animate) {
        if (!ShellSettings.keyboardRgb || Wallpaper.wallpaperStill.length === 0) return
        keyboardRgbDebounce.animate = keyboardRgbDebounce.animate || animate === true
        keyboardRgbDebounce.restart()
    }

    function resetKeyboardRgb() {
        root.keyboardRgbSend({ cmd: "reset" })
        root.keyboardRgbPalette = null
    }

    function refreshKeyboardRgb() { root.keyboardRgbSend({ cmd: "status" }) }

    // One line of JSON to the script's `serve` loop, which stays connected
    // to the keyboard: finding it costs two seconds, paid once per session
    // instead of before every change.
    function keyboardRgbSend(obj) {
        if (!keyboardRgbProc.running) keyboardRgbProc.running = true
        keyboardRgbProc.write(JSON.stringify(obj) + "\n")
    }

    // A new wallpaper, or a video's poster: the keys follow it.
    Connections {
        target: Wallpaper
        function onWallpaperStillChanged() { root.applyKeyboardRgb(ShellSettings.keyboardRgbAnimate) }
    }

    // qs ipc call keyboard apply -- say, bound to a key, after switching
    // profiles on the keyboard (a profile switch covers these colours).
    IpcHandler {
        target: "keyboard"
        function apply(): void { root.applyKeyboardRgb(false) }
        function sweep(): void { root.applyKeyboardRgb(true) }
        function reset(): void { root.resetKeyboardRgb() }
        // What was last sent, key by key ("row,col": colour) -- or the error.
        function status(): string {
            var p = root.keyboardRgbPalette
            return JSON.stringify(p ? p.keys : { error: root.keyboardRgbError })
        }
    }

    Connections {
        target: ShellSettings
        function onKeyboardRgbChanged() {
            if (ShellSettings.keyboardRgb) root.applyKeyboardRgb(ShellSettings.keyboardRgbAnimate)
            else root.resetKeyboardRgb()
        }
        function onKeyboardRgbBrightnessChanged() { root.applyKeyboardRgb(false) }
        function onKeyboardRgbProfileChanged() {
            root.keyboardRgbSend({ cmd: "target", profile: ShellSettings.keyboardRgbProfile })
        }
    }

    // A wallpaper change settles (the crop is rendered, the video's poster is
    // cut) before the keyboard follows; one write, not several.
    Timer {
        id: keyboardRgbDebounce
        property bool animate: false
        interval: 500
        onTriggered: {
            root.keyboardRgbSend({ cmd: "apply", image: Wallpaper.wallpaperStill,
                                   brightness: ShellSettings.keyboardRgbBrightness,
                                   animate: keyboardRgbDebounce.animate })
            keyboardRgbDebounce.animate = false
        }
    }

    Process {
        id: keyboardRgbProc
        running: true
        stdinEnabled: true
        command: ["python3", root.keyboardRgbScript, "serve"]
        stdout: SplitParser {
            onRead: line => {
                var d
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.cmd === "profile") {
                    root.keyboardProfileActive = d.active
                    return
                }
                // Keyboards plugged in or out: keep the list current without
                // losing the rest of the last status.
                if (d.cmd === "devices") {
                    var st = Object.assign({}, root.keyboardRgbStatus)
                    st.devices = d.devices
                    st.connected = d.devices.length > 0
                    root.keyboardRgbStatus = st
                    return
                }
                if (d.cmd === "status") {
                    root.keyboardRgbStatus = d
                    if (d.active !== null && d.active !== undefined) root.keyboardProfileActive = d.active
                    return
                }
                root.keyboardRgbError = d.ok ? "" : (d.error || "")
                if (d.cmd === "apply" && d.ok && d.keys) root.keyboardRgbPalette = { keys: d.keys }
            }
        }
        // Asked once it is up, so Settings knows whether there is a keyboard.
        onStarted: {
            keyboardRgbProc.write(JSON.stringify({ cmd: "target", profile: ShellSettings.keyboardRgbProfile }) + "\n")
            keyboardRgbProc.write(JSON.stringify({ cmd: "status" }) + "\n")
        }
    }
}
