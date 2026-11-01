import QtQuick
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Sound: outputs, inputs and per-app levels. Output and per-app use the bar's audio
// panel functions; the input side is this page's own (Audio.audioSources, micVolume).
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

        // With All outputs on: each device's own level under the master. The combined output is not
        // listed (PipeWire files it under filters).
        Repeater {
            model: Audio.allOutputs ? Audio.audioSinks : []

            SettingsRow {
                id: device
                required property var modelData
                stacked: true
                icon: "\u{F04C3}"
                title: device.modelData.name
                value: Math.round(deviceSlider.shown) + "%"

                SettingsSlider {
                    id: deviceSlider
                    width: parent.width
                    from: 0; to: 150; step: 1
                    neutral: 100
                    value: device.modelData.volume
                    format: v => Math.round(v) + "%"
                    onMoved: v => Audio.setSinkVolume(device.modelData.id, v)
                }
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
