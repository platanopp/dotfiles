pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Who is logged in: the user name and the avatar -- the control panel's
// header, the lock screen, Settings -> Profile.
Singleton {
    id: root

    // From the environment at once; whoami below only confirms it. It used to
    // start empty, and the clock's panel showed a hard-coded name meanwhile.
    property string username: Quickshell.env("USER") || ""

    // The logged-in user's picture, from where Linux keeps one: ~/.face (what
    // display managers read), ~/.face.icon, or AccountsService's copy. Empty
    // when there is none, and the control panel shows the initial instead.
    property string avatarPath: ""
    // Bumped on every change: the file keeps its name, so an Image showing it
    // must be told to read it again (see avatarSource).
    property int avatarVersion: 0

    // For Images: cleared for one frame on a change, so a picture shown with
    // cache: false reloads rather than keeping the old one.
    readonly property string avatarSource: root.avatarPath.length > 0 && root.avatarVersion >= 0
        ? "file://" + root.avatarPath : ""

    property string avatarError: ""
    property bool avatarBusy: false

    // Framing: zoom (1: the largest square the picture holds) and the
    // square's centre as fractions of the picture (see scripts/avatar.py).
    function setAvatar(path, zoom, x, y) {
        root.avatarCmd(zoom === undefined ? ["set", path]
                                          : ["set", path, String(zoom), String(x), String(y)])
    }

    // Frame the picture ~/.face was cut from again.
    function adjustAvatar(zoom, x, y) { root.avatarCmd(["adjust", String(zoom), String(x), String(y)]) }
    function removeAvatar() { root.avatarCmd(["remove"]) }

    // The picture to frame and the framing in use: { path, zoom, x, y }.
    property var avatarFraming: ({ path: "" })
    function refreshAvatarFraming() { if (!avatarFramingProc.running) avatarFramingProc.running = true }

    Process {
        id: avatarFramingProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/avatar.py", "source"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.avatarFraming = JSON.parse(text) } catch (e) {}
            }
        }
    }

    function avatarCmd(args) {
        if (avatarSetProc.running) return
        root.avatarBusy = true
        root.avatarError = ""
        avatarSetProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/avatar.py"].concat(args)
        avatarSetProc.running = true
    }

    Process {
        id: avatarSetProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.avatarBusy = false
                var d
                try { d = JSON.parse(text) } catch (e) { root.avatarError = "Could not change the picture"; return }
                if (!d.ok) { root.avatarError = d.error || "Could not change the picture"; return }
                root.avatarPath = ""
                root.avatarVersion++
                avatarProc.running = true
                root.refreshAvatarFraming()
            }
        }
    }

    Process {
        id: avatarProc
        running: true
        command: ["sh", "-c", "for f in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [ -s \"$f\" ] && { printf '%s' \"$f\"; exit 0; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root.avatarPath = text.trim()
        }
    }

    Process {
        id: whoamiProc
        command: ["whoami"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.username = text.trim()
        }
    }
}
