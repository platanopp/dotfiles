import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// System tray: background apps that publish a StatusNotifierItem (Discord,
// Steam, Telegram and friends) appear here on their own, the way they do in
// Waybar. Quickshell registers the host, so nothing else needs to run.
RowLayout {
    id: root

    // Window the item menus are anchored to.
    property var menuWindow: null

    spacing: 8
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItem
            required property var modelData

            Layout.preferredWidth: 22
            Layout.preferredHeight: 22

            // Qt happily loads the theme's "missing icon" graphic and reports
            // Ready, so a broken name has to be caught by asking the theme
            // whether it actually has it.
            readonly property bool iconAvailable: {
                var src = String(trayItem.modelData.icon || "")
                if (src.length === 0) return false
                var prefix = "image://icon/"
                if (src.indexOf(prefix) !== 0) return true
                var name = src.substring(prefix.length)
                var query = name.indexOf("?")
                // A ?path= form points at the app's own directory; trust it.
                if (query !== -1) return true
                return Quickshell.iconPath(name, true).length > 0
            }

            IconImage {
                id: trayIcon
                anchors.centerIn: parent
                implicitSize: 18
                mipmap: true
                source: trayItem.modelData.icon
                visible: trayItem.iconAvailable
            }

            // Apps sometimes name an icon the theme does not ship; without
            // this the item renders as a broken-image placeholder.
            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: 6
                visible: !trayItem.iconAvailable
                color: Theme.surfaceContainerHigh

                Text {
                    anchors.centerIn: parent
                    text: {
                        var label = trayItem.modelData.title || trayItem.modelData.id || "?"
                        return label.charAt(0).toUpperCase()
                    }
                    color: Theme.textSecondary
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.fontMono
                }
            }

            StateLayer {
                hitMargin: 2
                onTapped: {
                    // Some items are menu-only and do nothing on activate.
                    if (trayItem.modelData.onlyMenu) root.openMenu(trayItem)
                    else trayItem.modelData.activate()
                }
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.openMenu(trayItem)
            }

            TapHandler {
                acceptedButtons: Qt.MiddleButton
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: trayItem.modelData.secondaryActivate()
            }
        }
    }

    function openMenu(item) {
        if (!item.modelData.hasMenu || !root.menuWindow) return
        var point = item.mapToItem(null, item.width / 2, item.height)
        item.modelData.display(root.menuWindow, Math.round(point.x), Math.round(point.y))
    }
}
