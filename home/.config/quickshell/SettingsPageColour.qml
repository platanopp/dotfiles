import QtQuick
import QtQuick.Layouts

// Settings -> Colour: saturation per display, and the tone of the whole
// picture. Saturation is NVIDIA's digital vibrance, set per connector through
// nvibrant; temperature and brightness go through hyprsunset's colour matrix,
// and gamma through a screen shader -- all three apply to every display at
// once, which is why they sit in a section of their own.
Column {
    id: page
    spacing: 28

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
        subtitle: "Digital vibrance through the NVIDIA driver, per display. 0% leaves colours as they come; more makes them punchier. Double-click a slider to go back to 0."

        Repeater {
            model: page.monitors

            SettingsRow {
                id: vib
                required property var modelData
                stacked: true
                title: page.shortName(vib.modelData)
                description: vib.modelData.name

                SettingsSlider {
                    width: parent.width
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
        subtitle: "For every display at once. The line on each track marks neutral, and a double-click goes back to it."

        SettingsRow {
            stacked: true
            title: "Colour temperature"
            description: "Warmer is easier on the eyes at night; neutral is 6000 K."

            SettingsSlider {
                width: parent.width
                from: 2500
                to: 9000
                neutral: 6000
                gradient: warmCool
                value: page.colour.temperature
                format: v => Math.round(v / 50) * 50 + " K"
                onMoved: v => AppState.setDisplayTemperature(Math.round(v / 50) * 50)
            }
        }

        SettingsRow {
            stacked: true
            title: "Brightness"
            description: "A flat multiplier on the picture, not the panel's backlight: it dims and lifts, but bends nothing."

            SettingsSlider {
                width: parent.width
                from: 50
                to: 150
                neutral: 100
                value: page.colour.brightness
                format: v => Math.round(v) + "%"
                onMoved: v => AppState.setDisplayBrightness(v)
            }
        }

        SettingsRow {
            stacked: true
            title: "Gamma"
            description: "Above 1.00 lifts the midtones while black stays black -- what makes a dark playfield readable."

            SettingsSlider {
                width: parent.width
                from: 0.6
                to: 1.6
                neutral: 1.0
                value: page.colour.gamma
                format: v => v.toFixed(2)
                onMoved: v => AppState.setDisplayGamma(v)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Reset"

        SettingsRow {
            title: "Back to neutral tone"
            description: "Temperature, brightness and gamma to where they started. Saturation is left as it is."

            PillButton {
                text: "Reset"
                icon: "\u{F099B}"
                onClicked: {
                    AppState.setDisplayTemperature(6000)
                    AppState.setDisplayBrightness(100)
                    AppState.setDisplayGamma(1.0)
                }
            }
        }
    }
}
