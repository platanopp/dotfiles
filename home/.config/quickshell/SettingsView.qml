import Quickshell
import QtQuick
import QtQuick.Layouts

// The Settings window's contents: pages down the left, the open page on the
// right. It is not a window of its own -- the control panel grows into it (see
// ControlPanel.qml), which is why it has a way back as well as a way out.
//
// Monochrome: one accent, the shell's own light grey, for everything chosen
// or filled -- the same language as the control panel's toggles. Pages tell
// themselves apart by their icons, not by colour; a colour per page was tried
// and the colours did not sit together.
//
// Only pages with something real behind them. Every control here drives a
// script that changes the machine; none of them is there to fill the list.
Item {
    id: view

    property string page: "displays"
    property string hostName: ""
    signal backRequested()
    signal closeRequested()

    readonly property var nav: [
        { group: "Devices", items: [
            { id: "displays", label: "Displays", icon: "\u{F037A}", file: "SettingsPageDisplays.qml" },
            { id: "colour", label: "Colour", icon: "\u{F03D8}", file: "SettingsPageColour.qml" },
            { id: "sound", label: "Sound", icon: "\u{F057E}", file: "SettingsPageSound.qml" }
        ] },
        { group: "Hyprland", items: [
            { id: "look", label: "Look", icon: "\u{F05B2}", file: "SettingsPageLook.qml" },
            { id: "input", label: "Input", icon: "\u{F037D}", file: "SettingsPageInput.qml" }
        ] },
        { group: "System", items: [
            { id: "profile", label: "Profile", icon: "\u{F0004}", file: "SettingsPageProfile.qml" },
            { id: "shell", label: "Shell", icon: "\u{F10AC}", file: "SettingsPageShell.qml" },
            { id: "power", label: "Power & idle", icon: "\u{F0241}", file: "SettingsPagePower.qml" },
            { id: "about", label: "About", icon: "\u{F02FD}", file: "SettingsPageAbout.qml" }
        ] }
    ]

    readonly property var current: {
        for (var g = 0; g < view.nav.length; g++)
            for (var i = 0; i < view.nav[g].items.length; i++)
                if (view.nav[g].items[i].id === view.page) return view.nav[g].items[i]
        return view.nav[0].items[0]
    }

    Component.onCompleted: AppState.refreshHypr()
    onPageChanged: if (view.page === "look" || view.page === "input") AppState.refreshHypr()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Pages ────────────────────────────────────────────────────────
        ColumnLayout {
            // Pinned: a layout whose children fill their width fills its own
            // too, whatever its preferred width says.
            Layout.fillWidth: false
            Layout.preferredWidth: 212
            Layout.minimumWidth: 212
            Layout.maximumWidth: 212
            Layout.fillHeight: true
            Layout.topMargin: 14
            Layout.bottomMargin: 12
            Layout.leftMargin: 12
            Layout.rightMargin: 10
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 16
                spacing: 8

                // Back to the control panel this grew out of.
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: backState.hovered ? Theme.surfaceContainerHigh : "transparent"

                    IconGlyph {
                        anchors.centerIn: parent
                        text: "\u{F004D}"
                        size: Theme.iconMedium
                        color: Theme.textPrimary
                    }

                    StateLayer {
                        id: backState
                        onTapped: view.backRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: Theme.accent

                    IconGlyph {
                        anchors.centerIn: parent
                        text: "\u{F385}"
                        size: Theme.iconMedium
                        color: Theme.accentText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Settings"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                        font.family: Theme.fontMono
                    }

                    Text {
                        Layout.fillWidth: true
                        text: view.hostName
                        visible: text.length > 0
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                    }
                }
            }

            Repeater {
                model: view.nav

                ColumnLayout {
                    id: navGroup
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.leftMargin: 12
                        Layout.topMargin: navGroup.index > 0 ? 14 : 0
                        Layout.bottomMargin: 3
                        text: navGroup.modelData.group
                        color: Theme.textMuted
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.4
                        font.capitalization: Font.AllUppercase
                        font.family: Theme.fontMono
                    }

                    Repeater {
                        model: navGroup.modelData.items

                        Rectangle {
                            id: navItem
                            required property var modelData
                            readonly property bool chosen: view.page === navItem.modelData.id

                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 14
                            color: navItem.chosen ? Theme.alpha(Theme.accent, 0.14)
                                 : navState.hovered ? Theme.surfaceContainer : "transparent"

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 10
                                spacing: 11

                                TintBadge {
                                    icon: navItem.modelData.icon
                                    tint: Theme.accent
                                    box: 30
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: navItem.modelData.label
                                    color: navItem.chosen ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: 12
                                    font.bold: navItem.chosen
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    visible: navItem.chosen
                                    Layout.preferredWidth: 6
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: Theme.accent
                                }
                            }

                            StateLayer {
                                id: navState
                                radius: navItem.radius
                                interactive: !navItem.chosen
                                onTapped: view.page = navItem.modelData.id
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ── The open page ────────────────────────────────────────────────
        Rectangle {
            id: pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            Layout.rightMargin: 10
            radius: 24
            color: Theme.alpha(Theme.foreground, 0.035)

            // The page's title stays put; only what is under it scrolls.
            RowLayout {
                id: pageHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 22
                anchors.leftMargin: 26
                anchors.rightMargin: 72
                spacing: 14

                TintBadge {
                    icon: view.current.icon
                    tint: Theme.accent
                    box: 46
                }

                Text {
                    Layout.fillWidth: true
                    text: view.current.label
                    color: Theme.textPrimary
                    font.pixelSize: 22
                    font.bold: true
                    font.family: Theme.fontMono
                }
            }

            // A hairline where the cards pass under the title, only once they
            // actually do.
            Rectangle {
                anchors.top: scroller.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.outline
                opacity: scroller.contentY > 2 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
            }

            Flickable {
                id: scroller
                anchors.top: pageHeader.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 18
                anchors.bottomMargin: 10
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                contentHeight: pageLoader.height + 70
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Loader {
                    id: pageLoader
                    width: scroller.width
                    source: view.current.file

                    onLoaded: {
                        item.width = Qt.binding(() => pageLoader.width)
                        scroller.contentY = 0
                        arrive.restart()
                    }

                    // Each page comes in with a short rise and fade. The rise
                    // is a transform: the Flickable owns this item's y.
                    transform: Translate { id: rise }

                    ParallelAnimation {
                        id: arrive
                        NumberAnimation { target: pageLoader; property: "opacity"; from: 0; to: 1; duration: Theme.durMedium; easing.type: Easing.OutCubic }
                        NumberAnimation { target: rise; property: "y"; from: 12; to: 0; duration: Theme.durMedium; easing.type: Easing.OutCubic }
                    }
                }
            }

            // Out, as opposed to back.
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 18
                width: 34
                height: 34
                radius: 17
                color: closeState.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F0156}"
                    size: Theme.iconSmall
                    color: Theme.textPrimary
                }

                StateLayer {
                    id: closeState
                    onTapped: view.closeRequested()
                }
            }

            // ── What happened to the last Hyprland change ────────────────
            //
            // Applied and committed, or refused and rolled back -- said once,
            // at the bottom, then gone.
            Rectangle {
                id: toast
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: toast.shown ? 18 : -height - 4
                width: Math.min(parent.width - 40, toastRow.implicitWidth + 28)
                height: 40
                radius: 20
                color: Theme.alpha(Theme.background, 0.94)
                border.width: 1
                border.color: Theme.alpha(toast.good ? Theme.success : Theme.error, 0.5)

                property bool shown: false
                // Not merely moved out of sight: parked below the pane it
                // still showed through, and with no result yet it wore the
                // error's red.
                visible: toast.shown || toastSlide.running
                readonly property var last: AppState.hyprLast
                readonly property bool good: toast.last !== null && toast.last.ok === true

                onLastChanged: if (toast.last) { toast.shown = true; hideToast.restart() }

                Behavior on anchors.bottomMargin { NumberAnimation { id: toastSlide; duration: Theme.durMedium; easing.type: Easing.OutCubic } }

                Timer {
                    id: hideToast
                    interval: 4200
                    onTriggered: toast.shown = false
                }

                RowLayout {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 9

                    IconGlyph {
                        text: toast.good ? "\u{F05E0}" : "\u{F0028}"
                        size: Theme.iconSmall
                        color: toast.good ? Theme.success : Theme.error
                    }

                    Text {
                        Layout.maximumWidth: pane.width - 110
                        elide: Text.ElideRight
                        text: {
                            var l = toast.last
                            if (!l) return ""
                            if (!l.ok) return "Not applied, rolled back · " + (l.error || "")
                            if (l.commit && l.commit.committed) return "Applied · saved as " + l.commit.hash
                            return "Applied"
                        }
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                    }
                }
            }
        }
    }
}
