import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Quick capture into the Obsidian vault, in a pill of its own.
//
// Type a line, press Enter, and it lands as a timestamped bullet under
// today's heading in the vault's capture note. Nothing here talks to
// Obsidian: the vault is Markdown on disk, so this works whether the app is
// open or not, and Obsidian reads the change when it next looks.
PanelWindow {
    id: notesItem

    property var bar: null

    screen: bar.screen
    visible: true
    color: "transparent"

    // Closed, only the pill's own rectangle takes input, so the rest of this
    // full-screen surface is not there as far as anything below is
    // concerned. Open, the mask comes off and the whole screen reports to
    // us -- which is the only way a click landing outside the panel can be
    // noticed at all, there being no focus grab to lean on.
    mask: bar.barHidden ? blankMask
        : notesItem.panelOpen ? null
        : pillMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    Region {
        id: pillMask
        item: pillArea
    }

    readonly property bool barHovered: barHover.hovered

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Typing needs the keys, but only while the box is up: the rest of the
    // time they belong to whatever the user is actually working in.
    WlrLayershell.keyboardFocus: notesItem.panelOpen ? WlrKeyboardFocus.OnDemand
                                                     : WlrKeyboardFocus.None

    // Spans the screen; the pill places itself inside with `leftMargin`,
    // which the shell sets from the clock's right edge.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // The content inside insets itself by 12, so the window sits back by
    // that much and the drawn edge lands exactly on Hyprland's gap.
    margins.top: AppState.gapTop - 12

    property int leftMargin: 0

    property bool panelOpen: false

    onPanelOpenChanged: {
        if (panelOpen) {
            AppState.refreshObsidianNotes()
            noteInput.forceActiveFocus()
        } else {
            noteInput.text = ""
        }
    }

    function submit() {
        if (noteInput.text.trim().length === 0) return
        AppState.addObsidianNote(noteInput.text)
        noteInput.text = ""
    }

    // Everything outside the panel. Swallows the first click and shuts on
    // the second, as asked -- there is no way to see a click out here
    // without taking it, so while the box is up a click meant for the app
    // underneath does not reach it.
    //
    // The handler spans the whole surface, the panel included, so the point
    // is checked against the panel's rectangle first: without that, a double
    // click to select a word in the box would close the thing being typed
    // into.
    TapHandler {
        enabled: notesItem.panelOpen

        onDoubleTapped: function(point) {
            var px = point.position.x
            var py = point.position.y
            if (px >= pillArea.x && px < pillArea.x + pillArea.width
                && py >= pillArea.y && py < pillArea.y + pillArea.height) return
            notesItem.panelOpen = false
        }
    }

    Item {
        id: pillArea
        x: notesItem.leftMargin
        y: 0
        width: notesItem.panelOpen ? 340 : 64
        height: notesItem.panelOpen ? Math.min(panelColumn.implicitHeight + 56, 560) : 64

        Behavior on x {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        Behavior on width {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        Behavior on height {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        // Only the pill keeps the bar up, not the full-screen backdrop.
        HoverHandler {
            id: barHover
        }

        Item {
            id: contentArea
            visible: !bar.barHidden
            anchors.fill: parent
            anchors.margins: 12

            Rectangle {
                id: notesGlass
                anchors.fill: parent
                radius: notesItem.panelOpen ? 26 : 20
                color: Theme.glass
                visible: false
                layer.enabled: true

                Behavior on radius {
                    NumberAnimation { duration: 200 }
                }
            }

            MultiEffect {
                source: notesGlass
                anchors.fill: notesGlass
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.5
                shadowBlur: 0.7
                shadowVerticalOffset: 4
                autoPaddingEnabled: true
            }

            // Obsidian's own icon, shipped with the app, rather than a glyph
            // standing in for it -- so it is the only coloured thing on the bar,
            // which is the point: it says which app this writes to.
            Image {
                id: notesIcon
                anchors.centerIn: parent
                visible: !notesItem.panelOpen
                opacity: !notesItem.panelOpen ? 1 : 0
                source: "file:///usr/share/icons/hicolor/512x512/apps/obsidian.png"
                width: 21
                height: 21
                sourceSize.width: 42
                sourceSize.height: 42
                smooth: true
                mipmap: true

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }

            TapHandler {
                enabled: !notesItem.panelOpen
                onTapped: notesItem.panelOpen = true
            }

            // Same reason the control panel gates its body: collapsed, a panel
            // that keeps drawing leaves its contents smeared across the pill.
            Flickable {
                visible: notesItem.panelOpen
                opacity: notesItem.panelOpen ? 1 : 0
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: panelColumn.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }

                Column {
                    id: panelColumn
                    width: parent.width
                    spacing: 12

                    Column {
                        width: parent.width
                        spacing: 2

                        Text {
                            text: "Quick capture"
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.bold: true
                            font.family: Theme.fontMono
                        }

                        Text {
                            text: AppState.obsidianError.length > 0
                                  ? AppState.obsidianError
                                  : AppState.obsidianVaultName + " · " + AppState.obsidianNote
                            color: AppState.obsidianError.length > 0 ? Theme.error : Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontMono
                            width: parent.width
                            elide: Text.ElideMiddle
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.max(40, noteInput.implicitHeight + 20)
                        radius: 12
                        color: Theme.surfaceContainer
                        border.width: noteInput.activeFocus ? 1 : 0
                        border.color: AppState.themeAccent

                        Behavior on border.color { ColorAnimation { duration: Theme.durShort } }

                        TextInput {
                            id: noteInput
                            anchors.fill: parent
                            anchors.margins: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontMono
                            selectByMouse: true
                            selectionColor: Theme.alpha(AppState.themeAccent, 0.35)
                            selectedTextColor: Theme.textPrimary
                            clip: true

                            onAccepted: notesItem.submit()
                            Keys.onEscapePressed: notesItem.panelOpen = false

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: noteInput.text.length === 0
                                text: "Jot something down…"
                                color: Theme.textMuted
                                font.pixelSize: 12
                                font.family: Theme.fontMono
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: noteCount.implicitHeight

                        Text {
                            id: noteCount
                            anchors.right: parent.right
                            visible: AppState.obsidianTotal > 0
                            text: AppState.obsidianTotal + (AppState.obsidianTotal === 1 ? " note" : " notes")
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontMono
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outline
                    }

                    Text {
                        visible: AppState.obsidianEntries.length === 0 && AppState.obsidianError.length === 0
                        text: "Nothing noted down yet"
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                    }

                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: AppState.obsidianEntries

                            Rectangle {
                                id: entryRow
                                required property var modelData
                                required property int index

                                // The date only prints when it changes going down
                                // the list, so a run of entries from one day reads
                                // as one block instead of repeating itself.
                                readonly property bool startsDay: index === 0
                                    || AppState.obsidianEntries[index - 1].date !== modelData.date

                                width: parent.width
                                height: entryText.implicitHeight + 12 + (startsDay ? dayLabel.implicitHeight + 6 : 0)
                                radius: 8
                                color: entryState.hovered ? Theme.surfaceContainer : "transparent"

                                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                Text {
                                    id: dayLabel
                                    visible: entryRow.startsDay
                                    anchors.top: parent.top
                                    anchors.topMargin: 4
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    text: entryRow.modelData.date
                                    color: Theme.textMuted
                                    font.pixelSize: 9
                                    font.family: Theme.fontMono
                                }

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 8

                                    Text {
                                        text: entryRow.modelData.time
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontMono
                                        Layout.alignment: Qt.AlignTop
                                    }

                                    Text {
                                        id: entryText
                                        text: entryRow.modelData.text
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontMono
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }

                                StateLayer {
                                    id: entryState
                                    interactive: false
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outline
                    }

                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: 12
                        color: openState.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            IconGlyph {
                                text: "󰏌"
                                color: Theme.textPrimary
                                size: Theme.iconSmall
                            }

                            Text {
                                text: "Open in Obsidian"
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontMono
                            }
                        }

                        StateLayer {
                            id: openState
                            onTapped: {
                                notesItem.panelOpen = false
                                AppState.openObsidianNote()
                            }
                        }
                    }
                }
            }
        }
    }
}
