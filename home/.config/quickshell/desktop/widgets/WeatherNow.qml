import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.desktop
import qs.services

// The clock panel's weather block on its own: the header with the city, and
// the raised tile with the sky, the temperature, humidity and wind.
WidgetCard {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "Weather"
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

        Rectangle {
            visible: Weather.ready
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            radius: Theme.radiusLarge
            color: Theme.surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: Weather.icon(Weather.code, Weather.isDay)
                    color: Theme.textPrimary
                    font.pixelSize: 30
                    font.family: Theme.fontMono
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: Math.round(Weather.temp) + "°"
                        color: Theme.textPrimary
                        font.pixelSize: 22
                        font.bold: true
                        font.family: Theme.fontDisplay
                        font.features: Theme.tabular
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Weather.describe(Weather.code)
                        color: Theme.textSecondary
                        font.pixelSize: 10
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }
                }

                ColumnLayout {
                    spacing: 2

                    RowLayout {
                        spacing: 4

                        IconGlyph {
                            text: "󰖎"
                            color: Theme.textMuted
                            size: Theme.iconTiny
                        }

                        Text {
                            text: Weather.humidity + "%"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }

                    RowLayout {
                        spacing: 4

                        IconGlyph {
                            text: "󰖝"
                            color: Theme.textMuted
                            size: Theme.iconTiny
                        }

                        Text {
                            text: Math.round(Weather.wind) + " km/h"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontText
                        }
                    }
                }
            }
        }

        // Before the first answer, or when there is none: say which.
        Text {
            visible: !Weather.ready
            Layout.fillWidth: true
            text: Weather.loading ? "Fetching the forecast..."
                : Weather.error.length > 0 ? "No forecast: " + Weather.error
                : "No forecast yet. It arrives once the network is up."
            color: Theme.textMuted
            font.pixelSize: 11
            font.family: Theme.fontText
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }
    }
}
