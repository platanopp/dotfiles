import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The bar's clock. Tapping it expands the pill in place -- the way the status
// and control widgets behave -- into today's date over the calendar and the
// week's weather side by side.
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
    mask: bar.barHidden ? blankMask : stageMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Input only where the pill is (see PillStage).
    Region {
        id: stageMask
        item: stage
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

    // Escape closes it (AppState.dismissPanels, bound while any panel is up).
    readonly property bool escapeOpen: clockItem.panelOpen
    readonly property string escapeKey: "clock:" + (clockItem.screen ? clockItem.screen.name : "")
    onEscapeOpenChanged: AppState.setPanelOpen(clockItem.escapeKey, clockItem.escapeOpen)
    Component.onDestruction: if (clockItem.escapeOpen) AppState.setPanelOpen(clockItem.escapeKey, false)

    Connections {
        target: AppState
        function onDismissRequested() { clockItem.panelOpen = false }
    }

    readonly property int panelWidth: 568
    readonly property int calendarWidth: 294
    readonly property var dateLocale: Qt.locale("en_US")


    anchors {
        top: true
        left: true
    }
    // The content inside insets itself by 12, so the window sits back by
    // that much and the drawn edge lands exactly on Hyprland's gap.
    margins.top: Math.max(0, AppState.gapTop - 12)

    // PanelWindow anchors to edges, so centring is done by hand. Held in a
    // plain property as well as the margin: a grouped property is not
    // guaranteed to notify. The window is as wide as the open panel all the
    // time (see the stage below), so this does not move as the pill grows.
    readonly property int leftMargin: screen ? Math.round((screen.width - implicitWidth) / 2) : 0
    margins.left: leftMargin

    // Where the pill's box ends on screen, mid-move included: the notes pill
    // parks off it (pillRightOf in shell.qml).
    readonly property real visualRight: leftMargin + stage.x + stage.width

    // Breathing room between the text and the edge of the pill.
    //
    // Named rather than folded into the width below, because the arithmetic is
    // not obvious: the window is wider than the pill by the 12px inset on each
    // side of the Item that holds it. So the window has to carry 24 of chrome
    // plus twice this value, and a bare number here reads as if it were the
    // padding when it is not.
    readonly property int compactPaddingH: Theme.pillPaddingH

    // The pill's box, centred in a window as wide as the open panel -- so
    // neither the date folding out on hover nor the panel opening ever
    // resizes the window sideways; only the box inside grows, both ways from
    // the middle (see PillStage).
    PillStage {
        id: stage
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        duration: Theme.durLong
        minWindowWidth: clockItem.panelWidth
        // Centred in a 568-wide window: an even width puts both edges on
        // whole pixels.
        evenWidth: true
        targetWidth: clockItem.panelOpen ? clockItem.panelWidth
                   : compactRow.implicitWidth + 24 + clockItem.compactPaddingH * 2
        targetHeight: clockItem.panelOpen ? panelColumn.implicitHeight + 56 : 64
        // Off while the date is folding in or out: that change is animated
        // where it starts (revealDate below), and a second animation chasing
        // it here made the pill grow in stutters.
        animateWidth: !revealAnim.running
    }

    implicitWidth: stage.windowWidth
    implicitHeight: stage.windowHeight

    // ── Time only, date on hover ─────────────────────────────────────────
    //
    // At rest the pill carries the time and nothing else; the date opens out
    // beside it while the pointer is on the pill, and folds away a moment
    // after it leaves -- the moment is so that brushing the pill's edge does
    // not make it flicker. The pill is centred, so it grows both ways.
    // "Always" in Settings -> Shell keeps the date out for good.
    readonly property bool showDate: ShellSettings.clockDate === "always"
                                     || barHover.hovered || clockItem.panelOpen
    property real revealDate: 0

    Component.onCompleted: clockItem.revealDate = clockItem.showDate ? 1 : 0

    onShowDateChanged: {
        if (clockItem.showDate) {
            foldTimer.stop()
            revealAnim.to = 1
            revealAnim.restart()
        } else {
            foldTimer.restart()
        }
    }

    Timer {
        id: foldTimer
        interval: 220
        onTriggered: {
            revealAnim.to = 0
            revealAnim.restart()
        }
    }

    NumberAnimation {
        id: revealAnim
        target: clockItem
        property: "revealDate"
        duration: Theme.durLong
        easing.type: Easing.OutCubic
    }

    // -- Calendar state ---------------------------------------------------
    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    // Which way the last change of month went: the grid slides in from that
    // side (1: a later month, from the right).
    property int slideDir: 1
    signal monthTurned()

    function shiftMonth(delta) {
        slideDir = delta > 0 ? 1 : -1
        var m = viewMonth + delta
        var y = viewYear
        while (m < 0) { m += 12; y -= 1 }
        while (m > 11) { m -= 12; y += 1 }
        viewMonth = m
        viewYear = y
        monthTurned()
    }

    function resetToToday() {
        today = new Date()
        var y = today.getFullYear(), m = today.getMonth()
        if (y === viewYear && m === viewMonth) return
        slideDir = (y * 12 + m) > (viewYear * 12 + viewMonth) ? 1 : -1
        viewYear = y
        viewMonth = m
        monthTurned()
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
        anchors.fill: stage
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
            // No spacing between the time and the date: the gap lives inside
            // the date (its leading margin below), so it folds away with it.
            // A row spacing stayed behind at rest as eight pixels of padding
            // on the right of the time.
            spacing: 0
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

            // The date, folded to nothing at rest. Its width is what opens,
            // so the pill grows with it frame by frame; clipped so the text is
            // uncovered rather than squeezed.
            Item {
                Layout.preferredWidth: (dateRow.implicitWidth + 8) * clockItem.revealDate
                Layout.preferredHeight: dateRow.implicitHeight
                clip: true
                opacity: clockItem.revealDate

                RowLayout {
                    id: dateRow
                    x: 8
                    spacing: 8

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

            // -- Today --------------------------------------------------------
            //
            // Time and date only. Who is logged in, the machine and its load
            // are the control panel's header, not the calendar's.
            RowLayout {
                width: parent.width
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignBottom
                    text: AppState.currentTime
                    color: Theme.textPrimary
                    font.pixelSize: 30
                    font.bold: true
                    font.family: Theme.fontMono
                }

                Text {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 5
                    Layout.fillWidth: true
                    text: AppState.currentDate
                    color: Theme.textMuted
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
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
                            id: monthTitle
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
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

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

                    // The days, sliding in from the side the month moved to.
                    // The wheel turns months too.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: daysGrid.implicitHeight
                        clip: true

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
                        }

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                if (turnCooldown.running) return
                                var d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
                                if (d === 0) return
                                clockItem.shiftMonth(d < 0 ? 1 : -1)
                                turnCooldown.restart()
                            }
                        }

                        Timer { id: turnCooldown; interval: 180 }

                        Connections {
                            target: clockItem
                            function onMonthTurned() { monthSlide.restart() }
                        }

                        ParallelAnimation {
                            id: monthSlide
                            NumberAnimation {
                                target: daysGrid; property: "x"
                                from: clockItem.slideDir * 36; to: 0
                                duration: Theme.durMedium; easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: daysGrid; property: "opacity"
                                from: 0; to: 1
                                duration: Theme.durMedium; easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: monthTitle; property: "opacity"
                                from: 0.2; to: 1
                                duration: Theme.durMedium; easing.type: Easing.OutCubic
                            }
                        }

                    Grid {
                        id: daysGrid
                        width: parent.width
                        columns: 7
                        spacing: 0

                        Repeater {
                            model: clockItem.monthCells

                            Item {
                                id: dayCell
                                required property var modelData
                                required property int index
                                readonly property bool weekend: index % 7 >= 5

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
                                    color: dayCell.isToday ? Theme.accentText
                                         : dayCell.weekend ? Theme.textSecondary : Theme.textPrimary
                                    font.pixelSize: 12
                                    font.bold: dayCell.isToday
                                    font.family: Theme.fontMono
                                }
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
