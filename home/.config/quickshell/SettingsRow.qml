import QtQuick
import QtQuick.Layouts

// One setting: a title, a line of explanation, and its control -- to the
// right, or underneath when `stacked` (a slider, a row of chips: anything
// that wants the card's full width).
//
// Rows sit in a SettingsGroup, which tells each one where it falls in the
// stack. The outer corners of a group are round and the corners where two
// rows meet are nearly square, so a group reads as one block cut into
// strips rather than as separate cards floating near each other.
Rectangle {
    id: row

    property string title: ""
    property string description: ""
    property bool stacked: false
    // Set by SettingsGroup: "single", "first", "middle" or "last".
    property string groupPos: "single"
    default property alias control: slot.data

    readonly property real outer: 20
    readonly property real inner: 6

    topLeftRadius: row.groupPos === "single" || row.groupPos === "first" ? row.outer : row.inner
    topRightRadius: topLeftRadius
    bottomLeftRadius: row.groupPos === "single" || row.groupPos === "last" ? row.outer : row.inner
    bottomRightRadius: bottomLeftRadius

    color: Theme.surfaceContainer
    width: parent ? parent.width : implicitWidth
    implicitWidth: 400
    implicitHeight: layout.implicitHeight + 32

    GridLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 18
        anchors.rightMargin: 16
        columns: row.stacked ? 1 : 2
        columnSpacing: 20
        rowSpacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

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
                font.pixelSize: 11
                font.family: Theme.fontMono
                wrapMode: Text.WordWrap
                lineHeight: 1.15
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
