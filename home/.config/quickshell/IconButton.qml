import QtQuick

// Circular icon button with a hit area sized in place. Bare glyphs relying on
// StateLayer's negative margins get their target clipped by any parent with
// clip: true, and crowd the edge of a panel.
Rectangle {
    id: root

    property string icon: ""
    property int size: 26
    property int glyphSize: Theme.iconMedium
    property color iconColor: Theme.textSecondary
    property bool interactive: true

    signal tapped()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: "transparent"

    IconGlyph {
        anchors.centerIn: parent
        text: root.icon
        color: root.interactive ? root.iconColor : Theme.textMuted
        size: root.glyphSize
    }

    StateLayer {
        interactive: root.interactive
        onTapped: root.tapped()
    }
}
