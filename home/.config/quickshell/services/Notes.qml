pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Service managing fast notes / sticky notes synced with Obsidian markdown files.
Singleton {
    id: root

    property var entries: []
    property int total: 0
    property string vaultName: ""
    property string noteName: ""
    property string notePath: ""
    property string error: ""
    property bool loading: false

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/quickshell/scripts/obsidian_notes.py"

    function parseState(text) {
        root.loading = false
        try {
            var parsed = JSON.parse(text)
            if (parsed.error) {
                root.error = parsed.error
                root.entries = []
                root.total = 0
                return
            }
            root.error = ""
            root.entries = parsed.entries || []
            root.total = parsed.total || 0
            root.vaultName = parsed.vaultName || ""
            root.noteName = parsed.note || ""
            root.notePath = parsed.path || ""
        } catch (e) {
            root.error = "Error al leer notas"
        }
    }

    function refresh() {
        if (!readProc.running) {
            root.loading = true
            readProc.running = true
        }
    }

    // Pending first, then the done ones; newest first within each.
    readonly property var ordered: root.entries.filter(e => !e.checked).concat(root.entries.filter(e => e.checked))
    readonly property int done: root.entries.filter(e => e.checked).length
    readonly property int pending: root.total - root.done

    // One script call at a time, in order; the rest wait here.
    property var opQueue: []

    function run(args) {
        if (actionProc.running) {
            root.opQueue = root.opQueue.concat([args])
            return
        }
        root.loading = true
        actionProc.command = ["python3", root.scriptPath].concat(args)
        actionProc.running = true
    }

    function add(text) {
        var trimmed = text.trim()
        if (trimmed.length > 0) root.run(["--add", trimmed])
    }

    function remove(id) {
        if (id) root.run(["--delete", id])
    }

    // Flipped here at once, so the box answers the click; the script's
    // reply (the file as written) replaces it a moment later.
    function toggle(id) {
        if (!id) return
        root.entries = root.entries.map(e => e.id === id ? Object.assign({}, e, { checked: !e.checked }) : e)
        root.run(["--toggle", id])
    }

    function edit(id, text) {
        var t = text.trim()
        if (!id || t.length === 0) return
        root.entries = root.entries.map(e => e.id === id ? Object.assign({}, e, { text: t }) : e)
        root.run(["--edit", id, t])
    }

    function clearDone() {
        if (root.done > 0) root.run(["--clear-done"])
    }

    function drainQueue() {
        if (root.opQueue.length === 0 || actionProc.running) return
        var next = root.opQueue[0]
        root.opQueue = root.opQueue.slice(1)
        root.run(next)
    }

    // Reminders, written in the note:
    //   @18:30          every day at that time, until the note is ticked
    //   @6/11 10:00     on 6 Nov: two days before, the day before and on the
    //   @6/11/2027      day, at that time (09:00 when none is given)
    // Without a year it is the nearest 6 Nov, so one written in December for
    // January lands next year. Checked on the minute: a time that passed while
    // the shell was off is not caught up on.
    readonly property var reminderRe: /@(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?(?:\s+\d{1,2}:\d{2})?|\d{1,2}:\d{2})(?![\d\/:])/
    readonly property var monthNames: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

    function pad(n) { return (n < 10 ? "0" : "") + n }

    // { token, hm, due } with due a Date at midnight, or null for a daily one;
    // null when the note has none (or a date that does not exist).
    function reminderOf(text) {
        var m = root.reminderRe.exec(text || "")
        if (!m) return null
        var tm = /(\d{1,2}):(\d{2})$/.exec(m[1])
        if (tm && (+tm[1] > 23 || +tm[2] > 59)) return null
        var hm = tm ? root.pad(+tm[1]) + ":" + tm[2] : "09:00"
        var dm = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?/.exec(m[1])
        if (!dm) return { token: m[0], hm: hm, due: null }
        var day = +dm[1], month = +dm[2] - 1
        var today = new Date(); today.setHours(0, 0, 0, 0)
        var year = dm[3] ? (dm[3].length === 2 ? 2000 + +dm[3] : +dm[3]) : today.getFullYear()
        var due = new Date(year, month, day)
        if (!dm[3]) {
            var next = new Date(year + 1, month, day)
            if (Math.abs(next - today) < Math.abs(due - today)) due = next
        }
        if (due.getMonth() !== month || due.getDate() !== day) return null
        return { token: m[0], hm: hm, due: due, timed: !!tm }
    }

    function daysUntil(due) {
        var today = new Date(); today.setHours(0, 0, 0, 0)
        return Math.round((due - today) / 86400000)
    }

    // What the widget shows in place of the token.
    function reminderLabel(r) {
        if (!r.due) return r.hm
        var d = r.due.getDate() + " " + root.monthNames[r.due.getMonth()]
        return r.timed ? d + " · " + r.hm : d
    }

    function reminderOverdue(r) {
        return !!r && !!r.due && root.daysUntil(r.due) < 0
    }

    property string lastMinute: ""

    function checkReminders() {
        var hm = Qt.formatTime(new Date(), "hh:mm")
        if (hm === root.lastMinute) return
        root.lastMinute = hm
        root.entries.forEach(function (e) {
            var r = e.checked ? null : root.reminderOf(e.text)
            if (!r || r.hm !== hm) return
            var left = r.due ? root.daysUntil(r.due) : 0
            if (left < 0 || left > 2) return
            var when = r.due ? root.reminderLabel(r) : hm
            var title = left === 2 ? "En 2 días · " + when
                      : left === 1 ? "Mañana · " + when
                      : "Hoy · " + hm
            var body = e.text.replace(r.token, "").replace(/\s{2,}/g, " ").trim()
            Quickshell.execDetached(["notify-send", "-a", "Fast Notes", "-u", left === 0 ? "critical" : "normal",
                                     "-i", "obsidian", title, body])
        })
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.checkReminders()
    }

    function openObsidian() {
        openProc.command = ["python3", root.scriptPath, "--open"]
        openProc.running = true
    }

    Process {
        id: readProc
        running: true
        command: ["python3", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: root.parseState(text)
        }
    }

    Process {
        id: actionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseState(text)
        }
        onRunningChanged: if (!running) root.drainQueue()
    }

    Process {
        id: openProc
        running: false
    }

    FileView {
        path: root.notePath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: debounce.restart()
    }

    Timer {
        id: debounce
        interval: 350
        onTriggered: root.refresh()
    }
}
