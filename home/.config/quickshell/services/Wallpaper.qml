pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The wallpaper: the picture list and thumbnails, the crop hyprpaper shows (wallpaper_crop.py),
// video wallpapers (mpvpaper via video_wallpaper.py) and pausing them under fullscreen.
// wallpaperStill is what the lock and keyboard follow.
Singleton {
    id: root

    property var wallpaperFiles: []
    property string selectedWallpaper: ""
    // The crop hyprpaper shows for selectedWallpaper, at the user's framing;
    // empty until the first answer.
    property string renderedWallpaper: ""

    function refreshWallpaperList() {
        wallpaperListProc.running = true
    }

    // Applying always goes through the cropper: hyprpaper only covers, contains or tiles, so it
    // gets an image already cut to the screen's shape. selectedWallpaper stays the user's own
    // file, which the picker matches against.
    readonly property string wallpaperCropScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py"

    function setWallpaper(path) {
        root.stopVideoWallpaper()
        root.selectedWallpaper = path
        // The old crop belongs to the old picture; until the new one
        // renders, the original is closer.
        root.renderedWallpaper = ""
        // No focus given: keep whatever framing this wallpaper already has.
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path]
        wallpaperCropProc.running = true
    }

    function setWallpaperFraming(path, focusX, focusY) {
        root.stopVideoWallpaper()
        root.selectedWallpaper = path
        // The old crop belongs to the old picture; until the new one
        // renders, the original is closer.
        root.renderedWallpaper = ""
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path,
                                     String(focusX), String(focusY)]
        wallpaperCropProc.running = true
    }

    // Geometry of the wallpaper being framed, so the editor knows how far
    // and which way the crop can move.
    property var wallpaperCropInfo: null

    function probeWallpaperCrop(path) {
        root.wallpaperCropInfo = null
        wallpaperProbeProc.command = ["python3", root.wallpaperCropScript, "get", path]
        wallpaperProbeProc.running = true
    }

    // Which wallpaper is up, read at startup so the picker has something
    // to open on after a restart.
    Process {
        id: currentWallpaperProc
        running: true
        // Asked of the cropper, not hyprpaper: hyprpaper.conf names the cached crop,
        // and the picker needs the original.
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py", "current"]
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim()
                if (path.length > 0) root.selectedWallpaper = path
            }
        }
    }

    // The crop in use, for the lock screen, read at startup: nothing
    // re-renders it on a shell restart.
    Process {
        id: renderedWallpaperProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py", "rendered"]
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim()
                if (path.length > 0) root.renderedWallpaper = path
            }
        }
    }

    Process {
        id: wallpaperListProc
        // At startup, so the picker can centre on the wallpaper in use: an empty
        // list opened it on the first file.
        running: true
        command: ["bash", "-c", "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                var trimmed = text.trim()
                var files = trimmed.length > 0 ? trimmed.split("\n") : []
                // An equal list is still a new array and rebuilds every bound view,
                // losing the picker's centred item.
                if (files.length === root.wallpaperFiles.length
                        && files.join("\n") === root.wallpaperFiles.join("\n"))
                    return
                root.wallpaperFiles = files
                root.buildWallpaperThumbs()
            }
        }
    }

    // Wallpaper thumbnails: decoding full-size originals took two seconds for the folder
    // (sourceSize caps the output, not the work). Cached JPEGs at carousel height are 34x
    // faster; the script keys on mtime and size.
    property var wallpaperThumbs: ({})

    function buildWallpaperThumbs() {
        wallpaperThumbsProc.running = true
    }

    // Falls back to the original, so an unreadable file still shows, slowly.
    function wallpaperThumb(path) {
        return root.wallpaperThumbs[path] || path
    }

    Process {
        id: wallpaperThumbsProc
        running: false
        // nice + ionice: a few seconds of CPU and reads at startup, and nothing waits on it.
        command: ["nice", "-n", "19", "ionice", "-c", "3", "python3",
                  Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_thumbs.py",
                  "build"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpaperThumbs = JSON.parse(text)
                } catch (e) {
                    root.wallpaperThumbs = ({})
                }
            }
        }
    }

    // Video wallpapers: mpvpaper on the layer above hyprpaper, whose image shows again when the
    // video stops. video_wallpaper.py owns the process and remembers the video across sessions.
    readonly property string videoWallpaperScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/video_wallpaper.py"

    // Paths, in the order the picker shows them.
    property var videoWallpaperFiles: []
    // path -> { thumb, poster }: a still at carousel height for the picker,
    // and one at full size for the lock screen.
    property var videoWallpaperFrames: ({})
    // The video playing as the wallpaper, or "" when it is an image.
    property string activeVideoWallpaper: ""

    function refreshVideoWallpapers() {
        if (!videoListProc.running) videoListProc.running = true
    }

    function videoWallpaperThumb(path) {
        var f = root.videoWallpaperFrames[path]
        return f && f.thumb ? f.thumb : ""
    }

    function setVideoWallpaper(path) {
        root.activeVideoWallpaper = path
        videoControlProc.command = ["python3", root.videoWallpaperScript, "apply", path]
        videoControlProc.running = true
    }

    function stopVideoWallpaper() {
        if (root.activeVideoWallpaper === "") return
        root.activeVideoWallpaper = ""
        videoControlProc.command = ["python3", root.videoWallpaperScript, "stop"]
        videoControlProc.running = true
    }

    // A still of whatever the wallpaper is, for things drawn over it (the lock screen): a
    // video's poster frame, or the rendered crop, since the original got cropped at the
    // centre instead of the chosen framing.
    readonly property string wallpaperStill: {
        if (root.activeVideoWallpaper !== "") {
            var f = root.videoWallpaperFrames[root.activeVideoWallpaper]
            if (f && f.poster) return f.poster
        }
        return root.renderedWallpaper !== "" ? root.renderedWallpaper
                                             : root.selectedWallpaper
    }

    Process {
        id: videoListProc
        // At startup as well as on open: the picker needs the list and the current video, and
        // the remembered video comes back here.
        running: true
        command: ["nice", "-n", "19", "python3",
                  Quickshell.env("HOME") + "/.config/quickshell/scripts/video_wallpaper.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var data
                try {
                    data = JSON.parse(text)
                } catch (e) {
                    return
                }
                var files = [], frames = {}
                for (var i = 0; i < data.videos.length; i++) {
                    var v = data.videos[i]
                    files.push(v.path)
                    frames[v.path] = { thumb: v.thumb, poster: v.poster }
                }
                root.videoWallpaperFrames = frames
                // An equal list assigned again is still a new array, and would reset the carousel.
                if (files.join("\n") !== root.videoWallpaperFiles.join("\n"))
                    root.videoWallpaperFiles = files
                root.activeVideoWallpaper = data.current || ""
            }
        }
    }

    // Brings the remembered video back; safe on every reload, as the script
    // leaves a playing video alone.
    Process {
        id: videoRestoreProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/video_wallpaper.py",
                  "restore"]
        // And paused where something fullscreen covers it (see syncVideoPause).
        onExited: {
            root.videoPaused = ({})
            videoPauseStart.restart()
        }
    }

    Process {
        id: videoControlProc
        running: false
        // A video just started: none of its monitors are paused yet, so check each for fullscreen.
        onExited: {
            root.videoPaused = ({})
            if (root.activeVideoWallpaper !== "") videoPauseStart.restart()
        }
    }

    // A video wallpaper, paused where it can't be seen: one mpvpaper per monitor, paused
    // while that monitor shows a fullscreen window. mpvpaper's --auto-mode FULL froze every
    // monitor and --auto-pause never fires here, so the shell tells each mpv through its
    // socket when its monitor's state changes.
    property var videoPaused: ({})

    function syncVideoPause() {
        if (root.activeVideoWallpaper === "") return
        videoPauseRefresh.restart()
    }

    Timer {
        id: videoPauseStart
        // The sockets appear a moment after mpvpaper starts.
        interval: 1500
        onTriggered: root.syncVideoPause()
    }

    Timer {
        id: videoPauseRefresh
        interval: 200
        onTriggered: {
            Hyprland.refreshWorkspaces()
            Hyprland.refreshMonitors()
            videoPauseApply.restart()
        }
    }

    Timer {
        id: videoPauseApply
        interval: 200
        onTriggered: {
            if (root.activeVideoWallpaper === "") return
            var next = Object.assign({}, root.videoPaused)
            var ms = Hyprland.monitors.values
            for (var i = 0; i < ms.length; i++) {
                var ws = ms[i].activeWorkspace
                var full = !!(ws && ws.lastIpcObject && ws.lastIpcObject.hasfullscreen)
                if (next[ms[i].name] === full) continue
                next[ms[i].name] = full
                Quickshell.execDetached(["python3", root.videoWallpaperScript, "pause",
                                         ms[i].name, full ? "on" : "off"])
            }
            root.videoPaused = next
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "fullscreen": case "workspacev2": case "focusedmonv2": case "activespecial":
            case "openwindow": case "closewindow": case "movewindowv2":
                root.syncVideoPause()
            }
        }
    }

    Process {
        id: wallpaperSetProc
        running: false
    }

    Process {
        id: wallpaperProbeProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpaperCropInfo = JSON.parse(text)
                } catch (e) {
                    root.wallpaperCropInfo = null
                }
            }
        }
    }

    // Renders the crop, then points hyprpaper at the result: two steps, since the
    // second needs the first's answer.
    Process {
        id: wallpaperCropProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var rendered = ""
                try {
                    rendered = JSON.parse(text).rendered || ""
                } catch (e) {
                    rendered = ""
                }
                if (rendered.length === 0) return
                root.renderedWallpaper = rendered
                wallpaperSetProc.command = ["bash", "-c", "P=\"$1\"; hyprctl hyprpaper preload \"$P\" >/dev/null 2>&1; hyprctl hyprpaper wallpaper \",$P,cover\"; printf 'splash = false\\nwallpaper {\\n    monitor =\\n    path = %s\\n    fit_mode = cover\\n}\\n' \"$P\" > \"$HOME/.config/hypr/hyprpaper.conf\"", "_", rendered]
                wallpaperSetProc.running = true
            }
        }
    }
}
