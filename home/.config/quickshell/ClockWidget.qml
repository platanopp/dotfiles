import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The bar's clock. Tapping it expands the pill in place -- the way the status
// and control widgets behave -- into a profile header with the calendar and
// the week's weather side by side.
PanelWindow {
    id: clockItem

    property var bar: null
    screen: bar ? bar.screen : null
    visible: true

    // Hidden by cutting input and drawing nothing, never by unmapping the
    // window. Toggling visible destroys the layer surface, and Hyprland
    // restacks it on the way back: the full-width bar came back above the
    // pills and swallowed every click meant for them. The blur rule ignores
    // pixels below 0.3 alpha, so a surface drawing nothing leaves no band.
    mask: bar.barHidden ? blankMask : null

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Keeps the bar up while the pointer is on it; shell.qml folds these
    // together with the reveal zone's own hover.
    readonly property bool barHovered: barHover.hovered

    HoverHandler {
        id: barHover
    }
    color: "transparent"

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    property bool panelOpen: false

    readonly property int panelWidth: 568
    readonly property int calendarWidth: 294
    readonly property var dateLocale: Qt.locale("en_US")

    readonly property string avatarPath: Quickshell.env("HOME") + "/Pictures/fastfetch/ce96f0818cb63716e671e999de24dae9.jpg"

    anchors {
        top: true
        left: true
    }
    // The content inside insets itself by 12, so the window sits back by
    // that much and the drawn edge lands exactly on Hyprland's gap.
    margins.top: AppState.gapTop - 12

    // PanelWindow anchors to edges, so centring is done by hand. Held in a
    // plain property as well as the margin: a grouped property is not
    // guaranteed to notify, and the notes pill parks off this one.
    readonly property int leftMargin: screen ? Math.round((screen.width - implicitWidth) / 2) : 0
    margins.left: leftMargin

    implicitWidth: panelOpen ? panelWidth : compactRow.implicitWidth + 40
    implicitHeight: panelOpen ? panelColumn.implicitHeight + 56 : 64

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
    }

    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
    }

    // -- Calendar state ---------------------------------------------------
    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    function shiftMonth(delta) {
        var m = viewMonth + delta
        var y = viewYear
        while (m < 0) { m += 12; y -= 1 }
        while (m > 11) { m -= 12; y += 1 }
        viewMonth = m
        viewYear = y
    }

    function resetToToday() {
        today = new Date()
        viewYear = today.getFullYear()
        viewMonth = today.getMonth()
    }

    // Day numbers laid out Monday-first; 0 is a blank cell.
    readonly property var monthCells: {
        var first = new Date(viewYear, viewMonth, 1)
        var lead = (first.getDay() + 6) % 7
        var count = new Date(viewYear, viewMonth + 1, 0).getDate()
        var cells = []
        for (var i = 0; i < lead; i++) cells.push(0)
        for (var d = 1; d <= count; d++) cells.push(d)
        // Pad to whole weeks so the grid keeps its height month to month.
        while (cells.length % 7 !== 0) cells.push(0)
        return cells
    }

    readonly property bool viewingCurrentMonth:
        viewYear === today.getFullYear() && viewMonth === today.getMonth()

    function weekdayShort(isoDate) {
        var parts = isoDate.split("-")
        var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
        return d.toLocaleDateString(clockItem.dateLocale, "ddd").replace(".", "")
    }

    HyprlandFocusGrab {
        windows: [clockItem]
        active: clockItem.panelOpen
        onCleared: clockItem.panelOpen = false
    }

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: parent
        anchors.margins: 12

        Rectangle {
            id: panelGlass
            anchors.fill: parent
            radius: clockItem.panelOpen ? 26 : 20

            Behavior on radius {
                NumberAnimation { duration: 200 }
            }
            color: Theme.glass
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: panelGlass
            anchors.fill: panelGlass
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.5
            shadowBlur: 0.7
            shadowVerticalOffset: 4
            autoPaddingEnabled: true
        }

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: 8
            visible: !clockItem.panelOpen
            opacity: clockItem.panelOpen ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            Text {
                text: AppState.currentTime
                color: Theme.textPrimary
                font.pixelSize: 14
                font.bold: true
                font.family: Theme.fontMono
            }

            Text {
                text: "\u00b7"
                color: Theme.textMuted
                font.pixelSize: 14
                font.family: Theme.fontMono
            }

            Text {
                text: AppState.currentDate
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontMono
            }
        }

        StateLayer {
            interactive: !clockItem.panelOpen
            onTapped: {
                clockItem.resetToToday()
                clockItem.panelOpen = true
            }
        }

        Column {
            id: panelColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14
            visible: clockItem.panelOpen

            // -- Profile ------------------------------------------------------
            RowLayout {
                width: parent.width
                spacing: 14

                Item {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56

                    Rectangle {
                        id: avatarMask
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.alpha(Theme.accent, 0.6)
                    }

                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file://" + clockItem.avatarPath
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: avatarMask
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: width / 2
                        color: Theme.surfaceContainerHigh
                        visible: avatarImage.status !== Image.Ready

                        Text {
                            anchors.centerIn: parent
                            text: AppState.username.length > 0 ? AppState.username.charAt(0).toUpperCase() : "?"
                            color: Theme.accent
                            font.pixelSize: 24
                            font.bold: true
                            font.family: Theme.fontMono
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: AppState.username.length > 0 ? AppState.username : "gone"
                            color: Theme.textPrimary
                            font.pixelSize: 21
                            font.bold: true
                            font.family: Theme.fontMono
                        }

                        Text {
                            text: "@" + AppState.hostname
                            color: Theme.accent
                            font.pixelSize: 13
                            font.family: Theme.fontMono
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 2
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Text {
                        text: "~/dev · " + AppState.distro
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.topMargin: 3
                        spacing: 6

                        Repeater {
                            model: [
                                { icon: "󰅐", value: AppState.uptimeText },
                                { icon: "󰍛", value: Math.round(AppState.ramPercent) + "%" },
                                { icon: "󰻠", value: Math.round(AppState.cpuPercent) + "%" }
                            ]

                            Rectangle {
                                id: chip
                                required property var modelData

                                visible: modelData.value.length > 0
                                implicitWidth: chipRow.implicitWidth + 16
                                implicitHeight: 20
                                radius: 10
                                color: Theme.surfaceContainer

                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    IconGlyph {
                                        text: chip.modelData.icon
                                        color: Theme.accent
                                        size: Theme.iconTiny
                                    }

                                    Text {
                                        text: chip.modelData.value
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontMono
                                    }
                                }
                            }
                        }
                    }
                }

                // There is width to spare here, so the clock gets to be the
                // anchor it is on the bar.
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: AppState.currentTime
                        color: Theme.textPrimary
                        font.pixelSize: 30
                        font.bold: true
                        font.family: Theme.fontMono
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: AppState.currentDate
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outline
            }

            // -- Calendar and weather, side by side ---------------------------
            RowLayout {
                width: parent.width
                spacing: 18

                ColumnLayout {
                    Layout.preferredWidth: clockItem.calendarWidth
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: new Date(clockItem.viewYear, clockItem.viewMonth, 1)
                                    .toLocaleDateString(clockItem.dateLocale, "MMMM yyyy")
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.bold: true
                            font.capitalization: Font.Capitalize
                            font.family: Theme.fontMono
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "󰋚"
                            visible: !clockItem.viewingCurrentMonth
                            iconColor: Theme.accent
                            onTapped: clockItem.resetToToday()
                        }

                        IconButton {
                            icon: "󰅁"
                            onTapped: clockItem.shiftMonth(-1)
                        }

                        IconButton {
                            icon: "󰅂"
                            onTapped: clockItem.shiftMonth(1)
                        }
                    }

                    Grid {
                        Layout.fillWidth: true
                        columns: 7
                        spacing: 0

                        Repeater {
                            model: ["L", "M", "X", "J", "V", "S", "D"]

                            Item {
                                id: weekdayCell
                                required property var modelData
                                width: clockItem.calendarWidth / 7
                                height: 24

                                Text {
                                    anchors.centerIn: parent
                                    text: weekdayCell.modelData
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: Theme.fontMono
                                }
                            }
                        }
                    }

                    Grid {
                        Layout.fillWidth: true
                        columns: 7
                        spacing: 0

                        Repeater {
                            model: clockItem.monthCells

                            Item {
                                id: dayCell
                                required property var modelData

                                readonly property bool isToday:
                                    clockItem.viewingCurrentMonth && modelData === clockItem.today.getDate()

                                width: clockItem.calendarWidth / 7
                                height: 38

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 30
                                    height: 30
                                    radius: 15
                                    visible: dayCell.isToday
                                    color: Theme.accent
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: dayCell.modelData > 0
                                    text: dayCell.modelData
                                    color: dayCell.isToday ? Theme.accentText : Theme.textPrimary
                                    font.pixelSize: 12
                                    font.bold: dayCell.isToday
                                    font.family: Theme.fontMono
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Weather"
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.bold: true
                            font.family: Theme.fontMono
                        }

                        Text {
                            text: Weather.city
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontMono
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "󰑐"
                            interactive: !Weather.loading
                            onTapped: Weather.refresh()
                        }
                    }

                    Text {
                        visible: !Weather.ready
                        Layout.fillWidth: true
                        text: Weather.loading ? "Fetching the forecast..."
                            : (Weather.error.length > 0 ? "No forecast: " + Weather.error : "No data")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        visible: Weather.ready
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        radius: 18
                        color: Theme.surfaceContainer

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Text {
                                text: Weather.icon(Weather.code, Weather.isDay)
                                color: Theme.accent
                                font.pixelSize: 30
                                font.family: Theme.fontMono
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: Math.round(Weather.temp) + "°"
                                    color: Theme.textPrimary
                                    font.pixelSize: 22
                                    font.bold: true
                                    font.family: Theme.fontMono
                                }

                                Text {
                                    text: Weather.describe(Weather.code)
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            ColumnLayout {
                                spacing: 2

                                RowLayout {
                                    spacing: 4

                                    IconGlyph {
                                        text: "󰖎"
                                        color: Theme.textMuted
                                        size: Theme.iconTiny
                                    }

                                    Text {
                                        text: Weather.humidity + "%"
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        font.family: Theme.fontMono
                                    }
                                }

                                RowLayout {
                                    spacing: 4

                                    IconGlyph {
                                        text: "󰖝"
                                        color: Theme.textMuted
                                        size: Theme.iconTiny
                                    }

                                    Text {
                                        text: Math.round(Weather.wind) + " km/h"
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        font.family: Theme.fontMono
                                    }
                                }
                            }
                        }
                    }

                    // One row per day, so the labels have room to breathe.
                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                    Repeater {
                        model: Weather.ready ? Weather.days : []

                        Rectangle {
                            id: dayRow
                            required property var modelData
                            required property int index

                            width: parent.width
                            height: 26
                            radius: 8
                            color: index === 0 ? Theme.alpha(Theme.accent, 0.14) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    Layout.preferredWidth: 30
                                    text: dayRow.index === 0 ? "today" : clockItem.weekdayShort(dayRow.modelData.date)
                                    color: dayRow.index === 0 ? Theme.accent : Theme.textSecondary
                                    font.pixelSize: 10
                                    font.bold: dayRow.index === 0
                                    font.family: Theme.fontMono
                                }

                                Text {
                                    text: Weather.icon(dayRow.modelData.code, true)
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: Theme.fontMono
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Math.round(dayRow.modelData.max) + "°"
                                    color: Theme.textPrimary
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: Theme.fontMono
                                }

                                Text {
                                    Layout.preferredWidth: 26
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(dayRow.modelData.min) + "°"
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontMono
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
