import QtQuick
import qs.config

// A key as a small keycap: the mono legend on a raised fill with a hairline edge. The shell's only
// keycap; the keybinds sheet draws it a size up through capHeight and fontSize.
Rectangle {
    id: cap

    property string key: ""
    property int capHeight: 18
    property int fontSize: 10

    width: Math.max(cap.capHeight, capText.implicitWidth + 10)
    height: cap.capHeight
    radius: Theme.radiusSmall
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outline

    Text {
        id: capText
        anchors.centerIn: parent
        text: cap.key
        color: Theme.textSecondary
        font.pixelSize: cap.fontSize
        font.family: Theme.fontMono
    }
}
