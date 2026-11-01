import QtQuick
import qs.components
import qs.config

// One choice out of a few in one pill: the chosen segment filled with a
// check, the fill sliding between them.
//
// options: [{ value, label }]    value compared with ===
// value:   the current choice
// picked(value) when another segment is tapped
Rectangle {
    id: root

    property var options: []
    property var value
    // The page's colour for the chosen segment; the accent when none is given.
    property color tint: Theme.accent
    readonly property color onTint: Theme.inkOn(root.tint)
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
        color: root.tint

        Behavior on x { Elastic { small: true } }
        Behavior on width { Elastic { small: true } }
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

                Behavior on width { Elastic { small: true } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: seg.chosen
                        text: "\u{F012C}"
                        size: Theme.iconTiny
                        color: root.onTint
                    }

                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.modelData.label
                        font.pixelSize: 11
                        font.bold: seg.chosen
                        font.family: Theme.fontText
                        color: seg.chosen ? root.onTint : Theme.textSecondary
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
