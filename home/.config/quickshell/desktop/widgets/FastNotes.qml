import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.config
import qs.desktop
import qs.services

// Fast Notes: a small task list on the desktop, kept in the Obsidian vault as
// "- [ ] HH:MM text" lines (scripts/obsidian_notes.py), so the same list is
// checkable from Obsidian. A click on a note or its box checks it off; the
// done ones sink below the pending, struck through, until cleared.
WidgetCard {
    id: root

    implicitWidth: 320
    implicitHeight: 360
    clip: true

    function submit() {
        var txt = noteInput.text.trim()
        if (txt.length === 0) return
        Notes.add(txt)
        noteInput.text = ""
        notesList.positionViewAtBeginning()
    }

    // A small square button with a glyph, tinted on hover.
    component GlyphButton: Rectangle {
        id: btn
        property string glyph: ""
        property color hoverInk: Theme.accent
        signal clicked()

        implicitWidth: 26
        implicitHeight: 26
        radius: 8
        color: btnMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.durShort } }

        IconGlyph {
            anchors.centerIn: parent
            text: btn.glyph
            color: btnMouse.containsMouse ? btn.hoverInk : Theme.textMuted
            size: Theme.iconSmall

            Behavior on color { ColorAnimation { duration: Theme.durShort } }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        anchors.bottomMargin: 10
        spacing: 12

        // ── Header ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Image {
                source: "file:///usr/share/icons/hicolor/512x512/apps/obsidian.png"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                sourceSize.width: 44
                sourceSize.height: 44
                smooth: true
                mipmap: true
            }

            Column {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Notas rápidas"
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.family: Theme.fontDisplay
                }

                Text {
                    text: Notes.total === 0 ? "Nada pendiente"
                        : Notes.pending === 0 ? "Todo hecho"
                        : Notes.pending + (Notes.pending === 1 ? " pendiente" : " pendientes")
                          + (Notes.done > 0 ? " · " + Notes.done + (Notes.done === 1 ? " hecha" : " hechas") : "")
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }
            }

            GlyphButton {
                glyph: "\u{F00E2}" // broom
                hoverInk: Theme.error
                visible: Notes.done > 0
                onClicked: Notes.clearDone()
            }

            GlyphButton {
                glyph: "\u{F03CC}" // open in Obsidian
                onClicked: Notes.openObsidian()
            }
        }

        // Today's progress: how much of the list is checked off.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -2
            Layout.preferredHeight: 3
            radius: 1.5
            color: Theme.track
            visible: Notes.total > 0

            Rectangle {
                width: parent.width * (Notes.total > 0 ? Notes.done / Notes.total : 0)
                height: parent.height
                radius: parent.radius
                color: Theme.accent

                Behavior on width { NumberAnimation { duration: Theme.durMedium * 2; easing.type: Easing.OutCubic } }
            }
        }

        // ── New note ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: Theme.surfaceContainer
            border.width: 1
            border.color: noteInput.activeFocus ? Theme.alpha(Theme.accent, 0.7) : Theme.outline

            Behavior on border.color { ColorAnimation { duration: Theme.durShort } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 6

                TextInput {
                    id: noteInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.family: Theme.fontText
                    selectByMouse: true
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    clip: true

                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: noteInput.focus = false

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: noteInput.text.length === 0 && !noteInput.inputMethodComposing
                        text: "Nueva nota…  (@6/11 10:00 o @18:30)"
                        color: Theme.textMuted
                        font: noteInput.font
                    }
                }

                Rectangle {
                    readonly property bool ready: noteInput.text.trim().length > 0
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 8
                    color: ready ? Theme.accent : "transparent"
                    scale: addMouse.pressed ? 0.9 : 1

                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                    Behavior on scale { Elastic { small: true } }

                    IconGlyph {
                        anchors.centerIn: parent
                        text: "\u{F0415}" // plus
                        color: parent.ready ? Theme.accentText : Theme.textMuted
                        size: Theme.iconSmall
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        enabled: parent.ready
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submit()
                    }
                }
            }
        }

        // ── The list ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
                anchors.centerIn: parent
                visible: Notes.total === 0
                spacing: 6

                IconGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{F0135}" // check-circle-outline
                    color: Theme.alpha(Theme.foreground, 0.25)
                    size: 26
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Todo al día"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontText
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Escribe arriba y pulsa Enter"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                }
            }

            ListView {
                id: notesList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Notes.ordered
                spacing: 2

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property bool checked: row.modelData.checked
                    // Its text open for editing: Enter or a click away saves,
                    // Esc puts it back.
                    property bool editing: false

                    function startEdit() {
                        editor.text = row.modelData.text
                        row.editing = true
                        editor.forceActiveFocus()
                        editor.cursorPosition = editor.length
                    }
                    function finishEdit(save) {
                        if (!row.editing) return
                        row.editing = false
                        if (save && editor.text.trim() !== row.modelData.text) Notes.edit(row.modelData.id, editor.text)
                    }
                    // The first done note gets a small "Hechas" label over it.
                    readonly property bool firstDone: row.checked
                        && (row.index === 0 || !Notes.ordered[row.index - 1].checked)
                        && Notes.pending > 0

                    width: notesList.width
                    height: body.height + (row.firstDone ? doneLabel.height + 8 : 0)

                    Text {
                        id: doneLabel
                        visible: row.firstDone
                        x: 8
                        y: 4
                        text: "Hechas"
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.family: Theme.fontText
                        font.letterSpacing: 0.4
                    }

                    Rectangle {
                        id: body
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(34, (row.editing ? editor.implicitHeight : noteText.implicitHeight) + 16)
                        radius: 9
                        color: row.editing ? Theme.surfaceContainerHigh : rowHover.hovered ? Theme.surfaceContainer : "transparent"
                        border.width: row.editing ? 1 : 0
                        border.color: Theme.alpha(Theme.accent, 0.6)

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }

                        HoverHandler { id: rowHover }

                        // The whole row checks it off, not just the box.
                        MouseArea {
                            anchors.fill: parent
                            enabled: !row.editing
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notes.toggle(row.modelData.id)
                        }

                        // The box, Obsidian's: an outline, then filled with a tick.
                        Rectangle {
                            id: box
                            x: 8
                            y: 9
                            width: 16
                            height: 16
                            radius: 5
                            color: row.checked ? Theme.accent : "transparent"
                            border.width: row.checked ? 0 : 1.5
                            border.color: rowHover.hovered ? Theme.alpha(Theme.accent, 0.8) : Theme.alpha(Theme.foreground, 0.35)

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: "\u{F012C}" // check
                                color: Theme.accentText
                                size: 12
                                scale: row.checked ? 1 : 0.4
                                opacity: row.checked ? 1 : 0

                                Behavior on scale { Elastic { small: true } }
                                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                            }
                        }

                        Text {
                            id: noteText
                            anchors.left: box.right
                            anchors.leftMargin: 10
                            anchors.right: meta.left
                            anchors.rightMargin: 8
                            y: 8
                            // A reminder ("@18:30", "@6/11 10:00") shows as a bell and its
                            // date, in the accent; red once the date has passed undone.
                            readonly property var reminder: Notes.reminderOf(row.modelData.text)
                            textFormat: Text.StyledText
                            text: {
                                var esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                                var r = noteText.reminder
                                if (!r) return esc(row.modelData.text)
                                var c = row.checked ? Theme.textMuted : Notes.reminderOverdue(r) ? Theme.error : Theme.accent
                                var i = row.modelData.text.indexOf(r.token)
                                return esc(row.modelData.text.slice(0, i))
                                    + "<font color=\"" + c + "\">\u{F009E}\u00a0\u00a0" + esc(Notes.reminderLabel(r)) + "</font>"
                                    + esc(row.modelData.text.slice(i + r.token.length))
                            }
                            color: row.checked ? Theme.textMuted : Theme.textPrimary
                            font.pixelSize: 13
                            font.family: Theme.fontText
                            font.strikeout: row.checked
                            lineHeight: 1.15
                            wrapMode: Text.Wrap
                            visible: !row.editing

                            Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                        }

                        TextEdit {
                            id: editor
                            visible: row.editing
                            anchors.left: noteText.left
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            y: noteText.y
                            color: Theme.textPrimary
                            font: noteText.font
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            selectionColor: Theme.alpha(Theme.accent, 0.35)
                            selectedTextColor: Theme.textPrimary

                            // One line in the note: Enter saves instead of breaking it.
                            Keys.onReturnPressed: row.finishEdit(true)
                            Keys.onEnterPressed: row.finishEdit(true)
                            Keys.onEscapePressed: row.finishEdit(false)
                            onActiveFocusChanged: if (!activeFocus) row.finishEdit(true)
                        }

                        // When, quietly; the delete cross takes its place on hover.
                        Item {
                            id: meta
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            y: 6
                            width: Math.max(timeText.implicitWidth, 48)
                            height: 22
                            visible: !row.editing

                            Text {
                                id: timeText
                                anchors.right: parent.right
                                anchors.rightMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: (row.modelData.dateDisplay === "Hoy" ? "" : row.modelData.dateDisplay + " ")
                                      + row.modelData.time
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontMono
                                font.features: Theme.tabular
                                opacity: rowHover.hovered ? 0 : 1

                                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                            }

                            Row {
                                anchors.right: parent.right
                                spacing: 4
                                opacity: rowHover.hovered ? 1 : 0
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }

                                Repeater {
                                    model: [
                                        { glyph: "\u{F03EB}", tint: Theme.accent, act: "edit" },   // pencil
                                        { glyph: "\u{F0156}", tint: Theme.error, act: "delete" }   // close
                                    ]

                                    Rectangle {
                                        required property var modelData
                                        width: 22
                                        height: 22
                                        radius: 7
                                        color: actMouse.containsMouse ? Theme.alpha(modelData.tint, 0.18) : "transparent"

                                        Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                        IconGlyph {
                                            anchors.centerIn: parent
                                            text: parent.modelData.glyph
                                            color: actMouse.containsMouse ? parent.modelData.tint : Theme.textSecondary
                                            size: 11
                                        }

                                        MouseArea {
                                            id: actMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: parent.modelData.act === "edit" ? row.startEdit()
                                                                                       : Notes.remove(row.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    id: vScroll
                    active: notesList.moving || vScrollHover.hovered
                    policy: notesList.contentHeight > notesList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    width: 4

                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: vScroll.pressed ? Theme.accent : Theme.alpha(Theme.foreground, 0.3)
                    }

                    HoverHandler { id: vScrollHover }
                }
            }
        }
    }
}
