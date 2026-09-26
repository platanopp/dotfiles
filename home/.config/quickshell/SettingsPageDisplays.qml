import QtQuick
import QtQuick.Layouts

// Settings -> Displays: where each screen sits, and the mode, refresh rate
// and scale of the one picked on the map. Adaptive sync is compositor-wide in
// Hyprland, so it has a section of its own rather than pretending to be per
// display.
Column {
    id: page
    spacing: 28

    // The display the page is pointed at; the focused one until another is
    // picked on the map.
    property string selected: ""

    readonly property var monitors: AppState.displayState.monitors || []
    readonly property var mon: {
        var ms = page.monitors
        for (var i = 0; i < ms.length; i++) if (ms[i].name === page.selected) return ms[i]
        for (var j = 0; j < ms.length; j++) if (ms[j].focused) return ms[j]
        return ms.length > 0 ? ms[0] : null
    }

    function shortName(m) {
        if (!m) return ""
        return (m.description || m.name)
            .replace(/ (Electric Company|Corporation|Technologies|Technology|Inc\.?|Co\.?,? ?Ltd\.?)/g, "")
    }

    function hzLabel(hz) {
        return (Math.abs(hz - Math.round(hz)) < 0.05 ? Math.round(hz) : hz.toFixed(2)) + " Hz"
    }

    // Distinct resolutions, biggest first.
    readonly property var resolutions: {
        if (!page.mon) return []
        var seen = {}, out = []
        var modes = page.mon.modes || []
        for (var i = 0; i < modes.length; i++) {
            var key = modes[i].w + "x" + modes[i].h
            if (seen[key]) continue
            seen[key] = true
            out.push({ value: key, label: modes[i].w + " × " + modes[i].h, area: modes[i].w * modes[i].h })
        }
        out.sort(function (a, b) { return b.area - a.area })
        return out
    }

    // The rates offered at the current resolution, fastest first. Values are
    // the exact mode strings Hyprland takes; labels drop the ".00".
    readonly property var rates: {
        if (!page.mon) return []
        var out = []
        var modes = page.mon.modes || []
        for (var i = 0; i < modes.length; i++)
            if (modes[i].w === page.mon.width && modes[i].h === page.mon.height)
                out.push({ value: modes[i].text, label: page.hzLabel(modes[i].hz), hz: modes[i].hz })
        out.sort(function (a, b) { return b.hz - a.hz })
        return out
    }

    readonly property string currentMode: {
        if (!page.mon) return ""
        for (var i = 0; i < page.rates.length; i++)
            if (Math.abs(page.rates[i].hz - page.mon.refresh) < 0.05) return page.rates[i].value
        return ""
    }

    // A resolution change keeps the fastest rate that resolution offers:
    // nobody picks 1440p to get it at 60 on a 120 Hz panel.
    function pickResolution(key) {
        var modes = page.mon.modes || [], best = null
        for (var i = 0; i < modes.length; i++)
            if (modes[i].w + "x" + modes[i].h === key && (!best || modes[i].hz > best.hz)) best = modes[i]
        if (best) AppState.proposeDisplayMode(page.mon.name, best.text)
    }

    // ── Keep or revert ───────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        visible: AppState.displayRevert !== null
        height: revertRow.implicitHeight + 28
        radius: 20
        color: Theme.alpha(Theme.warning, 0.14)
        border.width: 1
        border.color: Theme.alpha(Theme.warning, 0.35)

        RowLayout {
            id: revertRow
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Keep these display settings?"
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Theme.fontMono
                }

                Text {
                    Layout.fillWidth: true
                    text: "Going back to the previous ones in " + AppState.displayRevertLeft + " s"
                    color: Theme.warning
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    wrapMode: Text.WordWrap
                }
            }

            PillButton { text: "Revert"; onClicked: AppState.revertDisplayChanges() }
            PillButton { text: "Keep"; emphasis: true; onClicked: AppState.keepDisplayChanges() }
        }
    }

    // ── Arrangement ──────────────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        title: "Arrangement"
        subtitle: "Where each display sits next to the other. The pointer and windows cross over at the edges lined up here."

        SettingsRow {
            stacked: true
            title: page.monitors.length > 1 ? "Drag a display to move it" : "This display"
            description: page.monitors.length > 1
                ? "Edges snap to each other, so no gap is left between them. Click a display to change its settings below."
                : "With a second display plugged in, this is where you arrange them."

            MonitorMap {
                width: parent.width
                height: 200
                implicitHeight: 200
                selected: page.mon ? page.mon.name : ""
                onPicked: name => page.selected = name
            }
        }
    }

    // ── The picked display ───────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        visible: page.mon !== null
        title: page.mon ? page.shortName(page.mon) + "  ·  " + page.mon.name : ""
        subtitle: page.mon
            ? "Now " + page.mon.width + " × " + page.mon.height + " at " + page.hzLabel(page.mon.refresh)
              + (page.mon.scale !== 1 ? ", scaled " + Math.round(page.mon.scale * 100) + "%" : "")
            : ""

        SettingsRow {
            stacked: true
            title: "Resolution"
            description: "Changes ask to be kept: if the screen goes dark, the old one comes back by itself in 15 seconds."

            ChoiceChips {
                width: parent.width
                options: page.resolutions
                value: page.mon ? page.mon.width + "x" + page.mon.height : ""
                onPicked: v => page.pickResolution(v)
            }
        }

        SettingsRow {
            stacked: true
            title: "Refresh rate"
            description: page.rates.length > 1 ? "How many times a second the picture is redrawn."
                                               : "The only rate this resolution offers."

            ChoiceChips {
                width: parent.width
                options: page.rates
                value: page.currentMode
                onPicked: v => AppState.proposeDisplayMode(page.mon.name, v)
            }
        }

        SettingsRow {
            title: "Scale"
            description: "Makes everything on this display bigger. Hyprland may round it to the nearest size the resolution divides into."

            Segmented {
                options: [
                    { value: 1, label: "100%" },
                    { value: 1.25, label: "125%" },
                    { value: 1.5, label: "150%" },
                    { value: 2, label: "200%" }
                ]
                value: page.mon ? page.mon.scale : 1
                onPicked: v => AppState.proposeDisplayScale(page.mon.name, v)
            }
        }
    }

    // ── Sync ─────────────────────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        title: "Sync"
        subtitle: "Hyprland applies this to every display at once."

        SettingsRow {
            stacked: true
            title: "Adaptive sync"
            description: "Lets a display follow the frame rate it is being fed -- G-SYNC and FreeSync on Wayland. Some panels flicker with it always on, which is what \"Fullscreen\" is for."

            Segmented {
                options: [
                    { value: 0, label: "Off" },
                    { value: 1, label: "Always" },
                    { value: 2, label: "Fullscreen" }
                ]
                value: AppState.displayState.vrr
                onPicked: v => AppState.setDisplayVrr(v)
            }
        }
    }
}
