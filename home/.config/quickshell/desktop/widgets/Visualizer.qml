import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.config
import qs.desktop
import qs.services

// The media panel's spectrum on its own: mirrored bars, low notes at the centre, in the
// album colour. Listens only while a player plays and the desktop can be seen, since
// capturing audio is the costly part.
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

    readonly property int count: 56

    function level(i) {
        if (!root.listening) return 0
        var b = Spectrum.bands
        var half = root.count / 2
        var band = Math.round((i < half ? half - 1 - i : i - half) * b.length / half)
        return band >= 0 && band < b.length ? b[band] : 0
    }

    // The pill's two lines: the title, the artist beside it in grey. Only
    // while something plays; with nothing, the resting bars are the widget.
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        anchors.topMargin: 16
        spacing: 8
        visible: root.anyPlaying

        Text {
            Layout.maximumWidth: parent.width * 0.6
            text: root.bar ? root.bar.trackTitle : ""
            color: Theme.textPrimary
            font.pixelSize: 12
            font.bold: true
            font.family: Theme.fontText
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: root.bar ? root.bar.trackArtist : ""
            color: Theme.textSecondary
            font.pixelSize: 11
            font.family: Theme.fontText
            elide: Text.ElideRight
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        spacing: 3

        Repeater {
            model: root.count

            // Drawn at the helper's own rate (~43 a second), already smoothed. A per-bar
            // Behavior never settled between frames, so the whole desktop layer redrew at the
            // monitor's rate while music played.
            Rectangle {
                required property int index
                readonly property real level: root.level(index)

                anchors.bottom: parent.bottom
                width: 3
                height: 2 + level * 80
                radius: 1.5
                // At rest the bars are the track colour: the album's colour is
                // for the music, and with none playing they mark nothing.
                color: root.listening ? Theme.alpha(AlbumColors.accent, 0.35 + level * 0.6) : Theme.track
            }
        }
    }
}
