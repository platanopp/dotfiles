import QtQuick
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Sound: where sound goes out and comes in, how loud each is, and
// how loud each application is. The output side and the per-application
// levels are the same functions the bar's audio panel uses; the input side is
// the Settings window's own (Audio.audioSources, micVolume).
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    Component.onCompleted: {
        Audio.refreshAudioSinks()
        Audio.refreshAudioSources()
        Audio.watchAudioStreams()
    }
    Component.onDestruction: Audio.unwatchAudioStreams()

    function defaultOf(list) {
        for (var i = 0; i < list.length; i++) if (list[i].isDefault) return list[i].id
        return ""
    }

    SettingsGroup {
        width: parent.width
        title: "Output"

        SettingsRow {
            stacked: true
            icon: Audio.volumePercent === 0 ? "\u{F075F}" : "\u{F057E}"
            title: "Volume"
            value: Math.round(outSlider.shown) + "%"

            SettingsSlider {
                id: outSlider
                width: parent.width
                from: 0; to: 100; step: 1
                value: Audio.volumePercent
                format: v => Math.round(v) + "%"
                onMoved: v => Audio.setVolume(v)
            }
        }

        SettingsRow {
            icon: "\u{F0D38}"
            title: "All outputs"
            description: "Play through every device at once"

            SettingsSwitch {
                checked: Audio.allOutputs
                onToggled: c => Audio.setAllOutputs(c)
            }
        }

        // While everything plays everywhere, there is no one device to pick.
        SelectRow {
            icon: "\u{F04C3}"
            title: "Device"
            visible: Audio.audioSinks.length > 0 && !Audio.allOutputs
            options: Audio.audioSinks.map(s => ({ value: s.id, label: s.name }))
            value: page.defaultOf(Audio.audioSinks)
            onPicked: v => Audio.setDefaultSink(v)
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Input"

        SettingsRow {
            icon: Audio.micMuted ? "\u{F036D}" : "\u{F036C}"
            title: "Microphone"

            SettingsSwitch {
                checked: !Audio.micMuted
                onToggled: Audio.toggleMicMute()
            }
        }

        SettingsRow {
            stacked: true
            visible: !Audio.micMuted
            icon: "\u{F036C}"
            title: "Input level"
            value: Math.round(micSlider.shown) + "%"

            SettingsSlider {
                id: micSlider
                width: parent.width
                from: 0; to: 150; step: 1
                neutral: 100
                value: Audio.micVolume
                format: v => Math.round(v) + "%"
                onMoved: v => Audio.setMicVolume(v)
            }
        }

        SelectRow {
            icon: "\u{F036F}"
            title: "Device"
            visible: Audio.audioSources.length > 0
            options: Audio.audioSources.map(s => ({ value: s.id, label: s.name }))
            value: page.defaultOf(Audio.audioSources)
            onPicked: v => Audio.setDefaultSource(v)
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Applications"
        visible: Audio.audioStreams.length > 0

        Repeater {
            model: Audio.audioStreams

            SettingsRow {
                id: app
                required property var modelData
                stacked: true
                icon: "\u{F075A}"
                title: Audio.streamName(app.modelData.name)
                value: Math.round(appSlider.shown) + "%"

                SettingsSlider {
                    id: appSlider
                    width: parent.width
                    from: 0; to: 150; step: 1
                    neutral: 100
                    value: app.modelData.volume
                    format: v => Math.round(v) + "%"
                    onMoved: v => Audio.setStreamVolume(app.modelData.id, v)
                }
            }
        }
    }
}
