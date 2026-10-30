import QtQuick
import QtQuick.Layouts
import qs.config
import qs.desktop
import qs.services

// This week on one strip, Monday to Sunday, set like the clock panel's
// calendar: weekday initials above, the dates below, today in the accent.
WidgetCard {
    id: root

    readonly property var today: { Clock.currentDate; return new Date() }

    // ISO week: the week that holds this week's Thursday.
    readonly property int weekNumber: {
        var t = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
        t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7)
        var jan4 = new Date(t.getFullYear(), 0, 4)
        return 1 + Math.round(((t - jan4) / 86400000 - 3 + (jan4.getDay() + 6) % 7) / 7)
    }

    readonly property var days: {
        var back = (root.today.getDay() + 6) % 7
        var out = []
        for (var i = 0; i < 7; i++) {
            var d = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate() - back + i)
            out.push({ name: d.toLocaleDateString(Qt.locale("en_US"), "ddd").slice(0, 2),
                       day: d.getDate(), isToday: i === back, weekend: i >= 5 })
        }
        return out
    }

    readonly property real cellW: (root.width - 32) / 7

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.today.toLocaleDateString(Qt.locale("en_US"), "MMMM")
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontText
            }

            Text {
                Layout.fillWidth: true
                text: "Week " + root.weekNumber
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontText
            }
        }

        Row {
            Repeater {
                model: root.days

                Column {
                    id: day
                    required property var modelData
                    width: root.cellW
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 20
                        verticalAlignment: Text.AlignVCenter
                        text: day.modelData.name
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.bold: true
                        font.family: Theme.fontText
                    }

                    Item {
                        width: parent.width
                        height: 32

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: height / 2
                            visible: day.modelData.isToday
                            color: Theme.accent
                        }

                        Text {
                            anchors.centerIn: parent
                            text: day.modelData.day
                            color: day.modelData.isToday ? Theme.accentText
                                 : day.modelData.weekend ? Theme.textSecondary : Theme.textPrimary
                            font.pixelSize: 12
                            font.bold: day.modelData.isToday
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }
                }
            }
        }
    }
}
