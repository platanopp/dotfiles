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
    SettingsGroup {
        width: parent.width
        title: "Backup"
        visible: page.backup.repo === true

        SettingsRow {
            icon: "\u{F02A2}"
            title: "Last saved"
            description: page.backup.subject || ""

            Text {
                text: (page.backup.hash || "") + (page.backup.when ? "  ·  " + page.backup.when : "")
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.fontMono
            }
        }

        SettingsRow {
            icon: "\u{F006F}"
            title: page.backup.pending > 0
                ? page.backup.pending + (page.backup.pending === 1 ? " change not saved" : " changes not saved")
                : "Everything is saved"

            PillButton {
                text: AppState.backupBusy && AppState.backupLast === null ? "…" : "Back up now"
                emphasis: page.backup.pending > 0
                available: page.backup.pending > 0 && !AppState.backupBusy
                onClicked: AppState.backupCmd("backup")
            }
        }

        SettingsRow {
            id: pushRow
            icon: "\u{F0B7E}"
            title: page.backup.unpushed > 0
                ? page.backup.unpushed + (page.backup.unpushed === 1 ? " commit not on GitHub" : " commits not on GitHub")
                : "GitHub is up to date"
            description: pushRow.armed ? "The repository is public -- press again to publish" : ""

            // Two presses: the first arms it and says why, the second pushes.
            property bool armed: false

            Timer {
                id: disarmPush
                interval: 5000
                onTriggered: pushRow.armed = false
            }

            PillButton {
                text: pushRow.armed ? "Publish" : "Push"
                danger: pushRow.armed
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

    // What the last backup or push did.
    Text {
        width: parent.width
        visible: AppState.backupLast !== null
        text: {
            var l = AppState.backupLast
            if (!l) return ""
            if (!l.ok) return "Could not " + (l.action === "push" ? "push" : "back up") + ": " + l.error
            if (l.action === "push") return "Pushed to GitHub"
            return l.committed ? "Saved as " + (page.backup.hash || "") : "Nothing to save"
        }
        color: AppState.backupLast && !AppState.backupLast.ok ? Theme.error : Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontMono
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
}
