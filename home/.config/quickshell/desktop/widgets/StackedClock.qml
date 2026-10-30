import QtQuick
import qs.config
import qs.desktop
import qs.services

// Hour above minute, as large as the card allows, and the date under them:
// the time read from across the room.
WidgetCard {
    id: root

    // Re-read each time the shell's clock turns over a minute.
    readonly property var now: { Clock.currentTime; return new Date() }

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, ShellSettings.clock24h ? "hh" : "h")
            color: Theme.textPrimary
            font.pixelSize: 96
            font.weight: Font.Bold
            font.family: Theme.fontDisplay
            font.features: Theme.tabular
            lineHeightMode: Text.FixedHeight
            lineHeight: 92
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "mm")
            color: Theme.textPrimary
            font.pixelSize: 96
            font.weight: Font.Bold
            font.family: Theme.fontDisplay
            font.features: Theme.tabular
            lineHeightMode: Text.FixedHeight
            lineHeight: 92
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 6
            text: root.now.toLocaleDateString(Qt.locale("en_US"), "ddd d MMM")
                  + (ShellSettings.clock24h ? "" : "  " + Qt.formatDateTime(root.now, "AP"))
            color: Theme.textSecondary
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.family: Theme.fontText
        }
    }
}
