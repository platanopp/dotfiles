import QtQuick
import QtQuick.Layouts

// A setting with many possible values -- a display's resolutions, its refresh
// rates -- shown folded: the row carries only the current value, and a tap
// opens the choices underneath, inside the same card. Picking one folds it
// again. A long list of chips on permanent display was the noisiest thing on
// the page.
//
// Built like a SettingsRow (same corners, same badge and title) so it sits in
// a SettingsGroup among them.
Rectangle {
    id: row

    property string title: ""
    property string icon: ""
    property var options: []      // [{ value, label }]
    property var value
    signal picked(var value)

    // Set by SettingsGroup, as for SettingsRow.
    property string groupPos: "single"
    property bool open: false

    readonly property string currentLabel: {
        for (var i = 0; i < row.options.length; i++)
            if (row.options[i].value === row.value) return row.options[i].label
        return "—"
    }

    readonly property real outer: 22
    readonly property real inner: 6
    topLeftRadius: row.groupPos === "single" || row.groupPos === "first" ? row.outer : row.inner
    topRightRadius: topLeftRadius
    bottomLeftRadius: row.groupPos === "single" || row.groupPos === "last" ? row.outer : row.inner
    bottomRightRadius: bottomLeftRadius

    color: headHover.hovered && !row.open ? Theme.surfaceContainerHigh : Theme.surfaceContainer
    Behavior on color { ColorAnimation { duration: Theme.durShort } }

    width: parent ? parent.width : 400
    implicitHeight: 60 + (row.open ? choices.implicitHeight + 16 : 0)
    height: implicitHeight
    clip: true

    Behavior on implicitHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }

    // The folded line: badge, title, and the value with a chevron.
    Item {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 60

        HoverHandler { id: headHover }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            TintBadge {
                visible: row.icon.length > 0
                icon: row.icon
                box: 32
            }

            Text {
                Layout.fillWidth: true
                text: row.title
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontMono
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredHeight: 32
                Layout.preferredWidth: pillRow.implicitWidth + 26
                radius: 16
                color: Theme.alpha(Theme.background, 0.45)

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.currentLabel
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.bold: true
                        font.family: Theme.fontMono
                    }

                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F0140}"
                        size: Theme.iconSmall
                        color: Theme.textSecondary
                        rotation: row.open ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        StateLayer {
            radius: 0
            color: "transparent"
            onTapped: row.open = !row.open
        }
    }

    // The choices, in a grid so a long list stays short.
    Grid {
        id: choices
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        columns: Math.max(1, Math.floor((width + spacing) / (132 + spacing)))
        spacing: 6
        opacity: row.open ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }

        Repeater {
            model: row.options

            Rectangle {
                id: choice
                required property var modelData
                readonly property bool chosen: choice.modelData.value === row.value

                width: (choices.width - choices.spacing * (choices.columns - 1)) / choices.columns
                height: 34
                radius: 17
                color: choice.chosen ? Theme.accent
                     : choiceState.hovered ? Theme.surfaceContainerHigh
                     : Theme.alpha(Theme.background, 0.35)

                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: choice.chosen
                        text: "\u{F012C}"
                        size: Theme.iconTiny
                        color: Theme.accentText
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: choice.modelData.label
                        font.pixelSize: 11
                        font.bold: choice.chosen
                        font.family: Theme.fontMono
                        color: choice.chosen ? Theme.accentText : Theme.textSecondary
                    }
                }

                StateLayer {
                    id: choiceState
                    radius: choice.radius
                    interactive: !choice.chosen && row.open
                    onTapped: {
                        row.open = false
                        row.picked(choice.modelData.value)
                    }
                }
            }
        }
    }
}
