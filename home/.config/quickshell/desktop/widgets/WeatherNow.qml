import QtQuick
import qs.components
import qs.config
import qs.desktop
import qs.services

// The temperature and the sky, from the bar's own forecast (Weather), with
// today's high and low under them.
WidgetCard {
    id: root

    readonly property var todayRange: Weather.days.length > 0 ? Weather.days[0] : null

    Row {
        visible: Weather.ready
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 18

        IconGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.icon(Weather.code, Weather.isDay)
            color: Theme.textPrimary
            size: 48
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: Math.round(Weather.temp) + "°"
                color: Theme.textPrimary
                font.pixelSize: 36
                font.weight: Font.Bold
                font.family: Theme.fontDisplay
                font.features: Theme.tabular
            }

            Text {
                text: Weather.describe(Weather.code)
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontText
            }

            Text {
                visible: root.todayRange !== null
                topPadding: 2
                text: root.todayRange ? "H " + Math.round(root.todayRange.max) + "°  L "
                                        + Math.round(root.todayRange.min) + "°" : ""
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontText
                font.features: Theme.tabular
            }
        }
    }

    // Before the first answer, or when there is none: say which.
    Column {
        visible: !Weather.ready
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            text: Weather.loading ? "Fetching the forecast" : "No forecast yet"
            color: Theme.textPrimary
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.family: Theme.fontText
        }

        Text {
            width: parent.width
            text: Weather.error.length > 0 ? Weather.error : "It arrives once the network is up."
            color: Theme.textMuted
            font.pixelSize: 12
            font.family: Theme.fontText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
