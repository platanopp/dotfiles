import QtQuick
import QtQuick.Layouts

// One quick-setting toggle: name on top, live state underneath.
//
// The four of these were copies of the same forty lines, and each filled
// completely with the accent when on. The accent is a light grey, so "on"
// meant a near-white block -- four of them shouted over everything else in
// the panel. Here "on" is a tint of the accent plus a coloured icon and dot,
// which reads clearly without taking the panel over.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    // What the toggle is actually doing right now: the network name, how many
    // devices are connected. Saves opening a panel to find out.
    property string detail: ""
    property bool active: false

    signal tapped()

    implicitHeight: 60
    radius: 16
    color: root.active ? Theme.alpha(AppState.themeAccent, 0.16) : Theme.surfaceContainer

    scale: tileState.pressed ? 0.96 : 1.0
    transformOrigin: Item.Center

    Behavior on color { ColorAnimation { duration: Theme.durShort } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 9
        anchors.bottomMargin: 9
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: root.icon
                color: root.active ? AppState.themeAccent : Theme.textSecondary
                size: Theme.iconMedium
            }

            Text {
                text: root.label
                color: Theme.textPrimary
                font.pixelSize: 12
                font.bold: root.active
                font.family: Theme.fontMono
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // A dot as well as the colour: at a glance across the panel, a
            // fill this subtle is easy to miss on its own.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: AppState.themeAccent
                opacity: root.active ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
            }
        }

        Text {
            text: root.detail
            color: root.active ? Theme.textSecondary : Theme.textMuted
            font.pixelSize: 10
            font.family: Theme.fontMono
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    // The fill is a tint now rather than a solid accent, so a light tint reads
    // in both states and no longer has to flip with it.
    StateLayer {
        id: tileState
        onTapped: root.tapped()
    }
}
