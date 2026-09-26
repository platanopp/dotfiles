import QtQuick
import QtQuick.Layouts

// Settings -> Power & idle: how hard the CPU works, and what happens when the
// desk is left alone -- screens off, then the lock, and how the side display
// goes dark. The timing lives in hypridle.conf and the side display's mode in
// idle-screens.sh; scripts/idle_settings.py reads and rewrites both.
Column {
    id: page
    spacing: 28

    readonly property var idle: AppState.idleSettings
    readonly property int lockDelay: Math.max(0, page.idle.lock - page.idle.screensOff)

    SettingsGroup {
        width: parent.width
        title: "Performance"
        visible: AppState.powerProfiles.length > 0

        SettingsRow {
            stacked: true
            title: "Power mode"
            description: "How hard the CPU is allowed to work. The choice is kept across reboots -- power-profiles-daemon alone would start every session on Balanced."

            Segmented {
                options: AppState.powerProfiles.map(p => ({ value: p.name, label: p.label }))
                value: AppState.powerProfile
                onPicked: v => AppState.setPowerProfile(v)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "When you step away"
        subtitle: "Counted from the last key press or mouse move. A playing video, or a game you are using, keeps it from starting."

        SettingsRow {
            stacked: true
            title: "Turn the screens off after"
            description: "The lock below moves with it, keeping the same distance."

            Segmented {
                options: [
                    { value: 300, label: "5 min" },
                    { value: 600, label: "10 min" },
                    { value: 900, label: "15 min" },
                    { value: 1800, label: "30 min" },
                    { value: 3600, label: "1 h" }
                ]
                value: page.idle.screensOff
                onPicked: v => AppState.setScreensOff(v)
            }
        }

        SettingsRow {
            stacked: true
            title: "Lock the screen"
            description: "Kept apart from the screens going off on purpose: a screen that has only just gone dark comes back with a key press, without a password."

            Segmented {
                options: [
                    { value: 0, label: "With the screens" },
                    { value: 300, label: "+5 min" },
                    { value: 600, label: "+10 min" },
                    { value: 1800, label: "+30 min" }
                ]
                value: page.lockDelay
                onPicked: v => AppState.setLockDelay(v)
            }
        }

        SettingsRow {
            stacked: true
            title: "Side display"
            description: page.idle.xiaomiMode === "cover"
                ? "Kept awake behind a black cover with its backlight at 0. Safe in every case, but it keeps drawing power."
                : "Switched off over DDC, for real. The Xiaomi drops its HDMI link when it does, and Hyprland has coped with that every time it was tested -- if it ever comes back frozen, pick Cover."

            Segmented {
                options: [
                    { value: "ddc-off", label: "Switch off" },
                    { value: "cover", label: "Cover in black" }
                ]
                value: page.idle.xiaomiMode
                onPicked: v => AppState.setXiaomiMode(v)
            }
        }
    }
}
