import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// The session lock's face. Every piece of state it draws -- PAM's turn, the
// attempt ledger read back off faillock, Caps Lock, the keyboard layout,
// battery, network, Bluetooth -- belongs to LockEngine; nothing is decided
// here.
//
// Laid out as a single centred column: the clock, the field and the status
// line share one axis, so the eye never leaves the place the typing goes. The
// glanceable chips are pushed to the corners, where they can be read without
// competing with the field, and they fade back when the field is in use.
Scope {
    id: root

    WlSessionLock {
        id: session
        locked: LockEngine.locked

        // Handed back to the engine so anything that must not happen over a
        // visible desktop can wait for the compositor's answer rather than for
        // the request -- AppState's suspend is the one that cares.
        onSecureChanged: LockEngine.secured = session.secure

        surface: WlSessionLockSurface {
            id: pane
            color: "black"

            // The engine decides, and moves Hyprland's focus to the same
            // screen just before locking so the keyboard follows the card --
            // see fieldMonitor there. If it could not name a screen at all,
            // every surface draws the field rather than none of them.
            readonly property bool primary: LockEngine.fieldMonitor === ""
                || !pane.screen || pane.screen.name === LockEngine.fieldMonitor

            // ── Backdrop ─────────────────────────────────────────────────
            //
            // The lock draws its own copy of the wallpaper. A lock surface
            // covers the output completely, so there is nothing behind it to
            // let through -- what is not painted here is the black above.
            Item {
                id: stage
                anchors.fill: parent

                // Faded in on arrival and out on the way home, and then the
                // engine is told it may drop the lock. Its deadman is 2s, so
                // this has to stay comfortably shorter or the release would
                // race it.
                //
                // `shown` exists because a Behavior does not animate the value
                // an item is born with: without it the surface would appear at
                // full opacity and only the exit would be soft.
                property bool shown: false

                Component.onCompleted: stage.shown = true

                opacity: (LockEngine.leaving || !stage.shown) ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                        onRunningChanged: {
                            if (!running && LockEngine.leaving)
                                LockEngine.release()
                        }
                    }
                }

                Image {
                    id: shot
                    anchors.fill: parent
                    source: LockEngine.wallpaper.length > 0 ? "file://" + LockEngine.wallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: shot
                    blurEnabled: shot.status === Image.Ready
                    blurMax: 64
                    // Deepens once typing starts, so while a password is on
                    // screen the card is the only thing still in focus.
                    blur: LockEngine.focused ? 1.0 : 0.6

                    Behavior on blur {
                        NumberAnimation { duration: Theme.durExtraLong; easing.type: Easing.OutCubic }
                    }
                }

                // Nothing loaded yet, or no wallpaper set: the scrim alone is
                // the backdrop, and it must not be see-through.
                Rectangle {
                    anchors.fill: parent
                    color: Theme.alpha(Theme.background,
                        shot.status !== Image.Ready ? 1.0 : (LockEngine.focused ? 0.62 : 0.4))

                    Behavior on color { ColorAnimation { duration: Theme.durExtraLong } }
                }

                // ── The column ───────────────────────────────────────────
                ColumnLayout {
                    id: column
                    anchors.centerIn: parent
                    width: Math.min(520, pane.width - 96)
                    spacing: 0

                    // Clock. One line rather than stacked: at this size the
                    // hour and minute read as a single number, and stacking
                    // them spends the vertical room the field wants.
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Text {
                            text: LockEngine.hourText + ":" + LockEngine.minuteText
                            color: Theme.textPrimary
                            font.family: Theme.fontMono
                            font.pixelSize: 104
                            font.weight: Font.Light
                        }

                        Text {
                            visible: LockEngine.meridiem.length > 0
                            text: LockEngine.meridiem
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 18
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 20
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -4
                        text: LockEngine.dateText
                        color: Theme.textSecondary
                        font.family: Theme.fontMono
                        font.pixelSize: 14
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        // The greeting stands in for the field on the screens
                        // that do not have it, so it stays either way.
                        text: LockEngine.greeting + (pane.primary ? "" : ", " + LockEngine.displayName)
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    // ── Password ─────────────────────────────────────────
                    Rectangle {
                        id: fieldPill
                        visible: pane.primary
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 36
                        Layout.preferredWidth: 340
                        Layout.preferredHeight: 52
                        radius: 26
                        color: LockEngine.cardHigh
                        border.width: 1
                        border.color: LockEngine.lockedOut ? Theme.alpha(Theme.error, 0.7)
                                    : field.activeFocus ? Theme.alpha(Theme.accent, 0.55)
                                    : LockEngine.hairline

                        Behavior on border.color { ColorAnimation { duration: Theme.durMedium } }

                        // A wrong password shoves the pill sideways once. It
                        // is the one piece of feedback that needs no reading.
                        //
                        // Through a transform rather than x: the pill is a
                        // layout child, so its x belongs to the ColumnLayout
                        // and animating it would fight whatever the layout
                        // wants -- and every step's `to` would be read off a
                        // coordinate the step before it had already moved.
                        transform: Translate {
                            id: nudge
                        }

                        SequentialAnimation {
                            id: shake
                            NumberAnimation { target: nudge; property: "x"; to: -9; duration: 55 }
                            NumberAnimation { target: nudge; property: "x"; to: 9; duration: 55 }
                            NumberAnimation { target: nudge; property: "x"; to: -5; duration: 55 }
                            NumberAnimation { target: nudge; property: "x"; to: 0; duration: 55 }
                        }

                        Connections {
                            target: LockEngine
                            function onFailed() {
                                field.text = ""
                                shake.restart()
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 8
                            spacing: 10

                            IconGlyph {
                                text: LockEngine.lockedOut ? "\u{F0026}" : "\u{F033E}"
                                color: LockEngine.lockedOut ? Theme.error : Theme.textMuted
                                size: Theme.iconMedium
                            }

                            TextInput {
                                id: field
                                Layout.fillWidth: true
                                enabled: LockEngine.acceptsInput
                                // PAM can ask a question whose answer is not a
                                // secret; it says so, and the field obeys.
                                echoMode: LockEngine.secret ? TextInput.Password : TextInput.Normal
                                passwordCharacter: "•"
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: 15
                                verticalAlignment: TextInput.AlignVCenter
                                focus: true
                                clip: true

                                // The engine drives the blur and the step-back
                                // off this, so it hears the first keystroke.
                                onTextChanged: if (text.length > 0) LockEngine.engage()
                                onAccepted: { LockEngine.submit(text); text = "" }

                                // Refocused whenever the field can be used
                                // again: PAM taking a turn disables it, and a
                                // disabled item drops focus for good.
                                Connections {
                                    target: LockEngine
                                    function onAcceptsInputChanged() {
                                        if (LockEngine.acceptsInput && LockEngine.locked)
                                            field.forceActiveFocus()
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: field.text.length === 0
                                    text: LockEngine.lockedOut ? "Locked"
                                        : LockEngine.prompt.length > 0 ? LockEngine.prompt
                                        : "Password"
                                    color: Theme.textMuted
                                    font: field.font
                                }
                            }

                            // Submit. Carries the spinner too: the wait belongs
                            // to the button that started it, and putting it
                            // here keeps the status line for words.
                            Rectangle {
                                id: submitBtn
                                readonly property bool ready: field.text.length > 0 && LockEngine.acceptsInput
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: 19
                                color: submitBtn.ready ? Theme.accent : "transparent"

                                Behavior on color { ColorAnimation { duration: Theme.durMedium } }

                                IconGlyph {
                                    anchors.centerIn: parent
                                    visible: !LockEngine.busy
                                    text: "\u{F0054}"
                                    color: submitBtn.ready ? Theme.accentText : Theme.textMuted
                                    size: Theme.iconMedium
                                }

                                // A gap in a ring, spun. Cheaper than pulling
                                // in an animated image and it takes its colour
                                // from the theme.
                                Item {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    visible: LockEngine.busy

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Theme.alpha(Theme.accent, 0.25)
                                    }

                                    Rectangle {
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: Theme.accent
                                        x: parent.width / 2 - 2.5
                                        y: -1
                                        transformOrigin: Item.Center
                                    }

                                    RotationAnimation on rotation {
                                        running: LockEngine.busy
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 850
                                    }
                                }

                                StateLayer {
                                    interactive: submitBtn.ready
                                    onTapped: { LockEngine.submit(field.text); field.text = "" }
                                }
                            }
                        }
                    }

                    // ── The one line under the field ─────────────────────
                    //
                    // Everything PAM has to say goes here: its own wording for
                    // whatever it asked, how many tries are left, and the
                    // faillock countdown. Colour carries the severity so the
                    // sentence does not have to.
                    //
                    // Height is held whether or not there is text, so the
                    // column does not jump every time a message appears.
                    Item {
                        visible: pane.primary
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 14
                        Layout.preferredWidth: 400
                        Layout.preferredHeight: Math.max(18, status.implicitHeight)

                        Text {
                            id: status
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: LockEngine.statusText
                            opacity: text.length > 0 ? 1 : 0
                            color: LockEngine.statusKind === "error" ? Theme.error
                                 : LockEngine.statusKind === "good" ? Theme.success
                                 : Theme.textSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: 12

                            Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
                        }
                    }

                    // Caps Lock and the layout. Only worth the room when they
                    // are not what the fingers assume -- a wrong layout is the
                    // quietest way for a correct password to keep failing.
                    RowLayout {
                        visible: pane.primary && (LockEngine.capsLock || LockEngine.layoutShort.length > 0)
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        spacing: 8

                        Rectangle {
                            visible: LockEngine.capsLock
                            Layout.preferredWidth: capsLabel.implicitWidth + 22
                            Layout.preferredHeight: 24
                            radius: 12
                            color: Theme.alpha(Theme.warning, 0.16)
                            border.width: 1
                            border.color: Theme.alpha(Theme.warning, 0.4)

                            Text {
                                id: capsLabel
                                anchors.centerIn: parent
                                text: "CAPS"
                                color: Theme.warning
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        Rectangle {
                            visible: LockEngine.layoutShort.length > 0
                            Layout.preferredWidth: layoutRow.implicitWidth + 20
                            Layout.preferredHeight: 24
                            radius: 12
                            color: LockEngine.card
                            border.width: 1
                            border.color: LockEngine.hairline

                            RowLayout {
                                id: layoutRow
                                anchors.centerIn: parent
                                spacing: 6

                                IconGlyph {
                                    text: "\u{F030C}"
                                    color: Theme.textMuted
                                    size: Theme.iconTiny
                                }

                                Text {
                                    text: LockEngine.layoutShort
                                    color: Theme.textSecondary
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                // ── Who is being asked, top left ─────────────────────────
                //
                // Out of the column on purpose: the column is the transaction,
                // and the name is a label on it. It also stops the corner from
                // sitting empty opposite the chips.
                RowLayout {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 28
                    spacing: 10
                    visible: pane.primary && LockEngine.displayName.length > 0
                    opacity: LockEngine.focused ? 0.45 : 1

                    Behavior on opacity { NumberAnimation { duration: Theme.durExtraLong } }

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: Theme.alpha(Theme.accent, 0.2)
                        border.width: 1
                        border.color: Theme.alpha(Theme.accent, 0.4)

                        Text {
                            anchors.centerIn: parent
                            text: LockEngine.initials
                            color: Theme.textPrimary
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    Text {
                        text: LockEngine.displayName
                        color: Theme.textSecondary
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }
                }

                // ── Glance chips, top right ──────────────────────────────
                //
                // State worth a look, not part of signing in: kept out of the
                // column so the clock stays on the optical middle, and dimmed
                // while the field is in use.
                RowLayout {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 28
                    spacing: 8
                    opacity: LockEngine.focused ? 0.45 : 1

                    Behavior on opacity { NumberAnimation { duration: Theme.durExtraLong } }

                    Repeater {
                        model: [
                            {
                                "show": LockEngine.hasBattery,
                                "glyph": LockEngine.charging ? "\u{F0084}" : "\u{F0079}",
                                "label": LockEngine.batteryPercent + "%",
                                "alert": LockEngine.batteryLow
                            },
                            {
                                "show": LockEngine.netLabel.length > 0,
                                "glyph": LockEngine.netGlyph === "ethernet" ? "\u{F0200}"
                                       : LockEngine.netGlyph === "wifi" ? "\u{F05A9}"
                                       : "\u{F05AA}",
                                "label": LockEngine.netLabel,
                                "alert": false
                            },
                            {
                                "show": LockEngine.btOn && LockEngine.btLabel.length > 0,
                                "glyph": "\u{F00AF}",
                                "label": LockEngine.btLabel,
                                "alert": false
                            }
                        ]

                        Rectangle {
                            id: chip
                            required property var modelData

                            visible: chip.modelData.show
                            Layout.preferredWidth: chipRow.implicitWidth + 22
                            Layout.preferredHeight: 30
                            radius: 15
                            color: LockEngine.card
                            border.width: 1
                            border.color: LockEngine.hairline

                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 7

                                IconGlyph {
                                    text: chip.modelData.glyph
                                    color: chip.modelData.alert ? Theme.error : Theme.textSecondary
                                    size: Theme.iconSmall
                                }

                                Text {
                                    text: chip.modelData.label
                                    color: chip.modelData.alert ? Theme.error : Theme.textSecondary
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 150
                                }
                            }
                        }
                    }
                }

                // ── Power, bottom centre ─────────────────────────────────
                //
                // The engine marks which of these are worth a second thought.
                // Those arm on the first tap and run on the second, and arming
                // one disarms the last -- a lock screen is exactly where a
                // stray click must not end the session. Suspend does not ask:
                // it costs nothing and is the one most likely to be wanted.
                RowLayout {
                    id: powerRow
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 36
                    spacing: 8
                    visible: pane.primary
                    opacity: LockEngine.focused ? 0.45 : 1

                    property string armed: ""

                    Behavior on opacity { NumberAnimation { duration: Theme.durExtraLong } }

                    Timer {
                        id: disarm
                        interval: 4000
                        onTriggered: powerRow.armed = ""
                    }

                    Repeater {
                        model: LockEngine.powerActions

                        Rectangle {
                            id: powerBtn
                            required property var modelData

                            readonly property bool isArmed: powerRow.armed === powerBtn.modelData.id

                            Layout.preferredWidth: powerBtn.isArmed ? confirmLabel.implicitWidth + 32 : 44
                            Layout.preferredHeight: 44
                            radius: 22
                            color: powerBtn.isArmed ? Theme.alpha(Theme.error, 0.9) : LockEngine.card
                            border.width: 1
                            border.color: powerBtn.isArmed ? Theme.error : LockEngine.hairline

                            Behavior on Layout.preferredWidth {
                                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
                            }

                            Behavior on color { ColorAnimation { duration: Theme.durMedium } }

                            IconGlyph {
                                anchors.centerIn: parent
                                visible: !powerBtn.isArmed
                                text: {
                                    var id = powerBtn.modelData.id
                                    if (id === "suspend")   return "\u{F04B2}"
                                    if (id === "hibernate") return "\u{F0717}"
                                    if (id === "logout")    return "\u{F0343}"
                                    if (id === "reboot")    return "\u{F0709}"
                                    return "\u{F0425}"
                                }
                                color: Theme.textSecondary
                                size: Theme.iconMedium
                            }

                            Text {
                                id: confirmLabel
                                anchors.centerIn: parent
                                visible: powerBtn.isArmed
                                text: powerBtn.modelData.label + "?"
                                color: Theme.foreground
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                                font.bold: true
                            }

                            StateLayer {
                                onTapped: {
                                    if (!powerBtn.modelData.confirm || powerBtn.isArmed) {
                                        powerRow.armed = ""
                                        disarm.stop()
                                        LockEngine.runPower(powerBtn.modelData.id)
                                    } else {
                                        powerRow.armed = powerBtn.modelData.id
                                        disarm.restart()
                                    }
                                }
                            }
                        }
                    }
                }

                // Clicking anywhere crosses from the glance into the field, the
                // same as typing does. Last child so it sits under nothing --
                // it only takes presses the controls above did not want.
                TapHandler {
                    onTapped: {
                        LockEngine.engage()
                        if (pane.primary && LockEngine.acceptsInput)
                            field.forceActiveFocus()
                    }
                }
            }
        }
    }
}
