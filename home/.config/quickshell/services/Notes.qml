pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The notes pill's quick capture into an Obsidian note: what the note holds,
// adding to it, opening it in Obsidian.
Singleton {
    id: root

    // Straight at the vault's Markdown, not at Obsidian. Its only API is a
    // community plugin that answers while the app is running, which is the
    // wrong half of the time for a box you hit on the way past -- and the
    // vault is plain files anyway. See scripts/obsidian_capture.py.
    property var obsidianEntries: []
    property int obsidianTotal: 0
    property string obsidianVaultName: ""
    property string obsidianNote: ""
    property string obsidianPath: ""
    property string obsidianError: ""

    readonly property string obsidianScript:
        Quickshell.env("HOME") + "/.config/quickshell/scripts/obsidian_capture.py"

    // Both the read and the write print the note's new state, so they land
    // here and the list never has to be re-fetched after an entry is added.
    function applyObsidianState(text) {
        try {
            var parsed = JSON.parse(text)
            if (parsed.error) {
                root.obsidianError = parsed.error
                root.obsidianEntries = []
                root.obsidianTotal = 0
                return
            }
            root.obsidianError = ""
            root.obsidianEntries = parsed.entries || []
            root.obsidianTotal = parsed.total || 0
            root.obsidianVaultName = parsed.vaultName || ""
            root.obsidianNote = parsed.note || ""
            root.obsidianPath = parsed.path || ""
        } catch (e) {
            root.obsidianError = "Could not read the note"
            root.obsidianEntries = []
            root.obsidianTotal = 0
        }
    }

    function refreshObsidianNotes() {
        if (!obsidianReadProc.running) obsidianReadProc.running = true
    }

    // Notes typed while a save is still in flight wait their turn rather
    // than being dropped: typing faster than the disk is not a reason to
    // lose what someone wrote.
    property var obsidianQueue: []

    function addObsidianNote(text) {
        var trimmed = text.trim()
        if (trimmed.length === 0) return

        if (obsidianAddProc.running) {
            var queued = root.obsidianQueue.slice()
            queued.push(trimmed)
            root.obsidianQueue = queued
            return
        }

        // Argument vector, never a shell line: whatever gets typed in the
        // box is a note, not something to be parsed for quotes.
        obsidianAddProc.command = ["python3", root.obsidianScript, "--add", trimmed]
        obsidianAddProc.running = true
    }

    function drainObsidianQueue() {
        if (root.obsidianQueue.length === 0 || obsidianAddProc.running) return
        var queued = root.obsidianQueue.slice()
        var next = queued.shift()
        root.obsidianQueue = queued
        obsidianAddProc.command = ["python3", root.obsidianScript, "--add", next]
        obsidianAddProc.running = true
    }

    function openObsidianNote() {
        if (root.obsidianVaultName.length === 0) return
        var file = root.obsidianNote.replace(/\.md$/, "")
        obsidianOpenProc.command = ["xdg-open",
            "obsidian://open?vault=" + encodeURIComponent(root.obsidianVaultName)
            + "&file=" + encodeURIComponent(file)]
        obsidianOpenProc.running = true
    }

    Process {
        id: obsidianReadProc
        running: true
        command: ["python3", root.obsidianScript]
        stdout: StdioCollector {
            onStreamFinished: root.applyObsidianState(text)
        }
    }

    Process {
        id: obsidianAddProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyObsidianState(text)
        }
        onRunningChanged: if (!running) root.drainObsidianQueue()
    }

    Process {
        id: obsidianOpenProc
        running: false
    }

    // Obsidian and LiveSync write this note too, so the widget follows the
    // file rather than trusting its own last write to still be the latest.
    // The path comes from the script, which resolves the vault out of
    // Obsidian's registry -- so a vault moved from inside the app is picked
    // up here without the shell knowing where it went.
    FileView {
        path: root.obsidianPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: obsidianDebounce.restart()
    }

    Timer {
        id: obsidianDebounce
        interval: 400
        onTriggered: root.refreshObsidianNotes()
    }
}
