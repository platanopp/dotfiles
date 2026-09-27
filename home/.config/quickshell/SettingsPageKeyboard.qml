import QtQuick
import QtQuick.Layouts

// Settings -> Keyboard: a Wooting keyboard coloured from the wallpaper as a
// mosaic -- letters from the picture's dominant colours, the other keys from
// its other tones, every key its own shade (scripts/keyboard_rgb.py). The
// board drawn here shows the colours last sent, key for key.
Column {
    id: page
    spacing: 24

    readonly property var status: AppState.keyboardRgbStatus
    readonly property var pal: AppState.keyboardRgbPalette

    Component.onCompleted: AppState.refreshKeyboardRgb()

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
        title: "Wooting"

        SettingsRow {
            icon: "\u{F030C}"
            title: page.status.connected ? (page.status.model || "Wooting keyboard")
                 : page.status.sdk === false ? "The Wooting RGB SDK is not installed"
                 : "No Wooting keyboard found"

            PillButton {
                icon: "\u{F0450}"
                text: "Check"
                onClicked: AppState.refreshKeyboardRgb()
            }
        }

        SettingsRow {
            icon: "\u{F0E09}"
            title: "Match the wallpaper"
            description: AppState.keyboardRgbError.length > 0 ? AppState.keyboardRgbError : ""

            SettingsSwitch {
                checked: ShellSettings.keyboardRgb
                available: page.status.connected === true
                onToggled: c => ShellSettings.set("keyboardRgb", c)
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
            visible: ShellSettings.keyboardRgb && page.status.connected === true
            icon: "\u{F0450}"
            title: "Paint it again"
            description: "After switching profiles on the keyboard"

            PillButton {
                text: "Apply"
                onClicked: AppState.applyKeyboardRgb()
            }
        }
    }
}
