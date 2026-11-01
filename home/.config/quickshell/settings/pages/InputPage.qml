import QtQuick
import qs.components
import qs.config
import qs.services
import qs.settings

// Settings -> Hyprland -> Input: pointer, key repeat, scrolling and cursor, through
// hypr_settings.py. No keyboard layout here: a wrong one would make the lock's password untypable.
// The tablet is unaffected (absolute device).
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

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
            resettable: Hypr.option("sensitivity").overridden
            onReset: Hypr.resetHypr("sensitivity")

            SettingsSlider {
                id: speedSlider
                width: parent.width
                tint: page.tint
                from: -1; to: 1; step: 0.05
                neutral: 0
                value: Hypr.optionValue("sensitivity", 0)
                format: v => (v > 0.001 ? "+" : "") + v.toFixed(2)
                onMoved: v => Hypr.setHypr("sensitivity", v.toFixed(2))
            }
        }

        SettingsRow {
            icon: "\u{F0C50}"
            tint: page.tint
            title: "Acceleration"
            description: "Flat moves exactly as far as the hand"
            resettable: Hypr.option("accel_profile").overridden
            onReset: Hypr.resetHypr("accel_profile")

            Segmented {
                tint: page.tint
                options: [
                    { value: "adaptive", label: "Adaptive" },
                    { value: "flat", label: "Flat" }
                ]
                value: Hypr.optionValue("accel_profile", "adaptive")
                onPicked: v => Hypr.setHypr("accel_profile", v)
            }
        }

        SettingsRow {
            icon: "\u{F0CFE}"
            tint: page.tint
            title: "Focus follows"
            resettable: Hypr.option("follow_mouse").overridden
            onReset: Hypr.resetHypr("follow_mouse")

            // Click is Hyprland's 2, not 0: with 0 the pointer itself stayed on the focused window,
            // so the wheel and hover died elsewhere. With 2 only the keyboard waits for the click.
            Segmented {
                tint: page.tint
                options: [
                    { value: 1, label: "Hover" },
                    { value: 2, label: "Click" }
                ]
                value: Hypr.optionValue("follow_mouse", 1) === 0 ? 2 : Hypr.optionValue("follow_mouse", 1)
                onPicked: v => Hypr.setHypr("follow_mouse", v)
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
            resettable: Hypr.option("repeat_delay").overridden
            onReset: Hypr.resetHypr("repeat_delay")

            SettingsSlider {
                id: delaySlider
                width: parent.width
                tint: page.tint
                from: 150; to: 1000; step: 10
                value: Hypr.optionValue("repeat_delay", 600)
                format: v => Math.round(v) + " ms"
                onMoved: v => Hypr.setHypr("repeat_delay", Math.round(v))
            }
        }

        SettingsRow {
            stacked: true
            icon: "\u{F030C}"
            tint: page.tint
            title: "Repeat rate"
            value: Math.round(rateSlider.shown) + " / s"
            resettable: Hypr.option("repeat_rate").overridden
            onReset: Hypr.resetHypr("repeat_rate")

            SettingsSlider {
                id: rateSlider
                width: parent.width
                tint: page.tint
                from: 10; to: 80; step: 1
                value: Hypr.optionValue("repeat_rate", 25)
                format: v => Math.round(v) + " / s"
                onMoved: v => Hypr.setHypr("repeat_rate", Math.round(v))
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
            resettable: Hypr.option("scroll_factor").overridden
            onReset: Hypr.resetHypr("scroll_factor")

            SettingsSlider {
                id: scrollSlider
                width: parent.width
                tint: page.tint
                from: 0.3; to: 3.0; step: 0.1
                neutral: 1.0
                value: Hypr.optionValue("scroll_factor", 1)
                format: v => v.toFixed(1) + "×"
                onMoved: v => Hypr.setHypr("scroll_factor", v.toFixed(1))
            }
        }

        SettingsRow {
            icon: "\u{F0AC0}"
            tint: page.tint
            title: "Natural scrolling"
            resettable: Hypr.option("natural_scroll").overridden
            onReset: Hypr.resetHypr("natural_scroll")

            SettingsSwitch {
                tint: page.tint
                checked: Hypr.optionValue("natural_scroll", false)
                onToggled: c => Hypr.setHypr("natural_scroll", c)
            }
        }

        SettingsRow {
            icon: "\u{F05E7}"
            tint: page.tint
            title: "Hide cursor while typing"
            resettable: Hypr.option("hide_cursor_typing").overridden
            onReset: Hypr.resetHypr("hide_cursor_typing")

            SettingsSwitch {
                tint: page.tint
                checked: Hypr.optionValue("hide_cursor_typing", false)
                onToggled: c => Hypr.setHypr("hide_cursor_typing", c)
            }
        }
    }
}
