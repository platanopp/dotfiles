import QtQuick
import qs.config
import qs.desktop
import qs.services

// The month as a grid, Monday first, today in the accent: the one thing on
// it that is "now". Always six rows, so the card is the same size every
// month and a month that needs five does not leave it short.
WidgetCard {
    id: root

    // Re-worked out when the date turns over.
    readonly property var today: { Clock.currentDate; return new Date() }

    readonly property var cells: {
        var first = new Date(root.today.getFullYear(), root.today.getMonth(), 1)
        var lead = (first.getDay() + 6) % 7
        var out = []
        for (var i = 0; i < 42; i++) {
            var d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i)
            out.push({ day: d.getDate(),
                       inMonth: d.getMonth() === root.today.getMonth(),
                       isToday: d.toDateString() === root.today.toDateString() })
        }
        return out
    }

    readonly property int cellW: 34
    readonly property int cellH: 32

    Column {
        anchors.fill: parent
        anchors.margins: 20
        anchors.topMargin: 18
        spacing: 8

        Text {
            leftPadding: 4
            text: root.today.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
            color: Theme.textPrimary
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.family: Theme.fontText
        }

        Row {
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                Text {
                    required property var modelData
                    width: root.cellW
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: Theme.fontText
                }
            }
        }

        Grid {
            columns: 7

            Repeater {
                model: root.cells

                Item {
                    id: cell
                    required property var modelData
                    width: root.cellW
                    height: root.cellH

                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: height / 2
                        visible: cell.modelData.isToday
                        color: Theme.accent
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.day
                        color: cell.modelData.isToday ? Theme.accentText
                             : cell.modelData.inMonth ? Theme.textPrimary : Theme.textMuted
                        font.pixelSize: 12
                        font.weight: cell.modelData.isToday ? Font.Bold : Font.Normal
                        font.family: Theme.fontText
                        font.features: Theme.tabular
                    }
                }
            }
        }
    }
}
