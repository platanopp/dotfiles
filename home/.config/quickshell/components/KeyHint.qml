import QtQuick
import qs.config

// A key and what it does, for an overlay's footer; every overlay uses it. Rows are spaced 14px
// apart, and arrow pairs are written with a space ("← →").
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
