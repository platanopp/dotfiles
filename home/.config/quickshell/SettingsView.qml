import Quickshell
import QtQuick
import QtQuick.Layouts

// The Settings window's contents: pages down the left, the open page on the
// right. It is not a window of its own -- the control panel grows into it
// (see ControlPanel.qml), which is why it has a way back as well as a way
// out.
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
        { group: "Display", items: [
            { id: "displays", label: "Displays", icon: "\u{F0379}",
              title: "Displays", subtitle: "Arrangement, resolution and refresh rate for each screen" },
            { id: "colour", label: "Colour", icon: "\u{F03D8}",
              title: "Colour", subtitle: "Saturation, temperature, brightness and gamma" }
        ] },
        { group: "System", items: [
            { id: "power", label: "Power & idle", icon: "\u{F0241}",
              title: "Power & idle", subtitle: "Performance, and what happens when you step away" }
        ] }
    ]

    readonly property var current: {
        for (var g = 0; g < view.nav.length; g++)
            for (var i = 0; i < view.nav[g].items.length; i++)
                if (view.nav[g].items[i].id === view.page) return view.nav[g].items[i]
        return view.nav[0].items[0]
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Pages ────────────────────────────────────────────────────────
        ColumnLayout {
            // Pinned: a layout whose children fill their width fills its own
            // too, whatever its preferred width says -- and this one took the
            // whole window, leaving the page a sliver at the edge.
            Layout.fillWidth: false
            Layout.preferredWidth: 210
            Layout.minimumWidth: 210
            Layout.maximumWidth: 210
            Layout.fillHeight: true
            Layout.topMargin: 14
            Layout.bottomMargin: 14
            Layout.leftMargin: 12
            Layout.rightMargin: 10
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 18
                Layout.leftMargin: 2
                spacing: 10

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

                IconGlyph {
                    text: "\u{F385}"
                    size: Theme.iconLarge
                    color: Theme.textPrimary
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
                    spacing: 2

                    Text {
                        Layout.leftMargin: 14
                        Layout.topMargin: navGroup.index > 0 ? 16 : 0
                        Layout.bottomMargin: 4
                        text: navGroup.modelData.group
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.letterSpacing: 1.2
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
                            Layout.preferredHeight: 42
                            radius: 21
                            color: navItem.chosen ? Theme.alpha(Theme.accent, 0.16) : "transparent"

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            // The chosen page gets a bar in the accent at its
                            // start as well as the fill: the fill alone is a
                            // light grey over glass, easy to lose.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: navItem.chosen ? 18 : 0
                                radius: 1.5
                                color: Theme.accent

                                Behavior on height { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 12
                                spacing: 12

                                IconGlyph {
                                    text: navItem.modelData.icon
                                    size: Theme.iconMedium
                                    color: navItem.chosen ? Theme.textPrimary : Theme.textSecondary
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
                            }

                            StateLayer {
                                radius: navItem.radius
                                interactive: !navItem.chosen
                                onTapped: view.page = navItem.modelData.id
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                text: "Changes apply as you make them."
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontMono
                wrapMode: Text.WordWrap
            }
        }

        // ── The open page ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            Layout.rightMargin: 10
            radius: 22
            color: Theme.alpha(Theme.foreground, 0.035)

            // The page's title stays put; only what is under it scrolls. With
            // the title scrolling too, the close button ended up floating over
            // the cards.
            Item {
                id: pageHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 24
                anchors.leftMargin: 28
                anchors.rightMargin: 72
                height: headerColumn.implicitHeight

                Column {
                    id: headerColumn
                    width: parent.width
                    spacing: 4

                    Text {
                        text: view.current.title
                        color: Theme.textPrimary
                        font.pixelSize: 22
                        font.bold: true
                        font.family: Theme.fontMono
                    }

                    Text {
                        width: parent.width
                        text: view.current.subtitle
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.fontMono
                        wrapMode: Text.WordWrap
                    }
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
                anchors.leftMargin: 28
                anchors.rightMargin: 28
                contentHeight: pageLoader.height + 24
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Loader {
                    id: pageLoader
                    width: scroller.width
                    source: view.page === "colour" ? "SettingsPageColour.qml"
                          : view.page === "power" ? "SettingsPagePower.qml"
                          : "SettingsPageDisplays.qml"

                    onLoaded: {
                        item.width = Qt.binding(() => pageLoader.width)
                        scroller.contentY = 0
                        arrive.restart()
                    }

                    // Each page comes in with a short rise and fade, so
                    // switching reads as a change of page rather than the
                    // same card redrawing itself.
                    transform: Translate { id: rise }

                    ParallelAnimation {
                        id: arrive
                        NumberAnimation { target: pageLoader; property: "opacity"; from: 0; to: 1; duration: Theme.durMedium; easing.type: Easing.OutCubic }
                        NumberAnimation { target: rise; property: "y"; from: 10; to: 0; duration: Theme.durMedium; easing.type: Easing.OutCubic }
                    }
                }
            }

            // Out, as opposed to back.
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 16
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
        }
    }
}
