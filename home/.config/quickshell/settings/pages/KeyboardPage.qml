import QtQuick
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Keyboard: RGB keyboards lit with the wallpaper itself -- a
// Wooting through its own SDK, any other brand through OpenRGB --
// the picture laid over the board, each key the colour of the part under it
// (scripts/keyboard_rgb.py). The board drawn here shows the colours last
// sent, key for key.
Column {
    id: page
    spacing: 24

    readonly property var status: KeyboardRgb.keyboardRgbStatus
    readonly property var pal: KeyboardRgb.keyboardRgbPalette

    Component.onCompleted: KeyboardRgb.refreshKeyboardRgb()

    // A 60% ISO board: [width in units, matrix column] per key; the row in
    // Wooting's matrix is the row here plus one.
    readonly property var rows: [
        [[1,0],[1,1],[1,2],[1,3],[1,4],[1,5],[1,6],[1,7],[1,8],[1,9],[1,10],[1,11],[1,12],[2,13]],
        [[1.5,0],[1,1],[1,2],[1,3],[1,4],[1,5],[1,6],[1,7],[1,8],[1,9],[1,10],[1,11],[1,12],[1.5,13]],
        [[1.75,0],[1,1],[1,2],[1,3],[1,4],[1,5],[1,6],[1,7],[1,8],[1,9],[1,10],[1,11],[1,12],[1.25,13]],
        [[1.25,0],[1,1],[1,2],[1,3],[1,4],[1,5],[1,6],[1,7],[1,8],[1,9],[1,10],[1,11],[2.75,13]],
        [[1.25,0],[1.25,1],[1.25,2],[6.25,6],[1.25,10],[1.25,11],[1.25,12],[1.25,13]]
    ]

    // The colour the script sent to that key.
    function keyColour(rowIndex, col) {
        if (!page.pal || !page.pal.keys) return Theme.surfaceContainerHigh
        return page.pal.keys[(rowIndex + 1) + "," + col] || Theme.surfaceContainerHigh
    }

    // ── The board ────────────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        height: board.height + 64
        radius: 22
        color: Theme.surfaceContainer

        Column {
            id: board
            anchors.centerIn: parent
            spacing: 4
            opacity: ShellSettings.keyboardRgb && page.status.connected ? 1 : 0.35

            Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }

            readonly property real unit: Math.min(38, (page.width - 64 - 14 * 4) / 15)

            Repeater {
                model: page.rows

                Row {
                    id: keyRow
                    required property var modelData
                    required property int index
                    spacing: 4

                    Repeater {
                        model: keyRow.modelData

                        Rectangle {
                            id: key
                            required property var modelData
                            required property int index
                            width: board.unit * key.modelData[0] + 4 * (key.modelData[0] - 1)
                            height: board.unit
                            radius: 7
                            color: page.keyColour(keyRow.index, key.modelData[1])

                            Behavior on color { ColorAnimation { duration: Theme.durLong } }
                        }
                    }
                }
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Keyboards"

        // Every keyboard being lit, and how: key by key, by zones, or one
        // colour for the whole board.
        Repeater {
            model: page.status.devices || []

            SettingsRow {
                id: kb
                required property var modelData
                icon: "\u{F030C}"
                title: kb.modelData.name
                description: (kb.modelData.kind === "wooting" ? "Wooting SDK" : "OpenRGB") + " · "
                    + (kb.modelData.shape === "per-key" ? "key by key"
                       : kb.modelData.shape === "zones" ? "by zones" : "one colour")
            }
        }

        SettingsRow {
            visible: !page.status.devices || page.status.devices.length === 0
            icon: "\u{F030C}"
            title: "No RGB keyboard found"
            description: page.status.openrgb ? "" : "Other brands need OpenRGB running"

            PillButton {
                icon: "\u{F0450}"
                text: "Check"
                onClicked: KeyboardRgb.refreshKeyboardRgb()
            }
        }

        // Only the Wooting SDK reaches a Wooting; OpenRGB reaches the rest.
        // Said when it is not running, since that is why a keyboard of
        // another brand would be missing from the list above.
        SettingsRow {
            visible: !!(page.status.devices && page.status.devices.length > 0) && page.status.openrgb === false
            icon: "\u{F02FD}"
            title: "Other brands"
            description: "Keyboards other than Wooting are lit through OpenRGB, which is not running"

            PillButton {
                icon: "\u{F0450}"
                text: "Check"
                onClicked: KeyboardRgb.refreshKeyboardRgb()
            }
        }

        SettingsRow {
            icon: "\u{F0E09}"
            title: "Match the wallpaper"
            description: KeyboardRgb.keyboardRgbError.length > 0 ? KeyboardRgb.keyboardRgbError : ""

            SettingsSwitch {
                checked: ShellSettings.keyboardRgb
                available: page.status.connected === true
                onToggled: c => ShellSettings.set("keyboardRgb", c)
            }
        }

        // The keyboard only says which profile it is on by number, so the
        // one it is on right now is marked: switch on the keyboard and see.
        SettingsRow {
            stacked: true
            // Profiles are a Wooting's: the others have none to choose.
            visible: ShellSettings.keyboardRgb && (page.status.devices || []).some(d => d.kind === "wooting")
            icon: "\u{F0004}"
            title: "Wooting profile"
            value: KeyboardRgb.keyboardProfileActive >= 0 ? "On the keyboard now: " + (KeyboardRgb.keyboardProfileActive + 1) : ""

            Segmented {
                width: parent.width
                options: [
                    { value: -1, label: "All" },
                    { value: 0, label: KeyboardRgb.keyboardProfileActive === 0 ? "1 •" : "1" },
                    { value: 1, label: KeyboardRgb.keyboardProfileActive === 1 ? "2 •" : "2" },
                    { value: 2, label: KeyboardRgb.keyboardProfileActive === 2 ? "3 •" : "3" },
                    { value: 3, label: KeyboardRgb.keyboardProfileActive === 3 ? "4 •" : "4" }
                ]
                value: ShellSettings.keyboardRgbProfile
                onPicked: v => ShellSettings.set("keyboardRgbProfile", v)
            }
        }

        SettingsRow {
            stacked: true
            visible: ShellSettings.keyboardRgb
            icon: "\u{F00DF}"
            title: "Brightness"
            value: Math.round(brightSlider.shown) + "%"

            SettingsSlider {
                id: brightSlider
                width: parent.width
                from: 10; to: 100; step: 5
                value: ShellSettings.keyboardRgbBrightness
                format: v => Math.round(v) + "%"
                onMoved: v => ShellSettings.set("keyboardRgbBrightness", Math.round(v))
            }
        }

        SettingsRow {
            visible: ShellSettings.keyboardRgb
            icon: "\u{F0D46}"
            title: "Animate wallpaper changes"

            SettingsSwitch {
                checked: ShellSettings.keyboardRgbAnimate
                onToggled: c => ShellSettings.set("keyboardRgbAnimate", c)
            }
        }

        SettingsRow {
            visible: ShellSettings.keyboardRgb && page.status.connected === true
            icon: "\u{F0450}"
            title: "Paint it again"
            description: "After switching profiles on the keyboard"

            PillButton {
                text: "Apply"
                onClicked: KeyboardRgb.applyKeyboardRgb(ShellSettings.keyboardRgbAnimate)
            }
        }
    }
}
