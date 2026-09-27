import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets

// Settings -> Profile: the picture the control panel (and greeters) show for
// whoever is logged in. Chosen from a small browser of the user's own images,
// right here -- a separate file dialog would take focus and close the panel.
// scripts/avatar.py crops the choice to a square and writes ~/.face.
Column {
    id: page
    spacing: 24

    readonly property string home: Quickshell.env("HOME")
    // Where browsing starts: ~/Pictures if there is one, else home.
    property string folder: page.home + "/Pictures"
    // Thumbnails are cheap, not free: a folder of screenshots can hold
    // hundreds. More on request.
    property int limit: 36
    // ~/.face is a cropped copy, so the file it came from is only known for
    // a pick made here.
    property string lastPicked: ""

    onFolderChanged: page.limit = 36

    function shortPath(p) { return p.indexOf(page.home) === 0 ? "~" + p.slice(page.home.length) : p }
    function parentOf(p) { var i = p.lastIndexOf("/"); return i > 0 ? p.slice(0, i) : "/" }

    // ── Who ──────────────────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        height: 132
        radius: 22
        color: Theme.surfaceContainer

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 20

            Item {
                Layout.preferredWidth: 96
                Layout.preferredHeight: 96

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.alpha(Theme.foreground, 0.35)
                }

                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: width / 2
                    color: Theme.surfaceContainerHigh

                    Image {
                        id: current
                        anchors.fill: parent
                        source: AppState.avatarSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: 256
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: current.status !== Image.Ready
                        text: AppState.username.length > 0 ? AppState.username.charAt(0).toUpperCase() : "?"
                        color: Theme.textPrimary
                        font.pixelSize: 36
                        font.bold: true
                        font.family: Theme.fontMono
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: AppState.username
                    color: Theme.textPrimary
                    font.pixelSize: 20
                    font.bold: true
                    font.family: Theme.fontMono
                }

                Text {
                    Layout.fillWidth: true
                    text: AppState.avatarError.length > 0 ? AppState.avatarError
                        : AppState.avatarBusy ? "Saving…"
                        : "Pick an image below"
                    color: AppState.avatarError.length > 0 ? Theme.error : Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                }

                PillButton {
                    Layout.topMargin: 6
                    visible: AppState.avatarPath.length > 0
                    icon: "\u{F0A7A}"
                    text: "Remove"
                    available: !AppState.avatarBusy
                    onClicked: AppState.removeAvatar()
                }
            }
        }
    }

    // ── Browser ──────────────────────────────────────────────────────────
    SettingsGroup {
        width: parent.width
        title: "Choose a picture"

        // Where we are, and the way up.
        SettingsRow {
            icon: "\u{F024B}"
            title: page.shortPath(page.folder)

            Row {
                spacing: 6

                PillButton {
                    icon: "\u{F02DC}"
                    text: "Home"
                    available: page.folder !== page.home
                    onClicked: page.folder = page.home
                }

                PillButton {
                    icon: "\u{F005D}"
                    text: "Up"
                    available: page.folder !== "/"
                    onClicked: page.folder = page.parentOf(page.folder)
                }
            }
        }
    }

    FolderListModel {
        id: files
        folder: "file://" + page.folder
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.gif", "*.PNG", "*.JPG", "*.JPEG"]
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    Grid {
        id: grid
        width: parent.width
        columns: Math.max(3, Math.floor((width + spacing) / (112 + spacing)))
        spacing: 10
        readonly property real cell: (width - spacing * (columns - 1)) / columns

        Repeater {
            model: files

            Item {
                id: entry
                required property int index
                required property string fileName
                required property string filePath
                required property bool fileIsDir

                visible: entry.index < page.limit
                width: grid.cell
                height: entry.visible ? grid.cell + 22 : 0

                ClippingRectangle {
                    id: thumb
                    width: grid.cell
                    height: grid.cell
                    radius: 16
                    color: Theme.surfaceContainer
                    scale: tap.pressed ? 0.96 : hover.hovered ? 1.03 : 1

                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutCubic } }

                    IconGlyph {
                        anchors.centerIn: parent
                        visible: entry.fileIsDir
                        text: "\u{F024B}"
                        size: 34
                        color: Theme.textSecondary
                    }

                    Image {
                        anchors.fill: parent
                        visible: !entry.fileIsDir
                        source: entry.fileIsDir || !entry.visible ? "" : "file://" + entry.filePath
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 224
                        sourceSize.height: 224
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.foreground
                        opacity: hover.hovered ? 0.08 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                }

                // The picture in use, ringed. Outside the clip so the ring is
                // not cut in half.
                Rectangle {
                    anchors.fill: thumb
                    radius: thumb.radius
                    scale: thumb.scale
                    color: "transparent"
                    visible: AppState.avatarVersion >= 0 && AppState.avatarPath.length > 0
                             && entry.filePath === page.lastPicked
                    border.width: 2
                    border.color: Theme.foreground
                }

                Item {
                    anchors.fill: thumb
                    TapHandler {
                        id: tap
                        onTapped: {
                            if (entry.fileIsDir) page.folder = entry.filePath
                            else if (!AppState.avatarBusy) {
                                page.lastPicked = entry.filePath
                                AppState.setAvatar(entry.filePath)
                            }
                        }
                    }
                }

                Text {
                    anchors.top: thumb.bottom
                    anchors.topMargin: 5
                    width: parent.width
                    text: entry.fileName
                    color: entry.fileIsDir ? Theme.textPrimary : Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontMono
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: files.status === FolderListModel.Ready && files.count === 0
        text: "No folders or images here"
        color: Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontMono
        horizontalAlignment: Text.AlignHCenter
    }

    PillButton {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: files.count > page.limit
        text: "Show " + Math.min(36, files.count - page.limit) + " more"
        onClicked: page.limit += 36
    }
}
