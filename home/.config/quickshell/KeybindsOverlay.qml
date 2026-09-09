import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Full-screen cheatsheet of the Hyprland keybinds, opened from the control
// panel or from the bind the config points at "quickshell:keybinds".
//
// Mapped for as long as the shell runs and hidden by cutting input and
// drawing nothing, the same way the bar is: toggling `visible` destroys the
// layer surface, and the trip back through Hyprland's stacking is not worth
// it for something opened this often.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    // One copy of this exists per monitor, and only the one it was opened on
    // shows: two overlays both asking for exclusive keyboard focus is a fight
    // over where Escape lands.
    //
    // Matched against the name latched when it opened rather than against
    // live focus, which follows the mouse and used to drag the sheet to
    // whichever screen the pointer wandered onto.
    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (AppState.keybindsScreen === "") return bar.monitor.focused
        return bar.monitor.name === AppState.keybindsScreen
    }

    readonly property bool open: AppState.keybindsOpen && overlay.onOpeningScreen

    // Unmapped while closed, not merely drawn empty.
    //
    // A layer surface that stays mapped sits above every window under it for
    // the life of the session, and Hyprland composites it each frame whether
    // or not it has anything in it. There were four of these, full-screen, on
    // every monitor.
    //
    // The timer is what lets it close politely: `open` goes false, the fade
    // inside starts, and the surface stays mapped long enough for that fade to
    // play. Without it the window would vanish on the first frame and the
    // fade-out would never be seen.
    //
    // Connections rather than an `onOpenChanged` here, because two of these
    // files already declare one and a second on the same object is a
    // "Property value set multiple times" error.
    visible: overlay.open || unmapDelay.running

    Timer {
        id: unmapDelay
        // The inner fades run on durMedium; the margin covers the frame the
        // Behavior needs to get going.
        interval: Theme.durMedium + 80
    }

    Connections {
        target: overlay
        function onOpenChanged() {
            if (!overlay.open) unmapDelay.restart()
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:keybinds"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Exclusive only while open, so Escape reaches us and every other key
    // goes back to whatever the user was working in.
    WlrLayershell.keyboardFocus: overlay.open ? WlrKeyboardFocus.Exclusive
                                              : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: overlay.open ? null : blankMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // ── Sections ─────────────────────────────────────────────────────────
    //
    // One per thing that has keybinds, kept apart rather than merged: `d` is
    // a different key in yazi than it is in Hyprland, and a single flat list
    // would leave the reader working out which one they are looking at.
    readonly property var sections: [
        {
            name: "Hyprland",
            groups: AppState.hyprBindGroups,
            count: AppState.hyprBindCount,
            error: AppState.hyprBindsError
        },
        {
            name: "Yazi",
            groups: AppState.yaziBindGroups,
            count: AppState.yaziBindCount,
            error: AppState.yaziBindsError
        }
    ]

    // ── Column packing ───────────────────────────────────────────────────
    //
    // Two columns of groups rather than one long list. The split is picked
    // by trying every sequential cut and keeping the one whose taller column
    // is shortest -- sequential so the groups stay in the order the source
    // declares them, weighted by rows plus a couple for each header.
    function packColumns(groups) {
        if (!groups || groups.length === 0) return [[], []]

        var weights = []
        var total = 0
        for (var i = 0; i < groups.length; i++) {
            var w = (groups[i].binds ? groups[i].binds.length : 0) + 2
            weights.push(w)
            total += w
        }

        var bestCut = 1
        var bestTallest = Infinity
        for (var cut = 1; cut < groups.length; cut++) {
            var head = 0
            for (var j = 0; j < cut; j++) head += weights[j]
            var tallest = Math.max(head, total - head)
            if (tallest < bestTallest) {
                bestTallest = tallest
                bestCut = cut
            }
        }

        return [groups.slice(0, bestCut), groups.slice(bestCut)]
    }

    function close() {
        AppState.keybindsOpen = false
    }

    // ── Backdrop ─────────────────────────────────────────────────────────

    // Light: the compositor blurs whatever is behind this surface (see the
    // quickshell-keybinds-blur layer rule), so the tint only has to settle
    // the contrast under the card. At the dim that was needed without blur
    // the desktop went to mud instead of going soft.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.background, 0.38)
        opacity: overlay.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        TapHandler {
            onTapped: overlay.close()
        }
    }

    // Focus lives on an item rather than the window so Escape has somewhere
    // to land; taking it back on close keeps the shell from holding keys.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: overlay.open

        Keys.onEscapePressed: overlay.close()
    }

    // ── Card ─────────────────────────────────────────────────────────────

    Item {
        id: cardArea
        anchors.centerIn: parent
        width: card.width
        height: card.height

        opacity: overlay.open ? 1 : 0
        visible: opacity > 0
        scale: overlay.open ? 1 : 0.97

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: card
            width: cardColumn.implicitWidth + 56
            height: Math.min(cardColumn.implicitHeight + 48, overlay.height - 80)
            radius: 26
            color: Theme.glass
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.5
            shadowBlur: 0.8
            shadowVerticalOffset: 6
            autoPaddingEnabled: true
        }

        // Swallows clicks that land on the card, so only the backdrop closes.
        TapHandler {}

        Flickable {
            anchors.fill: parent
            anchors.margins: 24
            contentHeight: cardColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: cardColumn
                spacing: 18

                RowLayout {
                    width: parent.width
                    spacing: 10

                    IconGlyph {
                        text: "󰌌"
                        color: Theme.textPrimary
                        size: Theme.iconLarge
                    }

                    Text {
                        text: "Keyboard shortcuts"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.bold: true
                        font.family: Theme.fontMono
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Esc to close"
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                    }
                }

                Repeater {
                    model: overlay.sections

                    Column {
                        id: section
                        required property var modelData
                        spacing: 12

                        // Named and counted, with a rule under it: two lists
                        // stacked with only a gap between them read as one
                        // long list with an odd blank in the middle.
                        RowLayout {
                            width: section.width
                            spacing: 8

                            Text {
                                text: section.modelData.name
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.bold: true
                                font.family: Theme.fontMono
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                Layout.alignment: Qt.AlignVCenter
                                color: Theme.outline
                            }

                            Text {
                                text: section.modelData.count > 0 ? section.modelData.count : ""
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontMono
                            }
                        }

                        Text {
                            visible: section.modelData.error.length > 0
                            width: 480
                            text: section.modelData.error
                            color: Theme.error
                            font.pixelSize: 12
                            font.family: Theme.fontMono
                            wrapMode: Text.Wrap
                        }

                        Text {
                            visible: section.modelData.error.length === 0
                                     && section.modelData.count === 0
                            text: "No shortcuts configured"
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontMono
                        }

                        Row {
                            spacing: 40

                            Repeater {
                                model: overlay.packColumns(section.modelData.groups)

                                Column {
                                    id: bindColumn
                                    required property var modelData
                                    spacing: 20

                                    Repeater {
                                        model: bindColumn.modelData

                                        Column {
                                            id: bindGroup
                                            required property var modelData
                                            spacing: 4

                                            // Monospace, so the widest key string is
                                            // the widest chip: measuring it once per
                                            // group lines the actions up in a column.
                                            readonly property string widestKeys: {
                                                var longest = ""
                                                var binds = modelData.binds
                                                for (var i = 0; i < binds.length; i++) {
                                                    if (binds[i].keys.length > longest.length)
                                                        longest = binds[i].keys
                                                }
                                                return longest
                                            }

                                            TextMetrics {
                                                id: widestKeyMetrics
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                text: bindGroup.widestKeys
                                            }

                                            Text {
                                                text: bindGroup.modelData.name
                                                color: Theme.textMuted
                                                font.pixelSize: 11
                                                font.family: Theme.fontMono
                                                bottomPadding: 4
                                            }

                                            Repeater {
                                                model: bindGroup.modelData.binds

                                                RowLayout {
                                                    id: bindRow
                                                    required property var modelData
                                                    spacing: 12

                                                    Rectangle {
                                                        Layout.preferredWidth: widestKeyMetrics.width + 16
                                                        Layout.preferredHeight: keyLabel.implicitHeight + 8
                                                        Layout.alignment: Qt.AlignTop
                                                        radius: 7
                                                        color: Theme.surfaceContainerHigh

                                                        Text {
                                                            id: keyLabel
                                                            anchors.centerIn: parent
                                                            text: bindRow.modelData.keys
                                                            color: Theme.textPrimary
                                                            font.pixelSize: 11
                                                            font.family: Theme.fontMono
                                                        }
                                                    }

                                                    Column {
                                                        Layout.alignment: Qt.AlignTop
                                                        spacing: 1
                                                        topPadding: 4

                                                        Text {
                                                            text: bindRow.modelData.action
                                                            color: Theme.textSecondary
                                                            font.pixelSize: 12
                                                            font.family: Theme.fontMono
                                                        }

                                                        // What actually runs, for the
                                                        // binds whose label is a name
                                                        // for a command rather than
                                                        // the command itself.
                                                        Text {
                                                            visible: text.length > 0
                                                            text: bindRow.modelData.command || ""
                                                            color: Theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontMono
                                                            elide: Text.ElideRight
                                                            // Long shell one-liners
                                                            // must not set the column
                                                            // width for everyone else.
                                                            width: Math.min(implicitWidth, 380)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

