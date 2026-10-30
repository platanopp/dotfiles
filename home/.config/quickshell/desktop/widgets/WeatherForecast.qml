import QtQuick
import QtQuick.Layouts
import qs.config
import qs.desktop
import qs.services

// The clock panel's forecast list on its own: one row a day, the sky, the
// high and the low, today's row tinted in the accent as it is there.
WidgetCard {
    id: root

    readonly property var shown: Weather.days.slice(0, 5)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "Forecast"
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontText
            }

            Text {
                Layout.fillWidth: true
                text: Weather.city
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        Column {
            Layout.fillWidth: true
            visible: root.shown.length > 0
            spacing: 2

            Repeater {
                model: root.shown

                Rectangle {
                    id: day
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 26
                    radius: Theme.radiusSmall
                    color: index === 0 ? Theme.alpha(Theme.accent, 0.14) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            Layout.preferredWidth: 30
                            text: day.index === 0 ? "today"
                                : new Date(day.modelData.date + "T12:00").toLocaleDateString(Qt.locale("en_US"), "ddd")
                            color: day.index === 0 ? Theme.accent : Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: day.index === 0
                            font.family: Theme.fontText
                        }

                        Text {
                            text: Weather.icon(day.modelData.code, true)
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.family: Theme.fontMono
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Weather.describe(day.modelData.code)
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }

                        Text {
                            text: Math.round(day.modelData.max) + "°"
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }

                        Text {
                            Layout.preferredWidth: 26
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(day.modelData.min) + "°"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.shown.length === 0
            text: Weather.loading ? "Fetching the forecast..." : "No forecast yet. It arrives once the network is up."
            color: Theme.textMuted
            font.pixelSize: 11
            font.family: Theme.fontText
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }
    }
}
