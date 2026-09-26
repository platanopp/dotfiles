import QtQuick
import QtQuick.Layouts

// Settings -> Colour: saturation per display, and the tone of the whole
// picture. Saturation is NVIDIA's digital vibrance, per connector through
// nvibrant; temperature and brightness go through hyprsunset's colour matrix
// and gamma through a screen shader -- all three for every display at once.
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    readonly property var monitors: AppState.displayState.monitors || []
    readonly property var colour: AppState.displayState.colour
        || ({ temperature: 6000, brightness: 100, gamma: 1.0 })

    function shortName(m) {
        return (m.description || m.name)
            .replace(/ (Electric Company|Corporation|Technologies|Technology|Inc\.?|Co\.?,? ?Ltd\.?)/g, "")
    }

    // Warm to cool, with white where the neutral 6000 K falls on the track.
    Gradient {
        id: warmCool
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#ff9b40" }
        GradientStop { position: 0.54; color: "#f4f1ea" }
        GradientStop { position: 1.0; color: "#9fc4ff" }
    }

    SettingsGroup {
        width: parent.width
        title: "Saturation"
        tint: page.tint

        Repeater {
            model: page.monitors

            SettingsRow {
                id: vib
                required property var modelData
                stacked: true
                icon: "\u{F0301}"
                tint: page.tint
                title: page.shortName(vib.modelData)
                value: vibSlider.format(vibSlider.shown)

                SettingsSlider {
                    id: vibSlider
                    width: parent.width
                    tint: page.tint
                    from: 0
                    to: 1023
                    neutral: 0
                    value: AppState.displayState.vibrance
                           && AppState.displayState.vibrance[vib.modelData.name] !== undefined
                           ? AppState.displayState.vibrance[vib.modelData.name] : 0
                    format: v => Math.round(v / 1023 * 100) + "%"
                    onMoved: v => AppState.setDisplayVibrance(vib.modelData.name, v)
                }
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Tone"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F050F}"
            tint: page.tint
            title: "Temperature"
            value: tempSlider.format(tempSlider.shown)

            SettingsSlider {
                id: tempSlider
                width: parent.width
                tint: page.tint
                from: 2500
                to: 9000
                step: 50
                neutral: 6000
                gradient: warmCool
                value: page.colour.temperature
                format: v => Math.round(v / 50) * 50 + " K"
                onMoved: v => AppState.setDisplayTemperature(v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F00DF}"
            tint: page.tint
            title: "Brightness"
            value: brightSlider.format(brightSlider.shown)

            SettingsSlider {
                id: brightSlider
                width: parent.width
                tint: page.tint
                from: 50
                to: 150
                step: 1
                neutral: 100
                value: page.colour.brightness
                format: v => Math.round(v) + "%"
                onMoved: v => AppState.setDisplayBrightness(v)
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F0197}"
            tint: page.tint
            title: "Gamma"
            value: gammaSlider.format(gammaSlider.shown)

            SettingsSlider {
                id: gammaSlider
                width: parent.width
                tint: page.tint
                from: 0.6
                to: 1.6
                step: 0.01
                neutral: 1.0
                value: page.colour.gamma
                format: v => v.toFixed(2)
                onMoved: v => AppState.setDisplayGamma(v)
            }
        }

        SettingsRow {
            icon: "\u{F099B}"
            tint: page.tint
            title: "Neutral tone"

            PillButton {
                text: "Reset"
                onClicked: {
                    AppState.setDisplayTemperature(6000)
                    AppState.setDisplayBrightness(100)
                    AppState.setDisplayGamma(1.0)
                }
            }
        }
    }
}
