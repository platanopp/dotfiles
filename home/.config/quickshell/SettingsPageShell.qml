import QtQuick
import QtQuick.Layouts

// Settings -> Shell: how the bar, the clock and the lock screen behave --
// choices that used to be written into the code. Kept in
// ~/.config/quickshell/shell-settings.json (see ShellSettings).
Column {
    id: page
    spacing: 24

    readonly property var monitors: AppState.displayState.monitors || []

    function shortName(m) {
        return (m.description || m.name)
            .replace(/ (Electric Company|Corporation|Technologies|Technology|Inc\.?|Co\.?,? ?Ltd\.?)/g, "")
    }

    Component.onCompleted: AppState.refreshDisplay()

    SettingsGroup {
        width: parent.width
        title: "Clock"

        SettingsRow {
            icon: "\u{F0954}"
            title: "Date"

            Segmented {
                options: [
                    { value: "hover", label: "On hover" },
                    { value: "always", label: "Always" }
                ]
                value: ShellSettings.clockDate
                onPicked: v => ShellSettings.set("clockDate", v)
            }
        }

        SettingsRow {
            icon: "\u{F051B}"
            title: "24-hour clock"

            SettingsSwitch {
                checked: ShellSettings.clock24h
                onToggled: c => ShellSettings.set("clock24h", c)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Bar"

        SettingsRow {
            icon: "\u{F0293}"
            title: "Hide over fullscreen"
            description: "Comes back at the top edge"

            SettingsSwitch {
                checked: ShellSettings.barHideFullscreen
                onToggled: c => ShellSettings.set("barHideFullscreen", c)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Lock screen"

        SettingsRow {
            icon: "\u{F033E}"
            title: "Lock when the session starts"

            SettingsSwitch {
                checked: ShellSettings.lockAtBoot
                onToggled: c => ShellSettings.set("lockAtBoot", c)
            }
        }

        SettingsRow {
            stacked: page.monitors.length > 2
            icon: "\u{F0379}"
            title: "Password field on"

            Segmented {
                options: page.monitors.map(m => ({ value: m.name, label: page.shortName(m) }))
                value: ShellSettings.lockMonitor
                onPicked: v => ShellSettings.set("lockMonitor", v)
            }
        }

        SettingsRow {
            icon: "\u{F0341}"
            title: "Try it"

            PillButton {
                text: "Lock now"
                onClicked: AppState.lockSession()
            }
        }
    }
}
