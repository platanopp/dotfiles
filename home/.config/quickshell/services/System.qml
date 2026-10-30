pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// This machine, for Settings -> About: the distribution, the details
// scripts/about.py gathers, and the backup of the configuration.
Singleton {
    id: root

    property string distro: ""

    Process {
        id: sysInfoProc
        running: true
        command: ["sh", "-c", ". /etc/os-release 2>/dev/null && printf '%s' \"$PRETTY_NAME\""]
        stdout: StdioCollector {
            onStreamFinished: root.distro = text.trim()
        }
    }

    // ── About: the machine, and its backup ───────────────────────────────
    //
    // scripts/about.py for the facts about this machine; scripts/backup.py
    // for the backup of its configuration, in whatever repository Settings ->
    // Shell's backupRepo names (~/dotfiles unless changed) -- made on request
    // if this user has none yet.
    property var aboutInfo: ({})
    property var backupStatus: ({ repo: false })
    property bool backupBusy: false
    // The last action: { action, ok, error?, committed?, at }
    property var backupLast: null

    function refreshAbout() {
        root.refreshInfo()
        root.backupCmd("status")
        root.updateCmd("status")
    }

    // The facts alone, for the desktop's machine card: refreshAbout's backup
    // status also syncs the dotfiles, which a widget has no business doing.
    function refreshInfo() {
        if (!aboutInfoProc.running) aboutInfoProc.running = true
    }

    // status | init | backup | push | github
    function backupCmd(action) {
        if (backupProc.running) return
        root.backupBusy = action !== "status"
        backupProc.action = action
        backupProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/backup.py",
                              action, ShellSettings.backupRepo]
        backupProc.running = true
    }

    Process {
        id: aboutInfoProc
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/about.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.aboutInfo = JSON.parse(text) } catch (e) {}
            }
        }
    }

    Process {
        id: backupProc
        property string action: "status"
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try { d = JSON.parse(text) } catch (e) { return }
                if (backupProc.action === "status") {
                    root.backupStatus = d
                    return
                }
                if (d.status) root.backupStatus = d.status
                root.backupLast = { action: backupProc.action, ok: d.ok, error: d.error || "",
                                    committed: d.committed !== false, at: Date.now() }
            }
        }
        onExited: root.backupBusy = false
    }

    // ── Updates: the shell, from where it is published ───────────────────
    //
    // scripts/shell_update.py compares ~/.config/quickshell with the latest
    // published version (ShellSettings.updateSource) and, asked to, replaces
    // it -- the shell only, keeping this user's settings and widget layout,
    // with a copy of what was there. After an update the shell restarts:
    // reloading file by file leaves widgets loaded by URL on their old code.
    property var updateStatus: ({ state: "unknown" })
    property bool updateChecking: false
    property bool updateBusy: false
    // The last update: { ok, error?, files?, saved? }
    property var updateLast: null

    // status | update
    function updateCmd(action) {
        if (updateProc.running) return
        root.updateChecking = action === "status"
        root.updateBusy = action === "update"
        updateProc.action = action
        updateProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/shell_update.py",
                              action, ShellSettings.updateSource, ShellSettings.updateBranch,
                              ShellSettings.backupRepo]
        updateProc.running = true
    }

    Process {
        id: updateProc
        property string action: "status"
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try { d = JSON.parse(text) } catch (e) { return }
                if (updateProc.action === "status") {
                    root.updateStatus = d
                    return
                }
                root.updateLast = d
                if (d.ok && d.files > 0) restartProc.running = true
                else if (d.ok) root.updateStatus = Object.assign({}, root.updateStatus, { state: "current" })
            }
        }
        onExited: {
            root.updateChecking = false
            root.updateBusy = false
        }
    }

    Process {
        id: restartProc
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/shell_update.py", "restart"]
    }
}
