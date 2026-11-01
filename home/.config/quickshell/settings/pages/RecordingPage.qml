import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Recording: how the screen is recorded. Kept in ShellSettings and read by
// Recorder.startRecording, so a change applies to the next recording.
Column {
    id: page
    spacing: 24

    // gpu-screen-recorder, looked for once as the page opens: without it
    // nothing records, and the page says what to install.
    property bool recorderFound: true

    Process {
        running: true
        command: ["sh", "-c", "command -v gpu-screen-recorder >/dev/null && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: page.recorderFound = text.trim() === "yes"
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Recorder"
        visible: !page.recorderFound

        SettingsRow {
            icon: "\u{F0026}"
            tint: Theme.warning
            title: "gpu-screen-recorder is not installed"
            description: "sudo pacman -S gpu-screen-recorder"
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Video"

        SettingsRow {
            stacked: true
            icon: "\u{F0A24}"
            title: "Resolution"
            description: "Scaled down, never up: a smaller monitor is recorded as it is"

            Segmented {
                options: [
                    { value: "native", label: "Native" },
                    { value: "1440", label: "1440p" },
                    { value: "1080", label: "1080p" },
                    { value: "720", label: "720p" }
                ]
                value: ShellSettings.recordResolution
                onPicked: v => ShellSettings.set("recordResolution", v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F04C5}"
            title: "Frame rate"

            Segmented {
                options: [
                    { value: 30, label: "30 fps" },
                    { value: 60, label: "60 fps" },
                    { value: 120, label: "120 fps" },
                    { value: 144, label: "144 fps" }
                ]
                value: ShellSettings.recordFps
                onPicked: v => ShellSettings.set("recordFps", v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F0435}"
            title: "Quality"
            description: "Higher is sharper in fast motion, and a bigger file"

            Segmented {
                options: [
                    { value: "medium", label: "Medium" },
                    { value: "high", label: "High" },
                    { value: "very_high", label: "Very high" },
                    { value: "ultra", label: "Ultra" }
                ]
                value: ShellSettings.recordQuality
                onPicked: v => ShellSettings.set("recordQuality", v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F022B}"
            title: "Format"
            description: ShellSettings.recordCodec === "hevc"
                         ? "About half the size; some apps and older phones cannot play it"
                         : "Plays everywhere: Discord, WhatsApp, any editor"

            Segmented {
                options: [
                    { value: "h264", label: "MP4 · H.264" },
                    { value: "hevc", label: "MP4 · HEVC" }
                ]
                value: ShellSettings.recordCodec
                onPicked: v => ShellSettings.set("recordCodec", v)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Sound and pointer"

        SettingsRow {
            stacked: true
            icon: "\u{F057E}"
            title: "Sound"
            description: ShellSettings.recordAudio === "both"
                         ? "The computer and the microphone, mixed into one track"
                         : ""

            Segmented {
                options: [
                    { value: "none", label: "None" },
                    { value: "system", label: "Computer" },
                    { value: "mic", label: "Microphone" },
                    { value: "both", label: "Both" }
                ]
                value: ShellSettings.recordAudio
                onPicked: v => ShellSettings.set("recordAudio", v)
            }
        }

        SettingsRow {
            icon: "\u{F01C0}"
            title: "Show the pointer"

            SettingsSwitch {
                checked: ShellSettings.recordCursor
                onToggled: c => ShellSettings.set("recordCursor", c)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Saving"

        SettingsRow {
            stacked: true
            icon: "\u{F024B}"
            title: "Folder"
            description: Recorder.recordingFolder.replace(Quickshell.env("HOME"), "~")
            // Back to ~/Videos/Recordings.
            resettable: ShellSettings.recordFolder.length > 0
            onReset: ShellSettings.set("recordFolder", "")

            Row {
                spacing: 8

                PillButton {
                    text: "Change…"
                    icon: "\u{F0770}"
                    onClicked: Recorder.chooseRecordingFolder()
                }

                PillButton {
                    text: "Open"
                    icon: "\u{F03CC}"
                    onClicked: {
                        Quickshell.execDetached(["mkdir", "-p", Recorder.recordingFolder])
                        Quickshell.execDetached(["xdg-open", Recorder.recordingFolder])
                    }
                }
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Record"

        SettingsRow {
            icon: Recorder.recording ? "\u{F04DB}" : "\u{F044B}"
            tint: Recorder.recording ? Theme.error : Theme.accent
            title: Recorder.recording ? "Recording  " + Recorder.recordingClock(Recorder.recordingSeconds)
                                      : "Record this screen"
            description: "Super+Shift+R, or the Record tile in the control panel"

            PillButton {
                text: Recorder.recording ? "Stop" : "Start"
                danger: Recorder.recording
                emphasis: !Recorder.recording
                available: page.recorderFound
                onClicked: Recorder.toggleRecording(Panels.focusedScreenName())
            }
        }
    }
}
