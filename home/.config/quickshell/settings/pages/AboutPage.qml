import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> About: the machine, whether its shell is the latest published one, and the backup
// (~/dotfiles, synced and committed from here). The repo is public, so pushing asks twice.
Column {
    id: page
    spacing: 24

    readonly property var info: System.aboutInfo
    readonly property var backup: System.backupStatus
    readonly property var update: System.updateStatus

    Component.onCompleted: System.refreshAbout()

    // The machine, as a card of its own
    Rectangle {
        width: parent.width
        height: 118
        radius: Theme.radiusXLarge
        color: Theme.surfaceContainer

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18

            Rectangle {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 78
                radius: Theme.radiusXLarge
                color: Theme.surfaceContainerHigh

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F385}"
                    size: Theme.iconHero + 10
                    color: Theme.textPrimary
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
                    font.family: Theme.fontDisplay
                }

                Text {
                    Layout.fillWidth: true
                    text: (page.info.os || "") + (page.info.kernel ? "  ·  " + page.info.kernel : "")
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: page.info.uptime ? "up " + page.info.uptime : ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
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
                    font.family: Theme.fontText
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
                    font.family: Theme.fontText
                }
            }
        }
    }

    // Updates: the shell against its latest published version (shell_update.py), checked on
    // open; the update asks twice since it restarts the shell. The publisher's own copy
    // reads as newer and goes out from Backup.
    SettingsGroup {
        width: parent.width
        title: "Updates"

        SettingsRow {
            id: updateRow
            icon: "\u{F06B0}"
            title: {
                var u = page.update
                if (System.updateBusy) return "Updating…"
                if (u.state === "current") return "Up to date"
                if (u.state === "behind") return "An update is available"
                if (u.state === "ahead") return "You publish this shell"
                if (u.state === "error") return "Could not check for updates"
                return "Checking for updates…"
            }
            description: {
                var u = page.update
                var version = u.head ? u.head + (u.when ? " · " + u.when : "") : ""
                if (u.state === "behind")
                    return updateRow.armed
                        ? "Replaces the shell and restarts it; your settings and widgets stay. Press again"
                        : version + " · " + u.files + (u.files === 1 ? " file changes" : " files change")
                if (u.state === "ahead")
                    return "Yours is newer than " + u.source + "; it goes out from Backup"
                if (u.state === "error") return u.error || ""
                return version.length > 0 ? "Version " + version + " from " + u.source : ""
            }

            property bool armed: false

            Timer {
                id: disarmUpdate
                interval: 5000
                onTriggered: updateRow.armed = false
            }

            PillButton {
                readonly property bool behind: page.update.state === "behind"
                text: System.updateBusy || System.updateChecking ? "…"
                    : !behind ? "Check"
                    : updateRow.armed ? "Update now" : "Update"
                emphasis: behind
                available: !System.updateBusy && !System.updateChecking
                onClicked: {
                    if (!behind) {
                        System.updateCmd("status")
                        return
                    }
                    if (!updateRow.armed) {
                        updateRow.armed = true
                        disarmUpdate.restart()
                        return
                    }
                    updateRow.armed = false
                    System.updateCmd("update")
                }
            }
        }

        // What the update brings: the published commits that touched the shell
        // since this version, newest first.
        SettingsRow {
            visible: page.update.state === "behind" && (page.update.commits || []).length > 0
            icon: "\u{F02DA}"
            title: "What changes"
            stacked: true

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: page.update.commits || []

                    RowLayout {
                        required property var modelData
                        width: parent.width
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            text: modelData.subject
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.when
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontText
                        }
                    }
                }

                Text {
                    visible: (page.update.more || 0) > 0
                    text: "and " + page.update.more + " more"
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontText
                }
            }
        }
    }

    // What the last update did when it did not restart the shell: a failure, or nothing to change.
    Text {
        width: parent.width
        visible: System.updateLast !== null && !(System.updateLast.ok && System.updateLast.files > 0)
        text: {
            var l = System.updateLast
            if (!l) return ""
            if (!l.ok) return "Could not update: " + l.error
            return "Nothing to update"
        }
        color: System.updateLast && !System.updateLast.ok ? Theme.error : Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    // Backup: the user's configuration in a git repository (backup.py). Offers to create one,
    // then a private GitHub remote when gh is logged in, then pushing, asking twice and
    // saying plainly when the repo is public.
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
                text: System.backupBusy ? "…" : "Create"
                emphasis: true
                available: !System.backupBusy
                onClicked: System.backupCmd("init")
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
                font.family: Theme.fontText
            }
        }

        SettingsRow {
            visible: page.backup.repo === true
            icon: "\u{F006F}"
            title: page.backup.pending > 0
                ? page.backup.pending + (page.backup.pending === 1 ? " change not saved" : " changes not saved")
                : "Everything is saved"

            PillButton {
                text: System.backupBusy ? "…" : "Back up now"
                emphasis: page.backup.pending > 0
                available: page.backup.pending > 0 && !System.backupBusy
                onClicked: System.backupCmd("backup")
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
                available: !System.backupBusy
                onClicked: {
                    if (!githubRow.armed) {
                        githubRow.armed = true
                        disarmGithub.restart()
                        return
                    }
                    githubRow.armed = false
                    System.backupCmd("github")
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
                available: page.backup.unpushed > 0 && !System.backupBusy
                onClicked: {
                    if (!pushRow.armed) {
                        pushRow.armed = true
                        disarmPush.restart()
                        return
                    }
                    pushRow.armed = false
                    System.backupCmd("push")
                }
            }
        }
    }

    // What the last action did.
    Text {
        width: parent.width
        visible: System.backupLast !== null
        text: {
            var l = System.backupLast
            if (!l) return ""
            var verb = { init: "create the backup", backup: "back up", push: "push", github: "add GitHub" }[l.action] || l.action
            if (!l.ok) return "Could not " + verb + ": " + l.error
            if (l.action === "push") return "Uploaded"
            if (l.action === "github") return "Added to GitHub, private, and uploaded"
            if (l.action === "init") return "Backup created in " + (page.backup.display || "")
            return l.committed ? "Saved as " + (page.backup.hash || "") : "Nothing to save"
        }
        color: System.backupLast && !System.backupLast.ok ? Theme.error : Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
}
