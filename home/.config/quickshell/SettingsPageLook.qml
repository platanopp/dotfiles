import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets

// Settings -> Hyprland -> Look: gaps, borders, corners, transparency and
// effects. Everything goes through scripts/hypr_settings.py, which keeps to a
// fixed list of options, writes gui-settings.lua rather than hyprland.lua,
// checks the change live, puts it back if Hyprland refuses it, and commits it
// to ~/dotfiles when it took.
//
// The preview at the top is the point of the page: two windows over your own
// wallpaper, drawn with the values the sliders are showing -- including the
// one being dragged, before it has been applied.
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    function opt(key) { return AppState.hyprOptions[key] || ({ value: 0, overridden: false }) }
    function val(key, fallback) {
        var o = AppState.hyprOptions[key]
        return o && o.value !== null && o.value !== undefined ? o.value : fallback
    }

    // ── Preview ──────────────────────────────────────────────────────────
    Rectangle {
        id: preview
        width: parent.width
        height: 210
        radius: 22
        color: Theme.surfaceContainer

        // Scaled from a 1080-tall screen into the preview, then doubled:
        // at true scale a 15px gap is two pixels, and nothing reads.
        readonly property real k: (mock.height / 1080) * 2

        readonly property real gapIn: gapInSlider.shown * preview.k
        readonly property real gapOut: gapOutSlider.shown * preview.k
        // Not "border": a Rectangle has one, and redeclaring it fails the page.
        readonly property real borderPx: borderSlider.shown
        readonly property real round: roundSlider.shown * preview.k
        readonly property real focusedAlpha: activeSlider.shown
        readonly property real otherAlpha: inactiveSlider.shown
        readonly property string layout: page.val("layout", "dwindle")

        ClippingRectangle {
            id: mock
            anchors.fill: parent
            anchors.margins: 12
            radius: 14
            color: Theme.background

            Image {
                anchors.fill: parent
                source: AppState.wallpaperStill.length > 0 ? "file://" + AppState.wallpaperStill : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 800
            }

            // The two windows, laid out the way the chosen layout would:
            // dwindle halves the screen, master gives the first one more,
            // scrolling runs columns off the right edge.
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
                    y: preview.gapOut + preview.gapIn
                    width: (win.index === 0 ? win.areaW * win.share
                                            : preview.layout === "scrolling" ? win.areaW * win.share
                                            : win.areaW * (1 - win.share)) - preview.gapIn * 2
                    height: mock.height - (preview.gapOut + preview.gapIn) * 2

                    Behavior on x { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }

                    RectangularShadow {
                        anchors.fill: parent
                        visible: page.val("shadow", true)
                        radius: preview.round
                        blur: 14
                        offset.y: 3
                        color: Qt.rgba(0, 0, 0, 0.5)
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
                            visible: !win.focused && page.val("dim_inactive", false)
                            color: Qt.rgba(0, 0, 0, 0.35)
                        }
                    }
                }
            }
        }
    }

    // ── Spacing ──────────────────────────────────────────────────────────
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
            resettable: page.opt("gaps_in").overridden
            onReset: AppState.resetHypr("gaps_in")

            SettingsSlider {
                id: gapInSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 40; step: 1
                value: page.val("gaps_in", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => AppState.setHypr("gaps_in", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F00CE}"
            tint: page.tint
            title: "To the screen edge"
            value: Math.round(gapOutSlider.shown) + " px"
            resettable: page.opt("gaps_out").overridden
            onReset: AppState.resetHypr("gaps_out")

            SettingsSlider {
                id: gapOutSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 80; step: 1
                value: page.val("gaps_out", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => AppState.setHypr("gaps_out", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F00C7}"
            tint: page.tint
            title: "Border"
            value: Math.round(borderSlider.shown) + " px"
            resettable: page.opt("border_size").overridden
            onReset: AppState.resetHypr("border_size")

            SettingsSlider {
                id: borderSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 8; step: 1
                value: page.val("border_size", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => AppState.setHypr("border_size", Math.round(v))
            }
        }
    }

    // ── Shape ────────────────────────────────────────────────────────────
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
            resettable: page.opt("rounding").overridden
            onReset: AppState.resetHypr("rounding")

            SettingsSlider {
                id: roundSlider
                width: parent.width
                tint: page.tint
                from: 0; to: 40; step: 1
                value: page.val("rounding", 0)
                format: v => Math.round(v) + " px"
                onMoved: v => AppState.setHypr("rounding", Math.round(v))
            }
        }

        SettingsRow {
            icon: "\u{F0A1D}"
            tint: page.tint
            title: "Layout"
            resettable: page.opt("layout").overridden
            onReset: AppState.resetHypr("layout")

            Segmented {
                tint: page.tint
                options: [
                    { value: "dwindle", label: "Dwindle" },
                    { value: "master", label: "Master" },
                    { value: "scrolling", label: "Scrolling" }
                ]
                value: page.val("layout", "dwindle")
                onPicked: v => AppState.setHypr("layout", v)
            }
        }
    }

    // ── Transparency ─────────────────────────────────────────────────────
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
            resettable: page.opt("active_opacity").overridden
            onReset: AppState.resetHypr("active_opacity")

            SettingsSlider {
                id: activeSlider
                width: parent.width
                tint: page.tint
                from: 0.4; to: 1.0; step: 0.01
                value: page.val("active_opacity", 1)
                format: v => Math.round(v * 100) + "%"
                onMoved: v => AppState.setHypr("active_opacity", v.toFixed(2))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F06D0}"
            tint: page.tint
            title: "Other windows"
            value: Math.round(inactiveSlider.shown * 100) + "%"
            resettable: page.opt("inactive_opacity").overridden
            onReset: AppState.resetHypr("inactive_opacity")

            SettingsSlider {
                id: inactiveSlider
                width: parent.width
                tint: page.tint
                from: 0.2; to: 1.0; step: 0.01
                value: page.val("inactive_opacity", 1)
                format: v => Math.round(v * 100) + "%"
                onMoved: v => AppState.setHypr("inactive_opacity", v.toFixed(2))
            }
        }

        SettingsRow {
            icon: "\u{F00DD}"
            tint: page.tint
            title: "Dim other windows"
            resettable: page.opt("dim_inactive").overridden
            onReset: AppState.resetHypr("dim_inactive")

            SettingsSwitch {
                tint: page.tint
                checked: page.val("dim_inactive", false)
                onToggled: c => AppState.setHypr("dim_inactive", c)
            }
        }
    }

    // ── Effects ──────────────────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        title: "Effects"
        tint: page.tint

        SettingsRow {
            icon: "\u{F00B5}"
            tint: page.tint
            title: "Blur"
            resettable: page.opt("blur").overridden
            onReset: AppState.resetHypr("blur")

            SettingsSwitch {
                tint: page.tint
                checked: page.val("blur", true)
                onToggled: c => AppState.setHypr("blur", c)
            }
        }

        SettingsRow {
            stacked: true
            visible: page.val("blur", true)
            icon: "\u{F00B5}"
            tint: page.tint
            title: "Blur size"
            value: Math.round(blurSizeSlider.shown)
            resettable: page.opt("blur_size").overridden
            onReset: AppState.resetHypr("blur_size")

            SettingsSlider {
                id: blurSizeSlider
                width: parent.width
                tint: page.tint
                from: 1; to: 16; step: 1
                value: page.val("blur_size", 5)
                onMoved: v => AppState.setHypr("blur_size", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            visible: page.val("blur", true)
            icon: "\u{F00B5}"
            tint: page.tint
            title: "Blur passes"
            value: Math.round(blurPassSlider.shown)
            resettable: page.opt("blur_passes").overridden
            onReset: AppState.resetHypr("blur_passes")

            SettingsSlider {
                id: blurPassSlider
                width: parent.width
                tint: page.tint
                from: 1; to: 6; step: 1
                value: page.val("blur_passes", 3)
                onMoved: v => AppState.setHypr("blur_passes", Math.round(v))
            }
        }

        SettingsRow {
            icon: "\u{F0637}"
            tint: page.tint
            title: "Shadows"
            resettable: page.opt("shadow").overridden
            onReset: AppState.resetHypr("shadow")

            SettingsSwitch {
                tint: page.tint
                checked: page.val("shadow", true)
                onToggled: c => AppState.setHypr("shadow", c)
            }
        }

        SettingsRow {
            icon: "\u{F093A}"
            tint: page.tint
            title: "Animations"
            resettable: page.opt("animations").overridden
            onReset: AppState.resetHypr("animations")

            SettingsSwitch {
                tint: page.tint
                checked: page.val("animations", true)
                onToggled: c => AppState.setHypr("animations", c)
            }
        }
    }
}
