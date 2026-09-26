import QtQuick
import QtQuick.Layouts

// One quick toggle in the control panel.
//
// On is a filled tile in the accent with dark text on it, off is the plain
// surface. The accent here is a near-white grey, and the old version showed
// "on" as that grey at 16% over dark glass plus a 6px dot -- which read as
// barely different from off, and the dot cost the label its last few
// characters ("Do not dist…"). A fill cannot be mistaken, and it is the same
// on/off language the wallpaper picker's section switch speaks.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool active: false

    signal tapped()

    implicitHeight: 56
    radius: 16
    color: root.active ? Theme.accent : Theme.surfaceContainer

    readonly property color ink: root.active ? Theme.accentText : Theme.textPrimary

    scale: tileState.pressed ? 0.96 : 1.0
    transformOrigin: Item.Center

    Behavior on color { ColorAnimation { duration: Theme.durMedium } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 10

        IconGlyph {
            text: root.icon
            color: root.active ? Theme.accentText : Theme.textSecondary
            size: Theme.iconMedium
            Behavior on color { ColorAnimation { duration: Theme.durMedium } }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.label
                color: root.ink
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontMono
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
            }

            Text {
                Layout.fillWidth: true
                text: root.detail
                color: root.active ? Theme.alpha(Theme.accentText, 0.62) : Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontMono
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
            }
        }
    }

    StateLayer {
        id: tileState
        // Tinted with the text colour, so the hover shows on the filled tile
        // as well as on the empty one.
        tint: root.ink
        onTapped: root.tapped()
    }
}
