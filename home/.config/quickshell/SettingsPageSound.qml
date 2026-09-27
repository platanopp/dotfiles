import QtQuick
import QtQuick.Layouts

// Settings -> Sound: where sound goes out and comes in, how loud each is, and
// how loud each application is. The output side and the per-application
// levels are the same functions the bar's audio panel uses; the input side is
// the Settings window's own (AppState.audioSources, micVolume).
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    Component.onCompleted: {
        AppState.refreshAudioSinks()
        AppState.refreshAudioSources()
        AppState.watchAudioStreams()
    }
    Component.onDestruction: AppState.unwatchAudioStreams()

    function defaultOf(list) {
        for (var i = 0; i < list.length; i++) if (list[i].isDefault) return list[i].id
        return ""
    }

    SettingsGroup {
        width: parent.width
        title: "Output"

        SettingsRow {
            stacked: true
            icon: AppState.volumePercent === 0 ? "\u{F075F}" : "\u{F057E}"
            title: "Volume"
            value: Math.round(outSlider.shown) + "%"

            SettingsSlider {
                id: outSlider
                width: parent.width
                from: 0; to: 100; step: 1
                value: AppState.volumePercent
                format: v => Math.round(v) + "%"
                onMoved: v => AppState.setVolume(v)
            }
        }

        SelectRow {
            icon: "\u{F04C3}"
            title: "Device"
            visible: AppState.audioSinks.length > 0
            options: AppState.audioSinks.map(s => ({ value: s.id, label: s.name }))
            value: page.defaultOf(AppState.audioSinks)
            onPicked: v => AppState.setDefaultSink(v)
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Input"

        SettingsRow {
            icon: AppState.micMuted ? "\u{F036D}" : "\u{F036C}"
            title: "Microphone"

            SettingsSwitch {
                checked: !AppState.micMuted
                onToggled: AppState.toggleMicMute()
            }
        }

        SettingsRow {
            stacked: true
            visible: !AppState.micMuted
            icon: "\u{F036C}"
            title: "Input level"
            value: Math.round(micSlider.shown) + "%"

            SettingsSlider {
                id: micSlider
                width: parent.width
                from: 0; to: 150; step: 1
                neutral: 100
                value: AppState.micVolume
                format: v => Math.round(v) + "%"
                onMoved: v => AppState.setMicVolume(v)
            }
        }

        SelectRow {
            icon: "\u{F036F}"
            title: "Device"
            visible: AppState.audioSources.length > 0
            options: AppState.audioSources.map(s => ({ value: s.id, label: s.name }))
            value: page.defaultOf(AppState.audioSources)
            onPicked: v => AppState.setDefaultSource(v)
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Applications"
        visible: AppState.audioStreams.length > 0

        Repeater {
            model: AppState.audioStreams

            SettingsRow {
                id: app
                required property var modelData
                stacked: true
                icon: "\u{F075A}"
                title: AppState.streamName(app.modelData.name)
                value: Math.round(appSlider.shown) + "%"

                SettingsSlider {
                    id: appSlider
                    width: parent.width
                    from: 0; to: 150; step: 1
                    neutral: 100
                    value: app.modelData.volume
                    format: v => Math.round(v) + "%"
                    onMoved: v => AppState.setStreamVolume(app.modelData.id, v)
                }
            }
        }
    }
}
