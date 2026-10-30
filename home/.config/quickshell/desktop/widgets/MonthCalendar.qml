import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.desktop
import qs.services

// The clock panel's calendar, left on the desktop: the same header, weekday
// row and accent circle on today, and it turns months the same way, by the
// arrows or the wheel. Days outside the month are left blank, as there.
// Always six rows, so the card keeps its size from month to month.
WidgetCard {
    id: root

    // Re-worked out when the date turns over.
    readonly property var today: { Clock.currentDate; return new Date() }

    property int viewYear: root.today.getFullYear()
    property int viewMonth: root.today.getMonth()
    readonly property bool atToday: root.viewYear === root.today.getFullYear()
                                    && root.viewMonth === root.today.getMonth()
    property int slideDir: 1

    function show(year, month, dir) {
        root.slideDir = dir
        root.viewYear = year
        root.viewMonth = month
        slide.restart()
    }
    function shift(n) {
        var d = new Date(root.viewYear, root.viewMonth + n, 1)
        root.show(d.getFullYear(), d.getMonth(), n > 0 ? 1 : -1)
        backHome.restart()
    }
    function goToday() {
        if (root.atToday) return
        var ahead = new Date(root.viewYear, root.viewMonth, 1) > root.today
        root.show(root.today.getFullYear(), root.today.getMonth(), ahead ? -1 : 1)
    }

    // A month browsed to and left there comes back to this one after a
    // minute, and the view follows the date when the month turns over.
    Timer { id: backHome; interval: 60000; onTriggered: root.goToday() }
    onTodayChanged: if (!backHome.running) { root.viewYear = root.today.getFullYear(); root.viewMonth = root.today.getMonth() }

    readonly property var cells: {
        var first = new Date(root.viewYear, root.viewMonth, 1)
        var lead = (first.getDay() + 6) % 7
        var days = new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
        var out = []
        for (var i = 0; i < 42; i++) {
            var n = i - lead + 1
            out.push(n >= 1 && n <= days ? n : 0)
        }
        return out
    }

    readonly property real cellW: (root.width - 32) / 7

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                id: monthTitle
                Layout.fillWidth: true
                text: new Date(root.viewYear, root.viewMonth, 1).toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontText
            }

            IconButton {
                icon: "󰋚"
                visible: !root.atToday
                iconColor: Theme.textPrimary
                onTapped: root.goToday()
            }

            IconButton {
                icon: "󰅁"
                onTapped: root.shift(-1)
            }

            IconButton {
                icon: "󰅂"
                onTapped: root.shift(1)
            }
        }

        Row {
            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

                Item {
                    required property var modelData
                    width: root.cellW
                    height: 24

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.bold: true
                        font.family: Theme.fontText
                    }
                }
            }
        }

        // The days, sliding in from the side the month moved to.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (turnCooldown.running) return
                    var d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
                    if (d === 0) return
                    root.shift(d < 0 ? 1 : -1)
                    turnCooldown.restart()
                }
            }

            Timer { id: turnCooldown; interval: 180 }

            ParallelAnimation {
                id: slide
                NumberAnimation {
                    target: days; property: "x"
                    from: root.slideDir * 36; to: 0
                    duration: Theme.durMedium; easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: days; property: "opacity"
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
                id: days
                columns: 7

                Repeater {
                    model: root.cells

                    Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool weekend: index % 7 >= 5
                        readonly property bool isToday: root.atToday && modelData === root.today.getDate()
                        width: root.cellW
                        height: 34

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: height / 2
                            visible: cell.isToday
                            color: Theme.accent
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: cell.modelData > 0
                            text: cell.modelData
                            color: cell.isToday ? Theme.accentText
                                 : cell.weekend ? Theme.textSecondary : Theme.textPrimary
                            font.pixelSize: 12
                            font.bold: cell.isToday
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }
                }
            }
        }
    }
}
