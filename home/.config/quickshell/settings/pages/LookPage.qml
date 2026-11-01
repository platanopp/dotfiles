import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Hyprland -> Look: gaps, borders, corners, transparency and effects, through
// hypr_settings.py. The preview draws two windows over your wallpaper with the sliders'
// values, the one being dragged included.
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    // Preview
    Rectangle {
        id: preview
        width: parent.width
        height: 210
        radius: Theme.radiusXLarge
        color: Theme.surfaceContainer

        // Scaled from a 1080-tall screen into the preview, then doubled:
        // at true scale a 15px gap is two pixels, and nothing reads.
        readonly property real k: (mock.height / 1080) * 2

        readonly property real gapIn: gapInSlider.shown * preview.k
        readonly property real gapOut: gapOutSlider.shown * preview.k
        readonly property real gapTop: gapTopSlider.shown * preview.k
        // Not "border": a Rectangle has one, and redeclaring it fails the page.
        readonly property real borderPx: borderSlider.shown
        readonly property real round: roundSlider.shown * preview.k
        readonly property real focusedAlpha: activeSlider.shown
        readonly property real otherAlpha: inactiveSlider.shown
        readonly property string layout: Hypr.optionValue("layout", "dwindle")

        ClippingRectangle {
            id: mock
            anchors.fill: parent
            anchors.margins: 12
            radius: Theme.radiusMedium
            color: Theme.background

            Image {
                anchors.fill: parent
                source: Wallpaper.wallpaperStill.length > 0 ? "file://" + Wallpaper.wallpaperStill : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 800
            }

            // Laid out as the chosen layout would: dwindle halves the screen, master favours the
            // first, scrolling runs off the right.
            Repeater {
                model: 2

                Item {
                    id: win
                    required property int index
                    readonly property bool focused: win.index === 0

                    readonly property real areaX: preview.gapOut
                    readonly property real areaW: mock.width - preview.gapOut * 2
                    readonly property real share: preview.layout === "master" ? 0.62
                                                : preview.layout === "scrolling" ? 0.7 : 0.5

                    x: win.index === 0 ? win.areaX + preview.gapIn
                                       : win.areaX + win.areaW * win.share + preview.gapIn
                    y: preview.gapTop + preview.gapIn
                    width: (win.index === 0 ? win.areaW * win.share
                                            : preview.layout === "scrolling" ? win.areaW * win.share
                                            : win.areaW * (1 - win.share)) - preview.gapIn * 2
                    height: mock.height - preview.gapTop - preview.gapOut - preview.gapIn * 2

                    Behavior on y { Elastic {} }
                    Behavior on height { Elastic {} }

                    Behavior on x { Elastic {} }
                    Behavior on width { Elastic {} }

                    RectangularShadow {
                        anchors.fill: parent
                        visible: Hypr.optionValue("shadow", true)
                        radius: preview.round
                        blur: 14
                        offset.y: 3
                        color: Theme.alpha(Theme.shadow, 0.5)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: preview.round
                        color: Theme.alpha(Theme.background, win.focused ? preview.focusedAlpha : preview.otherAlpha)
                        border.width: preview.borderPx
                        border.color: win.focused ? page.tint : Theme.alpha(Theme.foreground, 0.25)

                        // A stand-in for content, so the window reads as one.
                        Column {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 12 + preview.borderPx
                            spacing: 6

                            Repeater {
                                model: [0.55, 0.8, 0.4, 0.65]
                                Rectangle {
                                    required property real modelData
                                    width: (win.width - 24) * modelData
                                    height: 5
                                    radius: 2.5
                                    color: Theme.alpha(Theme.foreground, 0.22)
                                }
                            }
                        }

                        // dim_inactive, over the window that is not focused.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            visible: !win.focused && Hypr.optionValue("dim_inactive", false)
                            color: Theme.alpha(Theme.shadow, 0.35)
                        }
                    }
                }
            }
        }
    }

    // Spacing
    SettingsGroup {
        width: parent.width
        title: "Spacing"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F11D9}"
            tint: page.tint
            title: "Between windows"
            value: Math.round(gapInSlider.shown) + " px"
            resettable: Hypr.option("gaps_in").overridden
            onReset: Hypr.resetHypr("gaps_in")

            SettingsSlider {
                id: gapInSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 40; step: 1
                value: Hypr.optionValue("gaps_in", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => Hypr.setHypr("gaps_in", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F00CE}"
            tint: page.tint
            title: "Sides and bottom"
            value: Math.round(gapOutSlider.shown) + " px"
            resettable: Hypr.option("gaps_out").overridden
            onReset: Hypr.resetHypr("gaps_out")

            SettingsSlider {
                id: gapOutSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 80; step: 1
                value: Hypr.optionValue("gaps_out", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => Hypr.setHypr("gaps_out", Math.round(v))
            }
        }

        // The top edge apart: the bar lives in it, and the pills follow it.
        SettingsRow {
            stacked: true
            icon: "\u{F0143}"
            tint: page.tint
            title: "Top"
            value: Math.round(gapTopSlider.shown) + " px"
            resettable: Hypr.option("gaps_top").overridden
            onReset: Hypr.resetHypr("gaps_top")

            SettingsSlider {
                id: gapTopSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 80; step: 1
                value: Hypr.optionValue("gaps_top", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => Hypr.setHypr("gaps_top", Math.round(v))
            }
        }

        SettingsRow {
            visible: Hypr.optionValue("gaps_top", 0) !== Hypr.optionValue("gaps_out", 0)
            icon: "\u{F0337}"
            tint: page.tint
            title: "Same on every edge"

            PillButton {
                text: "Match top"
                onClicked: Hypr.setHypr("gaps_top", Math.round(gapOutSlider.value))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F00C7}"
            tint: page.tint
            title: "Border"
            value: Math.round(borderSlider.shown) + " px"
            resettable: Hypr.option("border_size").overridden
            onReset: Hypr.resetHypr("border_size")

            SettingsSlider {
                id: borderSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 8; step: 1
                value: Hypr.optionValue("border_size", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => Hypr.setHypr("border_size", Math.round(v))
            }
        }
    }

    // Shape
    SettingsGroup {
        width: parent.width
        title: "Shape"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F0607}"
            tint: page.tint
            title: "Corner rounding"
            value: Math.round(roundSlider.shown) + " px"
            resettable: Hypr.option("rounding").overridden
            onReset: Hypr.resetHypr("rounding")

            SettingsSlider {
                id: roundSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 40; step: 1
                value: Hypr.optionValue("rounding", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => Hypr.setHypr("rounding", Math.round(v))
            }
        }

        SettingsRow {
            icon: "\u{F0A1D}"
            tint: page.tint
            title: "Layout"
            resettable: Hypr.option("layout").overridden
            onReset: Hypr.resetHypr("layout")

            Segmented {
                tint: page.tint
                options: [
                    { value: "dwindle", label: "Dwindle" },
                    { value: "master", label: "Master" },
                    { value: "scrolling", label: "Scrolling" }
                ]
                value: Hypr.optionValue("layout", "dwindle")
                onPicked: v => Hypr.setHypr("layout", v)
            }
        }
    }

    // Transparency
    SettingsGroup {
        width: parent.width
        title: "Transparency"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F05CC}"
            tint: page.tint
            title: "Focused window"
            value: Math.round(activeSlider.shown * 100) + "%"
            resettable: Hypr.option("active_opacity").overridden
            onReset: Hypr.resetHypr("active_opacity")

            SettingsSlider {
                id: activeSlider
                width: parent.width
                tint: page.tint
                from: 0.4; to: 1.0; step: 0.01
                value: Hypr.optionValue("active_opacity", 1)
                format: v => Math.round(v * 100) + "%"
                onMoved: v => Hypr.setHypr("active_opacity", v.toFixed(2))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F06D0}"
            tint: page.tint
            title: "Other windows"
            value: Math.round(inactiveSlider.shown * 100) + "%"
            resettable: Hypr.option("inactive_opacity").overridden
            onReset: Hypr.resetHypr("inactive_opacity")

            SettingsSlider {
                id: inactiveSlider
                width: parent.width
                tint: page.tint
                from: 0.2; to: 1.0; step: 0.01
                value: Hypr.optionValue("inactive_opacity", 1)
                format: v => Math.round(v * 100) + "%"
                onMoved: v => Hypr.setHypr("inactive_opacity", v.toFixed(2))
            }
        }

        SettingsRow {
            icon: "\u{F00DD}"
            tint: page.tint
            title: "Dim other windows"
            resettable: Hypr.option("dim_inactive").overridden
            onReset: Hypr.resetHypr("dim_inactive")

            SettingsSwitch {
                tint: page.tint
                checked: Hypr.optionValue("dim_inactive", false)
                onToggled: c => Hypr.setHypr("dim_inactive", c)
            }
        }
    }

    // Effects
    SettingsGroup {
        width: parent.width
        title: "Effects"
        tint: page.tint

        SettingsRow {
            icon: "\u{F00B5}"
            tint: page.tint
            title: "Blur"
            resettable: Hypr.option("blur").overridden
            onReset: Hypr.resetHypr("blur")

            SettingsSwitch {
                tint: page.tint
                checked: Hypr.optionValue("blur", true)
                onToggled: c => Hypr.setHypr("blur", c)
            }
        }

        SettingsRow {
            stacked: true
            visible: Hypr.optionValue("blur", true)
            icon: "\u{F00B5}"
            tint: page.tint
            title: "Blur size"
            value: Math.round(blurSizeSlider.shown)
            resettable: Hypr.option("blur_size").overridden
            onReset: Hypr.resetHypr("blur_size")

            SettingsSlider {
                id: blurSizeSlider
                width: parent.width
                tint: page.tint
                from: 1; to: 16; step: 1
                value: Hypr.optionValue("blur_size", 5)
                onMoved: v => Hypr.setHypr("blur_size", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            visible: Hypr.optionValue("blur", true)
            icon: "\u{F00B5}"
            tint: page.tint
            title: "Blur passes"
            value: Math.round(blurPassSlider.shown)
            resettable: Hypr.option("blur_passes").overridden
            onReset: Hypr.resetHypr("blur_passes")

            SettingsSlider {
                id: blurPassSlider
                width: parent.width
                tint: page.tint
                from: 1; to: 6; step: 1
                value: Hypr.optionValue("blur_passes", 3)
                onMoved: v => Hypr.setHypr("blur_passes", Math.round(v))
            }
        }

        SettingsRow {
            icon: "\u{F0637}"
            tint: page.tint
            title: "Shadows"
            resettable: Hypr.option("shadow").overridden
            onReset: Hypr.resetHypr("shadow")

            SettingsSwitch {
                tint: page.tint
                checked: Hypr.optionValue("shadow", true)
                onToggled: c => Hypr.setHypr("shadow", c)
            }
        }

        SettingsRow {
            icon: "\u{F093A}"
            tint: page.tint
            title: "Animations"
            resettable: Hypr.option("animations").overridden
            onReset: Hypr.resetHypr("animations")

            SettingsSwitch {
                tint: page.tint
                checked: Hypr.optionValue("animations", true)
                onToggled: c => Hypr.setHypr("animations", c)
            }
        }
    }
}
