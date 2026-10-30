import QtQuick
import qs.config
import qs.desktop
import qs.services

// The bar's clock pill at desktop size: the time, a dot, the day, on one
// line of glass with fully round ends.
WidgetCard {
    id: root

    readonly property string day: { Clock.currentDate; return new Date().toLocaleDateString(Qt.locale("en_US"), "dddd d MMMM") }

    radius: height / 2

    Row {
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Clock.currentTime
            color: Theme.textPrimary
            font.pixelSize: 30
            font.bold: true
            font.family: Theme.fontDisplay
            font.features: Theme.tabular
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "·"
            color: Theme.textMuted
            font.pixelSize: 18
            font.family: Theme.fontText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.day
            color: Theme.textSecondary
            font.pixelSize: 15
            font.family: Theme.fontText
            font.features: Theme.tabular
        }
    }
}
