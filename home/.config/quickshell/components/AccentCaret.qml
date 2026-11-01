import QtQuick
import qs.config

// The overlays' search caret, in the accent: the field is the one active thing there. A TextInput
// cursorDelegate that blinks like the stock caret but holds solid briefly after each keystroke.
Rectangle {
    id: caret

    width: 2
    height: parent ? parent.cursorRectangle.height : 0
    radius: 1
    color: Theme.accent

    Behavior on color { ColorAnimation { duration: Theme.durMedium } }

    SequentialAnimation on opacity {
        id: blink
        running: caret.visible
        loops: Animation.Infinite
        PauseAnimation { duration: 500 }
        NumberAnimation { to: 0; duration: Theme.durShort }
        PauseAnimation { duration: 400 }
        NumberAnimation { to: 1; duration: Theme.durShort }
    }

    Connections {
        target: caret.parent
        ignoreUnknownSignals: true
        function onCursorPositionChanged() {
            caret.opacity = 1
            blink.restart()
        }
    }
}
