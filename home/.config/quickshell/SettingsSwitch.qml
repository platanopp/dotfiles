import QtQuick

// On or off. The track fills with the accent when on and the thumb carries a
// check, so the state reads without colour alone.
Rectangle {
    id: root

    property bool checked: false
    property bool available: true
    property color tint: Theme.accent
    readonly property color onTint: Theme.luminance(root.tint) > 0.5 ? Theme.background : "#ffffff"
    signal toggled(bool checked)

    implicitWidth: 50
    implicitHeight: 28
    radius: height / 2
    opacity: root.available ? 1 : 0.45
    color: root.checked ? root.tint : Theme.alpha(Theme.background, 0.45)
    border.width: root.checked ? 0 : 1
    border.color: Theme.outline

    Behavior on color { ColorAnimation { duration: Theme.durMedium } }

    Rectangle {
        id: thumb
        width: root.height - 8
        height: width
        radius: width / 2
        y: 4
        x: root.checked ? root.width - width - 4 : 4
        color: root.checked ? root.onTint : Theme.textSecondary

        Behavior on x { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.durMedium } }

        IconGlyph {
            anchors.centerIn: parent
            visible: root.checked
            text: "\u{F012C}"
            size: Theme.iconTiny
            color: root.tint
        }
    }

    StateLayer {
        radius: root.radius
        interactive: root.available
        onTapped: root.toggled(!root.checked)
    }
}
