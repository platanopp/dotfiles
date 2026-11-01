pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Dominant colour of the current track's artwork, for the spectrum ring. ColorQuantizer
// reads only local files, so remote MPRIS art is fetched to a cache file first; one
// singleton so every bar shares one download.
Singleton {
    id: root

    // Set by the media widget whenever the track changes.
    property string artUrl: ""

    readonly property color fallback: Theme.accent

    // Greys carry no identity, so a cover that quantises to one is ignored.
    readonly property real minSaturation: 0.2
    // Album art is often darker than the panel wants: lift the pick clear of
    // the glass without going neon.
    readonly property real minValue: 0.72
    readonly property real maxSaturation: 0.85

    readonly property string cacheDir:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell/album-art"

    // Local art needs no download; anything else is cached under its own hash,
    // so a new cover gets a new path.
    readonly property bool artIsLocal: root.artUrl.indexOf("file://") === 0
    readonly property string localPath: {
        if (root.artUrl.length === 0) return ""
        // A file:// art URL is percent-encoded (osu sends
        // ".../osu%21/Songs/302447%20..."), so decode it to get a real path.
        if (root.artIsLocal) return decodeURIComponent(root.artUrl.substring(7))
        return root.cacheDir + "/" + Qt.md5(root.artUrl)
    }

    // Path of an image known to be on disk, or "" while one is being fetched.
    property string readyPath: ""

    property color accent: root.fallback

    onLocalPathChanged: {
        root.readyPath = ""
        root.accent = root.fallback
        if (root.localPath.length === 0) return
        if (root.artIsLocal) {
            root.readyPath = root.localPath
            return
        }

        // Arguments set here, not bound: a binding may not have caught up with
        // localPath when the process starts.
        fetchProc.command = ["bash", "-c", root.fetchScript,
                             "bash", root.artUrl, root.localPath]
        fetchProc.running = true
    }

    // url and path arrive as arguments, never spliced into the script, so a cover URL cannot
    // become shell syntax; the empty guard stops curl writing "./.part" into the cwd. Prints
    // a path only once the file is on disk.
    readonly property string fetchScript:
        '[ -n "$1" ] && [ -n "$2" ] || exit 0;' +
        ' mkdir -p "$(dirname "$2")";' +
        ' if [ ! -s "$2" ]; then' +
        '   if curl -sfL --max-time 10 -o "$2.part" "$1"; then mv "$2.part" "$2";' +
        '   else rm -f "$2.part"; fi;' +
        ' fi;' +
        ' [ -s "$2" ] && printf %s "$2"'

    Process {
        id: fetchProc

        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim()
                // Ignore a reply for a cover we have already moved past.
                if (p.length > 0 && p === root.localPath) root.readyPath = p
            }
        }
    }

    ColorQuantizer {
        id: quantizer
        source: root.readyPath.length > 0 ? "file://" + root.readyPath : ""
        depth: 3            // 2^3 colours -- enough to find a dominant one
        rescaleSize: 64     // quantise a thumbnail, not the full cover

        onColorsChanged: root.accent = root.pickAccent(quantizer.colors)
    }

    function pickAccent(colors) {
        if (!colors || colors.length === 0) return root.fallback

        var best = null
        var bestScore = -1
        for (var i = 0; i < colors.length; i++) {
            var c = colors[i]
            if (c.hsvSaturation < root.minSaturation) continue
            // Favour colour that is both vivid and not nearly black.
            var score = c.hsvSaturation * Math.max(c.hsvValue, 0.3)
            if (score > bestScore) {
                bestScore = score
                best = c
            }
        }
        if (best === null) return root.fallback

        return Qt.hsva(best.hsvHue,
                       Math.min(best.hsvSaturation, root.maxSaturation),
                       Math.max(best.hsvValue, root.minValue),
                       1.0)
    }
}
