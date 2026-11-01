import QtQuick
import qs.config

// Circular icon button with its hit area in place: bare glyphs on StateLayer's negative
// margins got clipped by `clip: true` parents.
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
