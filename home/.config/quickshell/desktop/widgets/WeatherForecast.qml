import QtQuick
import qs.components
import qs.config
import qs.desktop
import qs.services

// The next five days: the sky, the high, the low.
WidgetCard {
    id: root

    readonly property var shown: Weather.days.slice(0, 5)

    Column {
        anchors.fill: parent
        anchors.margins: 18
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        spacing: 12

        Item {
            width: parent.width
            height: title.implicitHeight

            Text {
                id: title
                text: "Forecast"
                color: Theme.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.family: Theme.fontText
            }

            Text {
                anchors.right: parent.right
                anchors.baseline: title.baseline
                width: Math.min(implicitWidth, parent.width - title.implicitWidth - 12)
                horizontalAlignment: Text.AlignRight
                text: Weather.city
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        Row {
            visible: root.shown.length > 0
            width: parent.width

            Repeater {
                model: root.shown

                Column {
                    id: day
                    required property var modelData
                    required property int index
                    width: parent.width / 5
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: day.index === 0 ? "Today"
                            : new Date(day.modelData.date + "T12:00").toLocaleDateString(Qt.locale("en_US"), "ddd")
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.family: Theme.fontText
                    }

                    IconGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.icon(day.modelData.code, true)
                        color: Theme.textPrimary
                        size: 24
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(day.modelData.max) + "°"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.family: Theme.fontText
                        font.features: Theme.tabular
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(day.modelData.min) + "°"
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.fontText
                        font.features: Theme.tabular
                    }
                }
            }
        }

        Text {
            visible: root.shown.length === 0
            width: parent.width
            text: Weather.loading ? "Fetching the forecast" : "No forecast yet. It arrives once the network is up."
            color: Theme.textMuted
            font.pixelSize: 12
            font.family: Theme.fontText
            wrapMode: Text.WordWrap
        }
    }
}
