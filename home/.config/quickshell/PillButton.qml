import QtQuick

// A plain action in the Settings window -- "Reset", "Keep", "Revert".
// `emphasis` fills it in the accent for the one action a card is asking for;
// `danger` tints it red.
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property bool emphasis: false
    property bool danger: false
    property bool available: true
    signal clicked()

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 34
    radius: height / 2
    opacity: root.available ? 1 : 0.45
    color: root.emphasis ? Theme.accent
         : root.danger ? Theme.alpha(Theme.error, 0.18)
         : Theme.surfaceContainerHigh

    Behavior on color { ColorAnimation { duration: Theme.durShort } }

    readonly property color ink: root.emphasis ? Theme.accentText
                               : root.danger ? Theme.error
                               : Theme.textPrimary

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        IconGlyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon.length > 0
            text: root.icon
            size: Theme.iconSmall
            color: root.ink
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: 11
            font.bold: root.emphasis
            font.family: Theme.fontMono
            color: root.ink
        }
    }

    StateLayer {
        radius: root.radius
        tint: root.ink
        interactive: root.available
        onTapped: root.clicked()
    }
}
