import QtQuick
import QtQuick.Layouts

// Settings -> Displays: where each screen sits, and the mode, refresh rate and
// scale of the one picked on the map. Adaptive sync is compositor-wide in
// Hyprland, so it sits on its own.
Column {
    id: page
    spacing: 24

    readonly property color tint: Theme.accent

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
    //
    // Resolution and scale go on at once and come back by themselves unless
    // kept: a mode the screen cannot show leaves it dark, with no way to reach
    // the control that would undo it.
    Rectangle {
        width: parent.width
        visible: AppState.displayRevert !== null
        height: 64
        radius: 22
        color: Theme.alpha(Theme.warning, 0.14)
        border.width: 1
        border.color: Theme.alpha(Theme.warning, 0.35)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 12

            // The countdown as a ring draining around the seconds left.
            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36

                Canvas {
                    id: ring
                    anchors.fill: parent
                    // Not "left": every Item already has one (anchors use it),
                    // and redeclaring it stopped the whole page from loading.
                    property real remaining: AppState.displayRevertLeft / 15
                    onRemainingChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineWidth = 3
                        ctx.strokeStyle = Theme.alpha(Theme.warning, 0.25)
                        ctx.beginPath(); ctx.arc(18, 18, 15, 0, Math.PI * 2); ctx.stroke()
                        ctx.strokeStyle = Theme.warning
                        ctx.beginPath(); ctx.arc(18, 18, 15, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ring.remaining); ctx.stroke()
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: AppState.displayRevertLeft
                    color: Theme.warning
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontMono
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Keep this?"
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontMono
            }

            PillButton { text: "Revert"; onClicked: AppState.revertDisplayChanges() }
            PillButton { text: "Keep"; emphasis: true; onClicked: AppState.keepDisplayChanges() }
        }
    }

    // ── Arrangement ──────────────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        title: "Arrangement"
        tint: page.tint

        SettingsRow {
            stacked: true
            icon: "\u{F037A}"
            tint: page.tint
            title: page.monitors.length > 1 ? "Drag to rearrange" : "This display"
            value: page.monitors.length > 1 ? page.monitors.length + " displays" : ""

            MonitorMap {
                width: parent.width
                height: 190
                implicitHeight: 190
                tint: page.tint
                selected: page.mon ? page.mon.name : ""
                onPicked: name => page.selected = name
            }
        }
    }

    // ── The picked display ───────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        visible: page.mon !== null
        title: page.mon ? page.shortName(page.mon) : ""
        tint: page.tint

        SelectRow {
            icon: "\u{F0A24}"
            title: "Resolution"
            options: page.resolutions
            value: page.mon ? page.mon.width + "x" + page.mon.height : ""
            onPicked: v => page.pickResolution(v)
        }

        // Four rates or fewer fit in one pill; more fold away like the
        // resolutions do.
        SettingsRow {
            visible: page.rates.length <= 4
            icon: "\u{F04C5}"
            title: "Refresh rate"

            Segmented {
                options: page.rates
                value: page.currentMode
                onPicked: v => AppState.proposeDisplayMode(page.mon.name, v)
            }
        }

        SelectRow {
            visible: page.rates.length > 4
            icon: "\u{F04C5}"
            title: "Refresh rate"
            options: page.rates
            value: page.currentMode
            onPicked: v => AppState.proposeDisplayMode(page.mon.name, v)
        }

        SettingsRow {
            icon: "\u{F06ED}"
            tint: page.tint
            title: "Scale"

            Segmented {
                tint: page.tint
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
        title: "Every display"
        tint: page.tint

        SettingsRow {
            icon: "\u{F04E6}"
            tint: page.tint
            title: "Adaptive sync"
            description: "G-SYNC / FreeSync"

            Segmented {
                tint: page.tint
                options: [
                    { value: 0, label: "Off" },
                    { value: 1, label: "On" },
                    { value: 2, label: "Fullscreen" }
                ]
                value: AppState.displayState.vrr
                onPicked: v => AppState.setDisplayVrr(v)
            }
        }
    }
}
