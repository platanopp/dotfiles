import QtQuick
import qs.config

// A key and what it does, for an overlay's footer: the keycap, then the
// action in muted text. Every overlay uses this one, set the way the widget
// picker set it first, so the hints read the same wherever they are. Rows
// of them are spaced 14px apart; arrow pairs are written with a space
// between the arrows ("← →").
Row {
    id: hint

    property string key: ""
    property string label: ""

    spacing: 6

    KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        key: hint.key
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: hint.label
        color: Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontText
    }
}
