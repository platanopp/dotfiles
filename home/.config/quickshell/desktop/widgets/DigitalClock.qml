import QtQuick
import qs.config
import qs.desktop
import qs.services

// The time on one line and the date written out below it, set like a
// headline and its standfirst.
WidgetCard {
    id: root

    readonly property var now: { Clock.currentTime; return new Date() }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 26
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Row {
            spacing: 6

            Text {
                id: time
                text: Qt.formatDateTime(root.now, ShellSettings.clock24h ? "hh:mm" : "h:mm")
                color: Theme.textPrimary
                font.pixelSize: 64
                font.weight: Font.Bold
                font.family: Theme.fontDisplay
                font.features: Theme.tabular
            }

            Text {
                visible: !ShellSettings.clock24h
                anchors.baseline: time.baseline
                text: Qt.formatDateTime(root.now, "AP")
                color: Theme.textSecondary
                font.pixelSize: 18
                font.weight: Font.DemiBold
                font.family: Theme.fontText
            }
        }

        Text {
            text: root.now.toLocaleDateString(Qt.locale("en_US"), "dddd, d MMMM")
            color: Theme.textSecondary
            font.pixelSize: 14
            font.family: Theme.fontText
        }
    }
}
