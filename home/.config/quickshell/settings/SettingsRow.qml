import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config

// One setting: badge, name and control, to the right or underneath when `stacked`; a description
// is a short hint at most. Rows sit in a SettingsGroup: round outer corners, nearly square where
// rows meet, so a group reads as one block.
Rectangle {
    id: row

    property string title: ""
    property string description: ""
    property string icon: ""
    property color tint: Theme.accent
    property bool stacked: false
    // Shown at the right of the title line in a stacked row -- a slider's
    // reading, a count.
    property string value: ""
    // Set by SettingsGroup: "single", "first", "middle" or "last".
    property string groupPos: "single"
    // A ↺ beside the title, for a setting changed here that can go back to
    // what the config file says.
    property bool resettable: false
    signal reset()
    default property alias control: slot.data

    readonly property real outer: 22
    readonly property real inner: 6

    topLeftRadius: row.groupPos === "single" || row.groupPos === "first" ? row.outer : row.inner
    topRightRadius: topLeftRadius
    bottomLeftRadius: row.groupPos === "single" || row.groupPos === "last" ? row.outer : row.inner
    bottomRightRadius: bottomLeftRadius

    color: rowHover.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer
    Behavior on color { ColorAnimation { duration: Theme.durShort } }

    width: parent ? parent.width : implicitWidth
    implicitWidth: 400
    implicitHeight: Math.max(60, layout.implicitHeight + 26)

    HoverHandler { id: rowHover }

    GridLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        columns: row.stacked ? 1 : 2
        columnSpacing: 16
        rowSpacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            TintBadge {
                visible: row.icon.length > 0
                icon: row.icon
                // Neutral: a badge on every row is a label, not a state; "on" shows
                // in the row's switch or slider.
                tint: Theme.textSecondary
                box: 32
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.title
                    visible: text.length > 0
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.description
                    visible: text.length > 0
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontText
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: row.stacked && row.value.length > 0
                text: row.value
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontText
            }

            Rectangle {
                visible: row.resettable
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: height / 2
                color: resetState.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F099B}"
                    size: Theme.iconTiny
                    color: Theme.textSecondary
                }

                StateLayer {
                    id: resetState
                    radius: height / 2
                    onTapped: row.reset()
                }
            }
        }

        Item {
            id: slot
            Layout.fillWidth: row.stacked
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitWidth: slot.children.length > 0 ? slot.children[0].implicitWidth : 0
            implicitHeight: slot.children.length > 0 ? slot.children[0].implicitHeight : 0
        }
    }
}
