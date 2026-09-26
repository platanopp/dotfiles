import QtQuick

// One choice out of a few, in one pill: the chosen segment filled in the
// accent with a check beside its label, the rest plain. The fill slides from
// one segment to the next rather than blinking, so the control says which way
// the choice moved.
//
//   options: [{ value, label }]    value compared with ===
//   value:   the current choice
//   picked(value) when another segment is tapped
Rectangle {
    id: root

    property var options: []
    property var value
    signal picked(var value)

    implicitHeight: 36
    implicitWidth: row.implicitWidth + 8
    radius: height / 2
    // Sunk below the card it sits on, the way the chosen segment rises out
    // of it.
    color: Theme.alpha(Theme.background, 0.45)

    readonly property int currentIndex: {
        for (var i = 0; i < root.options.length; i++)
            if (root.options[i].value === root.value) return i
        return -1
    }

    Rectangle {
        id: fill
        readonly property Item target: root.currentIndex >= 0 && segments.count > root.currentIndex
            ? segments.itemAt(root.currentIndex) : null
        visible: fill.target !== null
        x: fill.target ? row.x + fill.target.x : 4
        y: 4
        width: fill.target ? fill.target.width : 0
        height: root.height - 8
        radius: height / 2
        color: Theme.accent

        Behavior on x { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        x: 4
        y: 4

        Repeater {
            id: segments
            model: root.options

            Item {
                id: seg
                required property var modelData
                required property int index
                readonly property bool chosen: seg.index === root.currentIndex

                width: label.implicitWidth + (seg.chosen ? 18 : 0) + 28
                height: root.height - 8

                Behavior on width { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: seg.chosen
                        text: "\u{F012C}"
                        size: Theme.iconTiny
                        color: Theme.accentText
                    }

                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.modelData.label
                        font.pixelSize: 11
                        font.bold: seg.chosen
                        font.family: Theme.fontMono
                        color: seg.chosen ? Theme.accentText : Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                    }
                }

                StateLayer {
                    radius: height / 2
                    interactive: !seg.chosen
                    onTapped: root.picked(seg.modelData.value)
                }
            }
        }
    }
}
