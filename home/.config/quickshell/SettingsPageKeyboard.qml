import QtQuick
import QtQuick.Layouts

// Settings -> Keyboard: a Wooting keyboard coloured from the wallpaper. The
// letters take the picture's dominant colour, the other keys its other
// tones (scripts/keyboard_rgb.py). The board drawn here is a sketch of the
// same split, in the colours last sent.
Column {
    id: page
    spacing: 24

    readonly property var status: AppState.keyboardRgbStatus
    readonly property var pal: AppState.keyboardRgbPalette

    Component.onCompleted: AppState.refreshKeyboardRgb()

    // A 60% ISO board: [width in units, is a letter]. Letters follow the
    // script's LETTERS set.
    readonly property var rows: [
        [[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[2,0]],
        [[1.5,0],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,0],[1,0],[1.5,0]],
        [[1.75,0],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,0],[1,0],[1.25,0]],
        [[1.25,0],[1,0],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,0],[1,0],[1,0],[2.75,0]],
        [[1.25,0],[1.25,0],[1.25,0],[6.25,0],[1.25,0],[1.25,0],[1.25,0],[1.25,0]]
    ]

    // The same spread as the script: the other tones across the board from
    // left to right, a little of the row mixed in.
    function keyColour(rowIndex, x, isLetter) {
        if (!page.pal) return Theme.surfaceContainerHigh
        if (isLetter) return page.pal.dominant
        var others = page.pal.others || []
        if (others.length === 0) return page.pal.dominant
        var pos = (x / 15) * 0.8 + ((rowIndex + 1) / 6) * 0.2
        return others[Math.min(others.length - 1, Math.floor(pos * others.length))]
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
                            readonly property real startX: {
                                var x = 0
                                for (var i = 0; i < key.index; i++) x += keyRow.modelData[i][0]
                                return x
                            }
                            width: board.unit * key.modelData[0] + 4 * (key.modelData[0] - 1)
                            height: board.unit
                            radius: 7
                            color: page.keyColour(keyRow.index, key.startX, key.modelData[1] === 1)

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
