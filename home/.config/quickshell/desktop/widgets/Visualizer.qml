import QtQuick
import Quickshell.Services.Mpris
import qs.config
import qs.desktop
import qs.services

// The music as a spectrum, low notes in the middle, in the accent: it is the
// live part of the desktop. It took cava's place, and like cava it shows the
// speakers -- but it only listens while a player is playing and the desktop
// can be seen, since capturing the audio is the costly part (Spectrum).
WidgetCard {
    id: root

    readonly property bool anyPlaying: {
        var list = Mpris.players.values
        for (var i = 0; i < list.length; i++)
            if (list[i].isPlaying) return true
        return false
    }

    readonly property bool listening: root.live && root.anyPlaying
    onListeningChanged: root.listening ? Spectrum.subscribe() : Spectrum.unsubscribe()
    Component.onCompleted: if (root.listening) Spectrum.subscribe()
    Component.onDestruction: if (root.listening) Spectrum.unsubscribe()

    readonly property int count: 40

    function level(i) {
        if (!root.listening) return 0
        var b = Spectrum.bands
        var half = root.count / 2
        var band = Math.round((i < half ? half - 1 - i : i - half) * b.length / half)
        return band >= 0 && band < b.length ? b[band] : 0
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        anchors.topMargin: 16
        spacing: 2

        Text {
            width: parent.width
            text: root.anyPlaying && root.bar && root.bar.trackTitle.length > 0
                  ? root.bar.trackTitle + (root.bar.trackArtist.length > 0 ? "  ·  " + root.bar.trackArtist : "")
                  : "Nothing playing"
            color: root.anyPlaying ? Theme.textSecondary : Theme.textPrimary
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.family: Theme.fontText
            elide: Text.ElideRight
        }

        Text {
            visible: !root.anyPlaying
            text: "Play something and the bars move with it."
            color: Theme.textMuted
            font.pixelSize: 12
            font.family: Theme.fontText
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        spacing: 4

        Repeater {
            model: root.count

            Rectangle {
                required property int index
                readonly property real level: root.level(index)
                // Not readonly: the Behavior smooths between the helper's frames.
                property real len: 4 + level * 96

                anchors.bottom: parent.bottom
                width: 4
                height: len
                radius: width / 2
                // At rest the bars are the track colour: the accent is for
                // the music, and with none playing they mark nothing.
                color: root.listening ? Theme.alpha(Theme.accent, 0.4 + level * 0.6) : Theme.track

                Behavior on len {
                    NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                }
            }
        }
    }
}
