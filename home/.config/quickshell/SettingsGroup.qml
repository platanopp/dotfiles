import QtQuick

// A section of the Settings window: a heading, a line under it, and a stack
// of SettingsRows that it tells where they sit, so the stack gets round outer
// corners and near-square seams (see SettingsRow).
//
// Recounted whenever a row is shown or hidden, so a row that only applies
// sometimes does not leave the group with a square corner at an open end.
Column {
    id: group

    property string title: ""
    property string subtitle: ""
    property color tint: Theme.textPrimary
    default property alias rows: stack.data

    spacing: 10

    function place() {
        var shown = []
        for (var i = 0; i < stack.children.length; i++) {
            var c = stack.children[i]
            if (c.visible && c.groupPos !== undefined) shown.push(c)
        }
        for (var j = 0; j < shown.length; j++) {
            shown[j].groupPos = shown.length === 1 ? "single"
                : j === 0 ? "first"
                : j === shown.length - 1 ? "last"
                : "middle"
        }
    }

    Column {
        width: parent.width
        spacing: 3
        visible: group.title.length > 0 || group.subtitle.length > 0

        Row {
            visible: group.title.length > 0
            spacing: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: group.tint
            }

            Text {
                text: group.title
                color: Theme.textSecondary
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.4
                font.capitalization: Font.AllUppercase
                font.family: Theme.fontMono
            }
        }

        Text {
            width: parent.width
            visible: group.subtitle.length > 0
            text: group.subtitle
            color: Theme.textMuted
            font.pixelSize: 11
            font.family: Theme.fontMono
            wrapMode: Text.WordWrap
        }
    }

    Column {
        id: stack
        width: parent.width
        spacing: 3

        onVisibleChildrenChanged: group.place()
        Component.onCompleted: group.place()
    }
}
