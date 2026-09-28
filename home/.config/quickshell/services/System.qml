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
        if (!aboutInfoProc.running) aboutInfoProc.running = true
        root.backupCmd("status")
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
}
