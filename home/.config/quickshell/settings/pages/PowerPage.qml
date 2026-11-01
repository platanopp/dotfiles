import QtQuick
import qs.config
import qs.services
import qs.settings

// Settings -> Power & idle: the CPU profile and what happens when the desk is left alone.
// idle_settings.py reads and rewrites hypridle.conf and idle-screens.sh.
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    readonly property var idle: Power.idleSettings
    readonly property int lockDelay: Math.max(0, page.idle.lock - page.idle.screensOff)

    SettingsGroup {
        width: parent.width
        title: "Performance"
        tint: page.tint
        visible: Power.powerProfiles.length > 0

        SettingsRow {
            stacked: true
            icon: "\u{F04C5}"
            tint: page.tint
            title: "Power mode"

            Segmented {
                tint: page.tint
                options: Power.powerProfiles.map(p => ({ value: p.name, label: p.label }))
                value: Power.powerProfile
                onPicked: v => Power.setPowerProfile(v)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "When you step away"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F0D90}"
            tint: page.tint
            title: "Screens off after"

            Segmented {
                tint: page.tint
                options: [
                    { value: 300, label: "5 min" },
                    { value: 600, label: "10 min" },
                    { value: 900, label: "15 min" },
                    { value: 1800, label: "30 min" },
                    { value: 3600, label: "1 h" }
                ]
                value: page.idle.screensOff
                onPicked: v => Power.setScreensOff(v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F097F}"
            tint: page.tint
            title: "Then lock"

            Segmented {
                tint: page.tint
                options: [
                    { value: 0, label: "Right away" },
                    { value: 300, label: "+5 min" },
                    { value: 600, label: "+10 min" },
                    { value: 1800, label: "+30 min" }
                ]
                value: page.lockDelay
                onPicked: v => Power.setLockDelay(v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F0379}"
            tint: page.tint
            title: "Side display"
            description: page.idle.xiaomiMode === "cover" ? "Stays awake under a black cover"
                                                          : "Really off, over DDC"

            Segmented {
                tint: page.tint
                options: [
                    { value: "ddc-off", label: "Switch off" },
                    { value: "cover", label: "Black cover" }
                ]
                value: page.idle.xiaomiMode
                onPicked: v => Power.setXiaomiMode(v)
            }
        }
    }
}
