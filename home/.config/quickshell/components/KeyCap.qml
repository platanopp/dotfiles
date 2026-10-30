import QtQuick
import qs.config

// A key, drawn as a small keycap: its legend in the mono face, on a raised
// fill with a hairline edge. The one keycap of the shell -- the overlays'
// key hints (KeyHint) and the keybinds sheet's combinations are all this.
// The sheet draws its combinations a size up, through capHeight and
// fontSize; everywhere else it is left as it is.
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
