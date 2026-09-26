import QtQuick

// An icon on a rounded square of its own colour -- the Settings window's way
// of telling pages and settings apart at a glance, the way a phone's settings
// list does, without a line of text to do it.
Rectangle {
    id: root

    property string icon: ""
    property color tint: Theme.accent
    property int box: 30

    width: root.box
    height: root.box
    radius: Math.round(root.box * 0.32)
    color: Theme.alpha(root.tint, 0.18)

    IconGlyph {
        anchors.centerIn: parent
        text: root.icon
        color: root.tint
        size: root.box >= 40 ? Theme.iconLarge : root.box >= 28 ? Theme.iconMedium : Theme.iconSmall
    }
}
