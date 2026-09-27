import QtQuick
import QtQuick.Layouts

// Settings -> About: what this machine is, and how current its backup is.
// The backup is ~/dotfiles, a copy of the live configuration that only
// changes when it is synced and committed; the rows here do exactly that.
// Pushing publishes it -- the repo is public -- so that button asks twice.
Column {
    id: page
    spacing: 24

    readonly property var info: AppState.aboutInfo
    readonly property var backup: AppState.backupStatus

    Component.onCompleted: AppState.refreshAbout()

    // ── The machine, as a card of its own ────────────────────────────────
    Rectangle {
        width: parent.width
        height: 118
        radius: 22
        color: Theme.surfaceContainer

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18

            Rectangle {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 78
                radius: 24
                color: Theme.accent

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F385}"
                    size: Theme.iconHero + 10
                    color: Theme.accentText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    text: page.info.host || "…"
                    color: Theme.textPrimary
                    font.pixelSize: 20
                    font.bold: true
                    font.family: Theme.fontMono
                }

                Text {
                    Layout.fillWidth: true
                    text: (page.info.os || "") + (page.info.kernel ? "  ·  " + page.info.kernel : "")
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: page.info.uptime ? "up " + page.info.uptime : ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Hardware"

        Repeater {
            model: [
                { icon: "\u{F0EE0}", title: "Processor", key: "cpu" },
                { icon: "\u{F08AE}", title: "Graphics", key: "gpu" },
                { icon: "\u{F035B}", title: "Memory", key: "memory" }
            ]

            SettingsRow {
                id: hw
                required property var modelData
                icon: hw.modelData.icon
                title: hw.modelData.title

                Text {
                    text: page.info[hw.modelData.key] || "…"
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Software"

        Repeater {
            model: [
                { icon: "\u{F05B2}", title: "Hyprland", key: "hyprland" },
                { icon: "\u{F0A1D}", title: "Quickshell", key: "quickshell" }
            ]

            SettingsRow {
                id: sw
                required property var modelData
                icon: sw.modelData.icon
                title: sw.modelData.title

                Text {
                    text: (page.info[sw.modelData.key] || "…").split(" ")[0]
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }
            }
        }
    }

    // ── Backup ───────────────────────────────────────────────────────────
    //
    // For whoever is logged in: their configuration, copied into a git
    // repository (see scripts/backup.py). No repository yet, and the page
    // offers to make one; no remote, and it offers a private GitHub one when
    // gh is logged in; a remote, and it can push -- asking twice, and saying
    // so plainly when the repository is public.
    SettingsGroup {
        width: parent.width
        title: "Backup"

        // No repository yet.
        SettingsRow {
            visible: page.backup.repo !== true
            icon: "\u{F006F}"
            title: "No backup yet"
            description: "Keeps a copy of this desktop's configuration in " + (page.backup.display || "~/dotfiles")

            PillButton {
                text: AppState.backupBusy ? "…" : "Create"
                emphasis: true
                available: !AppState.backupBusy
                onClicked: AppState.backupCmd("init")
            }
        }

        SettingsRow {
            visible: page.backup.repo === true
            icon: "\u{F024B}"
            title: "Saved in"
            description: page.backup.hash ? "Last: " + page.backup.hash + (page.backup.when ? " · " + page.backup.when : "") : ""

            Text {
                text: page.backup.display || ""
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.fontMono
            }
        }

        SettingsRow {
            visible: page.backup.repo === true
            icon: "\u{F006F}"
            title: page.backup.pending > 0
                ? page.backup.pending + (page.backup.pending === 1 ? " change not saved" : " changes not saved")
                : "Everything is saved"

            PillButton {
                text: AppState.backupBusy ? "…" : "Back up now"
                emphasis: page.backup.pending > 0
                available: page.backup.pending > 0 && !AppState.backupBusy
                onClicked: AppState.backupCmd("backup")
            }
        }

        // A repository with nowhere to go: offer GitHub, private, when gh can.
        SettingsRow {
            id: githubRow
            visible: page.backup.repo === true && !page.backup.remote
            icon: "\u{F02A4}"
            title: "Local only"
            description: page.backup.gh
                ? (githubRow.armed ? "Creates a private repository on your GitHub -- press again"
                                   : "Not copied anywhere else yet")
                : "Log in with gh auth login to add GitHub"

            property bool armed: false

            Timer {
                id: disarmGithub
                interval: 5000
                onTriggered: githubRow.armed = false
            }

            PillButton {
                visible: page.backup.gh === true
                text: githubRow.armed ? "Create it" : "Add to GitHub"
                emphasis: githubRow.armed
                available: !AppState.backupBusy
                onClicked: {
                    if (!githubRow.armed) {
                        githubRow.armed = true
                        disarmGithub.restart()
                        return
                    }
                    githubRow.armed = false
                    AppState.backupCmd("github")
                }
            }
        }

        // A remote: push, asking twice.
        SettingsRow {
            id: pushRow
            visible: page.backup.repo === true && !!page.backup.remote
            icon: "\u{F0B7E}"
            title: page.backup.unpushed > 0
                ? page.backup.unpushed + (page.backup.unpushed === 1 ? " commit to upload" : " commits to upload")
                : "Uploaded"
            description: pushRow.armed
                ? (page.backup.visibility === "public" ? "This repository is public -- press again to publish"
                                                       : "Press again to upload")
                : (page.backup.remote || "").replace(/^https:\/\//, "").replace(/\.git$/, "")
                  + (page.backup.visibility ? " · " + page.backup.visibility : "")

            property bool armed: false

            Timer {
                id: disarmPush
                interval: 5000
                onTriggered: pushRow.armed = false
            }

            PillButton {
                text: pushRow.armed ? (page.backup.visibility === "public" ? "Publish" : "Upload") : "Push"
                danger: pushRow.armed && page.backup.visibility === "public"
                emphasis: pushRow.armed && page.backup.visibility !== "public"
                available: page.backup.unpushed > 0 && !AppState.backupBusy
                onClicked: {
                    if (!pushRow.armed) {
                        pushRow.armed = true
                        disarmPush.restart()
                        return
                    }
                    pushRow.armed = false
                    AppState.backupCmd("push")
                }
            }
        }
    }

    // What the last action did.
    Text {
        width: parent.width
        visible: AppState.backupLast !== null
        text: {
            var l = AppState.backupLast
            if (!l) return ""
            var verb = { init: "create the backup", backup: "back up", push: "push", github: "add GitHub" }[l.action] || l.action
            if (!l.ok) return "Could not " + verb + ": " + l.error
            if (l.action === "push") return "Uploaded"
            if (l.action === "github") return "Added to GitHub, private, and uploaded"
            if (l.action === "init") return "Backup created in " + (page.backup.display || "")
            return l.committed ? "Saved as " + (page.backup.hash || "") : "Nothing to save"
        }
        color: AppState.backupLast && !AppState.backupLast.ok ? Theme.error : Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontMono
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
}
