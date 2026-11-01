import QtQuick
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Shell: how the bar, the clock and the lock screen behave, kept in
// shell-settings.json (ShellSettings).
Column {
    id: page
    spacing: 24

    readonly property var monitors: Display.displayState.monitors || []

    Component.onCompleted: Display.refreshDisplay()

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
                options: page.monitors.map(m => ({ value: m.name, label: Display.shortName(m) }))
                value: ShellSettings.lockMonitor
                onPicked: v => ShellSettings.set("lockMonitor", v)
            }
        }

        SettingsRow {
            icon: "\u{F0341}"
            title: "Try it"

            PillButton {
                text: "Lock now"
                onClicked: Power.lockSession()
            }
        }
    }
}
