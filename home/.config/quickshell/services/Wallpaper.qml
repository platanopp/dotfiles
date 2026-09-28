pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The wallpaper: the picture list and its thumbnails, the crop hyprpaper
// shows (scripts/wallpaper_crop.py), video wallpapers (mpvpaper, through
// scripts/video_wallpaper.py) and pausing a video where a fullscreen window
// covers it. wallpaperStill is the one picture that stands for all of it --
// what the lock screen and the keyboard's colours follow.
Singleton {
    id: root

    property var wallpaperFiles: []
    property string selectedWallpaper: ""
    // The crop hyprpaper is showing for selectedWallpaper -- the picture at
    // the framing the user chose, cut to the screen's shape. Empty until the
    // first answer arrives. See wallpaperStill.
    property string renderedWallpaper: ""

    function refreshWallpaperList() {
        wallpaperListProc.running = true
    }

    // Applying a wallpaper goes through the cropper, always.
    //
    // hyprpaper can only cover, contain or tile, and all three pick the
    // framing themselves. So the shell hands it an image already cut to the
    // screen's shape at the point the user chose, and what hyprpaper is left
    // to do is put a picture of exactly the right size on the screen.
    //
    // selectedWallpaper stays the user's own file, not the crop: it is what
    // the picker matches its "in use" ring against, and the crop is an
    // implementation detail living in a cache directory.
    readonly property string wallpaperCropScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py"

    function setWallpaper(path) {
        root.stopVideoWallpaper()
        root.selectedWallpaper = path
        // The old crop belongs to the old picture; until the new one is
        // rendered, the original is the closer answer.
        root.renderedWallpaper = ""
        // No focus given: keep whatever framing this wallpaper already has.
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path]
        wallpaperCropProc.running = true
    }

    function setWallpaperFraming(path, focusX, focusY) {
        root.stopVideoWallpaper()
        root.selectedWallpaper = path
        // The old crop belongs to the old picture; until the new one is
        // rendered, the original is the closer answer.
        root.renderedWallpaper = ""
        wallpaperCropProc.command = ["python3", root.wallpaperCropScript, "apply", path,
                                     String(focusX), String(focusY)]
        wallpaperCropProc.running = true
    }

    // Geometry of the wallpaper being framed, so the editor knows how much
    // room the crop has to move and which way. Empty until a probe lands.
    property var wallpaperCropInfo: null

    function probeWallpaperCrop(path) {
        root.wallpaperCropInfo = null
        wallpaperProbeProc.command = ["python3", root.wallpaperCropScript, "get", path]
        wallpaperProbeProc.running = true
    }

    // Which wallpaper is actually up. selectedWallpaper was only ever set by
    // setWallpaper, so across a shell restart nothing was marked as current
    // and the picker had no item to open on. hyprpaper's own config is the
    // answer: setWallpaper writes it, and it is what survives the restart.
    Process {
        id: currentWallpaperProc
        running: true
        // Asked of the cropper, not of hyprpaper: hyprpaper.conf now names a
        // rendered crop in the cache, and the picker needs the file in the
        // user's own folder that it was cut from.
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper_crop.py", "current"]
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim()
                if (path.length > 0) root.selectedWallpaper = path
            }
        }
    }

    // The crop in use, for the lock screen, read at startup the same way the
    // wallpaper itself is: nothing re-renders it just because the shell came
    // back up.
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
        // Read at startup, not only when something asks. The picker centres
        // itself on the wallpaper in use, and it cannot find it in a list
        // that is still empty -- it opened on the first file in the folder
        // and the model arriving a moment later kept it there.
        running: true
        command: ["bash", "-c", "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                var trimmed = text.trim()
                var files = trimmed.length > 0 ? trimmed.split("\n") : []
                // Assigning an equal list is not a no-op: it is a new array,
                // so every view bound to it rebuilds. The picker refreshes on
                // the way open and would have thrown away which item was
                // centred to land back on the first file in the folder.
                if (files.length === root.wallpaperFiles.length
                        && files.join("\n") === root.wallpaperFiles.join("\n"))
                    return
                root.wallpaperFiles = files
                root.buildWallpaperThumbs()
            }
        }
    }

    // ── Wallpaper thumbnails ─────────────────────────────────────────────
    //
    // The carousel keeps a dozen panels alive and each was decoding its own
    // full-size original; the 8K PNG in that folder costs ~380ms by itself,
    // and the whole folder is two seconds. Qt's sourceSize caps the output,
    // not the work, so the panels sat on their placeholder long enough to
    // read as a black gap.
    //
    // Cached JPEGs at carousel height decode 34x faster (2107ms -> 62ms for
    // the folder). Rebuilt whenever the file list changes; the script keys on
    // mtime and size, so it only does work for what actually changed.
    property var wallpaperThumbs: ({})

    function buildWallpaperThumbs() {
        wallpaperThumbsProc.running = true
    }

    // Falls back to the original: a file the script could not read still
    // shows, just slowly, rather than leaving a hole in the carousel.
    function wallpaperThumb(path) {
        return root.wallpaperThumbs[path] || path
    }

    Process {
        id: wallpaperThumbsProc
        running: false
        // nice + ionice: the pass costs a few seconds of CPU and a burst of
        // reads the first time it sees a folder, and it runs at shell startup
        // when everything else is also competing. Nothing waits on it -- the
        // carousel falls back to originals until the map arrives -- so it can
        // afford to go last.
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

    // ── Video wallpapers ─────────────────────────────────────────────────
    //
    // Played by mpvpaper, on the layer above hyprpaper's; the image wallpaper
    // stays set underneath and is what shows again when the video stops. See
    // scripts/video_wallpaper.py, which owns the process and remembers which
    // video is up across sessions.
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

    // A still of whatever the wallpaper is, for things that draw it behind
    // themselves -- the lock screen, mostly. With a video up that is its
    // poster frame: a lock surface has no business playing a video behind a
    // password field, and the image underneath would be the wrong picture.
    //
    // For an image it is the rendered crop, not the user's own file. The
    // lock covers its screen, so handed the original it cropped it again at
    // the centre -- and a wallpaper framed off-centre in the picker showed a
    // different part of itself on the lock than on the desktop.
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
        // At startup as well as on open, for the same reason as the image
        // list: the picker centres on what is in use, and it needs the list
        // and the current video to do that. It is also where the remembered
        // video comes back from, so the ring is right after a restart.
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
                // Same reason as the image list: an equal list assigned again
                // is still a new array, and it would reset the carousel.
                if (files.join("\n") !== root.videoWallpaperFiles.join("\n"))
                    root.videoWallpaperFiles = files
                root.activeVideoWallpaper = data.current || ""
            }
        }
    }

    // Brings the remembered video back when a session starts. Safe to run on
    // every shell reload: the script leaves a video that is already playing
    // alone instead of restarting it from the top.
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
        // A video just started: its monitors are fresh, none paused yet, and
        // each is to be paused if something fullscreen covers it.
        onExited: {
            root.videoPaused = ({})
            if (root.activeVideoWallpaper !== "") videoPauseStart.restart()
        }
    }

    // ── A video wallpaper, paused where it cannot be seen ────────────────
    //
    // One mpvpaper per monitor (scripts/video_wallpaper.py), each paused
    // while its monitor shows a fullscreen window -- a game has no use for a
    // video decoded behind it -- and playing on the other monitor meanwhile.
    // mpvpaper's own --auto-mode FULL paused on any fullscreen window
    // anywhere, which froze the video on the monitor in plain sight; its
    // --auto-pause alone never fires here (Hyprland keeps drawing the layer).
    // So the shell, which knows which monitor has what, says so: only when a
    // monitor's state changes, through each mpv's own socket.
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

    // Renders the crop, then points hyprpaper at what came out. Two steps
    // rather than one shell line because the second needs the first's answer.
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
