import QtQuick
import qs.config
import qs.desktop
import qs.services

// The clock panel's header, grown for the desktop: the time large in SF Pro
// Display, the day under it in the muted grey the panels use for metadata.
WidgetCard {
    id: root

    readonly property string day: { Clock.currentDate; return new Date().toLocaleDateString(Qt.locale("en_US"), "dddd d MMMM") }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
            text: Clock.currentTime
            color: Theme.textPrimary
            font.pixelSize: 52
            font.bold: true
            font.family: Theme.fontDisplay
            font.features: Theme.tabular
        }

        Text {
            leftPadding: 2
            text: root.day
            color: Theme.textMuted
            font.pixelSize: 13
            font.family: Theme.fontText
        }
    }
}
