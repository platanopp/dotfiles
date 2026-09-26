import QtQuick

// One choice out of many, as chips that wrap onto more lines when they run
// out of room -- for lists too long for a Segmented, like the modes a display
// offers. Same look as a Segmented's chosen segment: accent fill and a check.
//
//   options: [{ value, label }]
//   value:   the current choice
//   picked(value)
Flow {
    id: root

    property var options: []
    property var value
    signal picked(var value)

    spacing: 6

    Repeater {
        model: root.options

        Rectangle {
            id: chip
            required property var modelData
            readonly property bool chosen: chip.modelData.value === root.value

            width: chipRow.implicitWidth + 24
            height: 32
            radius: height / 2
            color: chip.chosen ? Theme.accent : Theme.alpha(Theme.background, 0.45)

            Behavior on color { ColorAnimation { duration: Theme.durShort } }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6

                IconGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chip.chosen
                    text: "\u{F012C}"
                    size: Theme.iconTiny
                    color: Theme.accentText
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData.label
                    font.pixelSize: 11
                    font.bold: chip.chosen
                    font.family: Theme.fontMono
                    color: chip.chosen ? Theme.accentText : Theme.textSecondary
                }
            }

            StateLayer {
                radius: chip.radius
                interactive: !chip.chosen
                onTapped: root.picked(chip.modelData.value)
            }
        }
    }
}
