import QtQuick
import QtQuick.Layouts

// One setting: its badge, its name, and its control -- to the right, or
// underneath when `stacked` (a slider, a row of chips: anything that wants the
// card's full width). A description is allowed but kept to a short hint;
// the badge and the name are meant to carry the row.
//
// Rows sit in a SettingsGroup, which tells each one where it falls in the
// stack. The outer corners of a group are round and the corners where two
// rows meet are nearly square, so a group reads as one block cut into strips
// rather than as separate cards floating near each other.
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
                tint: row.tint
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
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.description
                    visible: text.length > 0
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontMono
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: row.stacked && row.value.length > 0
                text: row.value
                color: row.tint
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontMono
            }

            Rectangle {
                visible: row.resettable
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: resetState.hovered ? Theme.alpha(row.tint, 0.22) : Theme.alpha(row.tint, 0.1)

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F099B}"
                    size: Theme.iconTiny
                    color: row.tint
                }

                StateLayer {
                    id: resetState
                    radius: 14
                    tint: row.tint
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
