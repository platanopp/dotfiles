import QtQuick
import QtQuick.Layouts

// Settings -> Hyprland -> Input: the pointer, the keyboard's repeat, scrolling
// and the cursor. Same rules as the Look page (scripts/hypr_settings.py).
//
// The keyboard layout is not here on purpose: a wrong one, and the lock
// screen's password cannot be typed. The tablet is untouched by any of it --
// OpenTabletDriver drives an absolute device, which pointer speed and
// acceleration do not apply to.
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

    function opt(key) { return AppState.hyprOptions[key] || ({ value: 0, overridden: false }) }
    function val(key, fallback) {
        var o = AppState.hyprOptions[key]
        return o && o.value !== null && o.value !== undefined ? o.value : fallback
    }

    SettingsGroup {
        width: parent.width
        title: "Pointer"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F037D}"
            tint: page.tint
            title: "Speed"
            value: speedSlider.format(speedSlider.shown)
            resettable: page.opt("sensitivity").overridden
            onReset: AppState.resetHypr("sensitivity")

            SettingsSlider {
                id: speedSlider
                width: parent.width
                tint: page.tint
                from: -1; to: 1; step: 0.05
                neutral: 0
                value: page.val("sensitivity", 0)
                format: v => (v > 0.001 ? "+" : "") + v.toFixed(2)
                onMoved: v => AppState.setHypr("sensitivity", v.toFixed(2))
            }
        }

        SettingsRow {
            icon: "\u{F0C50}"
            tint: page.tint
            title: "Acceleration"
            description: "Flat moves exactly as far as the hand"
            resettable: page.opt("accel_profile").overridden
            onReset: AppState.resetHypr("accel_profile")

            Segmented {
                tint: page.tint
                options: [
                    { value: "adaptive", label: "Adaptive" },
                    { value: "flat", label: "Flat" }
                ]
                value: page.val("accel_profile", "adaptive")
                onPicked: v => AppState.setHypr("accel_profile", v)
            }
        }

        SettingsRow {
            icon: "\u{F0CFE}"
            tint: page.tint
            title: "Focus follows"
            resettable: page.opt("follow_mouse").overridden
            onReset: AppState.resetHypr("follow_mouse")

            Segmented {
                tint: page.tint
                options: [
                    { value: 1, label: "Hover" },
                    { value: 0, label: "Click" }
                ]
                value: page.val("follow_mouse", 1)
                onPicked: v => AppState.setHypr("follow_mouse", v)
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Keyboard"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F051B}"
            tint: page.tint
            title: "Repeat delay"
            value: Math.round(delaySlider.shown) + " ms"
            resettable: page.opt("repeat_delay").overridden
            onReset: AppState.resetHypr("repeat_delay")

            SettingsSlider {
                id: delaySlider
                width: parent.width
                tint: page.tint
                from: 150; to: 1000; step: 10
                value: page.val("repeat_delay", 600)
                format: v => Math.round(v) + " ms"
                onMoved: v => AppState.setHypr("repeat_delay", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F030C}"
            tint: page.tint
            title: "Repeat rate"
            value: Math.round(rateSlider.shown) + " / s"
            resettable: page.opt("repeat_rate").overridden
            onReset: AppState.resetHypr("repeat_rate")

            SettingsSlider {
                id: rateSlider
                width: parent.width
                tint: page.tint
                from: 10; to: 80; step: 1
                value: page.val("repeat_rate", 25)
                format: v => Math.round(v) + " / s"
                onMoved: v => AppState.setHypr("repeat_rate", Math.round(v))
            }
        }
    }

    SettingsGroup {
        width: parent.width
        title: "Scrolling & cursor"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F1552}"
            tint: page.tint
            title: "Scroll speed"
            value: scrollSlider.format(scrollSlider.shown)
            resettable: page.opt("scroll_factor").overridden
            onReset: AppState.resetHypr("scroll_factor")

            SettingsSlider {
                id: scrollSlider
                width: parent.width
                tint: page.tint
                from: 0.3; to: 3.0; step: 0.1
                neutral: 1.0
                value: page.val("scroll_factor", 1)
                format: v => v.toFixed(1) + "×"
                onMoved: v => AppState.setHypr("scroll_factor", v.toFixed(1))
            }
        }

        SettingsRow {
            icon: "\u{F0AC0}"
            tint: page.tint
            title: "Natural scrolling"
            resettable: page.opt("natural_scroll").overridden
            onReset: AppState.resetHypr("natural_scroll")

            SettingsSwitch {
                tint: page.tint
                checked: page.val("natural_scroll", false)
                onToggled: c => AppState.setHypr("natural_scroll", c)
            }
        }

        SettingsRow {
            icon: "\u{F05E7}"
            tint: page.tint
            title: "Hide cursor while typing"
            resettable: page.opt("hide_cursor_typing").overridden
            onReset: AppState.resetHypr("hide_cursor_typing")

            SettingsSwitch {
                tint: page.tint
                checked: page.val("hide_cursor_typing", false)
                onToggled: c => AppState.setHypr("hide_cursor_typing", c)
            }
        }
    }
}
