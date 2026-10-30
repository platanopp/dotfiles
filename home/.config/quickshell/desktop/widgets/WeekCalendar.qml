import QtQuick
import qs.config
import qs.desktop
import qs.services

// This week on one strip, Monday to Sunday, today filled in the accent.
WidgetCard {
    id: root

    readonly property var today: { Clock.currentDate; return new Date() }

    readonly property var days: {
        var back = (root.today.getDay() + 6) % 7
        var out = []
        for (var i = 0; i < 7; i++) {
            var d = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate() - back + i)
            out.push({ name: d.toLocaleDateString(Qt.locale("en_US"), "ddd").slice(0, 2),
                       day: d.getDate(), isToday: i === back })
        }
        return out
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 8

        Text {
            leftPadding: 2
            text: root.today.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
            color: Theme.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: Theme.fontText
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Repeater {
                model: root.days

                Rectangle {
                    id: day
                    required property var modelData
                    width: 38
                    height: 52
                    radius: width / 2
                    color: day.modelData.isToday ? Theme.accent : "transparent"

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: day.modelData.name
                            color: day.modelData.isToday ? Theme.accentText : Theme.textMuted
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.family: Theme.fontText
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: day.modelData.day
                            color: day.modelData.isToday ? Theme.accentText : Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: day.modelData.isToday ? Font.Bold : Font.DemiBold
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }
                }
            }
        }
    }
}
