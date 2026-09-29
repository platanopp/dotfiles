pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Screen recording with gpu-screen-recorder: the control panel's Record
// tile, the count and the timer on the control pill, Super+Shift+R and
// `qs ipc call record`. Settings -> Recording picks how it records.
Singleton {
    id: root

    // One monitor at a time, as Settings -> Recording says (by default 1080p
    // 60 fps H.264 MP4 with the computer's sound), encoded on the GPU
    // (scripts/screen_record.sh). Started and stopped from the control
    // panel's Record tile, the red dot the control
    // pill shows while it runs, Super+Shift+R, or `qs ipc call record ...`.
    // Stopped with SIGINT, which is what makes the recorder finish the file.
    readonly property bool recording: recordProc.running
    property string recordingFile: ""
    property string recordingMonitor: ""
    property real recordingSince: 0
    property int recordingSeconds: 0

    function startRecording(monitor) {
        if (recordProc.running) return
        root.recordingFile = ""
        root.recordingMonitor = monitor || Panels.focusedScreenName()
        recordProc.command = [Quickshell.env("HOME") + "/.config/quickshell/scripts/screen_record.sh",
                              "--monitor", root.recordingMonitor,
                              "--height", ShellSettings.recordResolution,
                              "--fps", String(ShellSettings.recordFps),
                              "--quality", ShellSettings.recordQuality,
                              "--codec", ShellSettings.recordCodec,
                              "--audio", ShellSettings.recordAudio,
                              "--cursor", ShellSettings.recordCursor ? "yes" : "no",
                              "--dir", ShellSettings.recordFolder]
        root.recordingSince = Date.now()
        root.recordingSeconds = 0
        recordProc.running = true
    }

    // Where recordings are going, for the Settings page.
    readonly property string recordingFolder: ShellSettings.recordFolder.length > 0
        ? ShellSettings.recordFolder
        : Quickshell.env("HOME") + "/Videos/Recordings"

    // A folder picked in a dialog (zenity); cancelling it changes nothing.
    function chooseRecordingFolder() {
        if (folderPickProc.running) return
        folderPickProc.running = true
    }

    Process {
        id: folderPickProc
        running: false
        command: ["zenity", "--file-selection", "--directory", "--title=Where recordings are saved",
                  "--filename=" + root.recordingFolder + "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = text.trim()
                if (d.length > 0) ShellSettings.set("recordFolder", d)
            }
        }
    }

    function stopRecording() {
        if (recordProc.running) recordProc.signal(2)
    }

    // Record, with a count of three first, shown on the control pill where
    // the recording's time then runs -- nothing over the screen, so the
    // three seconds are there to get to what is to be recorded. Pressing
    // record again during the count, or the pill, calls it off. Stop, if
    // recording already.
    function toggleRecording(monitor) {
        if (recordProc.running) root.stopRecording()
        else if (root.recordCountdown > 0) root.cancelRecordingCountdown()
        else root.countdownRecording(monitor)
    }

    // 3, 2, 1 while counting; 0 otherwise.
    property int recordCountdown: 0
    property string recordCountdownMonitor: ""

    function countdownRecording(monitor) {
        if (recordProc.running || root.recordCountdown > 0) return
        root.recordCountdownMonitor = monitor || Panels.focusedScreenName()
        root.recordCountdown = 3
        countdownTick.restart()
    }

    function cancelRecordingCountdown() {
        countdownTick.stop()
        root.recordCountdown = 0
    }

    Timer {
        id: countdownTick
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.recordCountdown > 1) {
                root.recordCountdown -= 1
                return
            }
            countdownTick.stop()
            root.recordCountdown = 0
            root.startRecording(root.recordCountdownMonitor)
        }
    }

    // "4:07", or "1:02:33" past the hour.
    function recordingClock(sec) {
        var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
        var ss = (s < 10 ? "0" : "") + s
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
    }

    Process {
        id: recordProc
        running: false
        stdout: SplitParser {
            // The script's first line is the file it records to.
            onRead: line => { if (root.recordingFile === "") root.recordingFile = line.trim() }
        }
        stderr: StdioCollector { id: recordErr }
        onExited: (code, status) => {
            var file = root.recordingFile
            var short = file.replace(Quickshell.env("HOME"), "~")
            if (file.length > 0 && root.recordingSeconds >= 1) {
                // Saved: said so, with a button that opens it.
                Quickshell.execDetached(["bash", "-c",
                    'a=$(notify-send -a "Screen recorder" -i video-x-generic -A open=Open "Recording saved" "$2"); '
                    + '[ "$a" = open ] && xdg-open "$1"', "_", file, short])
            } else {
                var why = recordErr.text.trim().split("\n").pop()
                Quickshell.execDetached(["notify-send", "-a", "Screen recorder", "-i", "dialog-error",
                                         "Recording failed", why.length > 0 ? why : "The recorder stopped at once."])
            }
            root.recordingSince = 0
        }
    }

    // The clock the tile and the pill show; only runs while recording.
    Timer {
        interval: 1000
        repeat: true
        running: recordProc.running
        onTriggered: root.recordingSeconds = Math.floor((Date.now() - root.recordingSince) / 1000)
    }

    IpcHandler {
        target: "record"
        function toggle(): void { root.toggleRecording("") }
        // With the count first, as the tile and the shortcut do.
        function start(): void { root.countdownRecording("") }
        function stop(): void { root.stopRecording() }
        function status(): string { return recordProc.running ? "recording " + root.recordingFile : "idle" }
    }
}
