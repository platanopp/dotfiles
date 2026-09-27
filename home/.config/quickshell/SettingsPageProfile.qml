import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets

// Settings -> Profile: the picture the control panel (and greeters) show for
// whoever is logged in. Chosen from a small browser of the user's own images,
// right here -- a separate file dialog would take focus and close the panel.
// Picking one opens it for framing -- drag to move, wheel or slider to zoom,
// inside the circle it will be shown in -- and Save has scripts/avatar.py
// cut that square and write ~/.face. The picture in use can be framed again
// the same way (Adjust): the script keeps what it was cut from.
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

    // ── Framing ──────────────────────────────────────────────────────────
    // The picture being framed ("" when not), and the framing: zoom 1 is
    // the largest square the picture holds; x, y the square's centre as
    // fractions of the picture's width and height.
    property string editing: ""
    property bool editingCurrent: false
    property real editZoom: 1
    property real editX: 0.5
    property real editY: 0.5

    function frame(path, current, zoom, x, y) {
        page.editing = path
        page.editingCurrent = current
        page.editZoom = zoom
        page.editX = x
        page.editY = y
    }

    function save() {
        if (page.editingCurrent) AppState.adjustAvatar(page.editZoom, page.editX, page.editY)
        else {
            page.lastPicked = page.editing
            AppState.setAvatar(page.editing, page.editZoom, page.editX, page.editY)
        }
        page.editing = ""
    }

    onFolderChanged: page.limit = 36

    function shortPath(p) { return p.indexOf(page.home) === 0 ? "~" + p.slice(page.home.length) : p }
    function parentOf(p) { var i = p.lastIndexOf("/"); return i > 0 ? p.slice(0, i) : "/" }

    // ── Who ──────────────────────────────────────────────────────────────
    Rectangle {
        visible: page.editing.length === 0
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
                        : "Pick an image below to frame it"
                    color: AppState.avatarError.length > 0 ? Theme.error : Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                }

                Row {
                    Layout.topMargin: 6
                    spacing: 6
                    visible: AppState.avatarPath.length > 0

                    PillButton {
                        icon: "\u{F019E}"
                        text: "Adjust"
                        available: !AppState.avatarBusy && AppState.avatarFraming.path.length > 0
                        onClicked: page.frame(AppState.avatarFraming.path, true, AppState.avatarFraming.zoom,
                                              AppState.avatarFraming.x, AppState.avatarFraming.y)
                    }

                    PillButton {
                        icon: "\u{F0A7A}"
                        text: "Remove"
                        available: !AppState.avatarBusy
                        onClicked: AppState.removeAvatar()
                    }
                }
            }
        }
    }

    // ── Framing the picture ──────────────────────────────────────────────
    Rectangle {
        id: editor
        visible: page.editing.length > 0
        width: parent.width
        height: 300
        radius: 22
        color: Theme.surfaceContainer

        // The picture's size as loaded; the framing is in fractions of it,
        // so the scaled-down copy shown here frames the same as the file.
        readonly property real iw: shown.implicitWidth
        readonly property real ih: shown.implicitHeight
        readonly property bool ready: shown.status === Image.Ready && iw > 0 && ih > 0
        readonly property real side: Math.min(iw, ih) / page.editZoom
        // Screen pixels per picture pixel, so the square fills the viewport.
        readonly property real k: ready ? viewport.width / side : 1

        // A framing kept inside the picture.
        function clamp(f, total) {
            var c = Math.min(Math.max(f * total, editor.side / 2), total - editor.side / 2)
            return c / total
        }
        function settle() {
            if (!editor.ready) return
            page.editX = editor.clamp(page.editX, editor.iw)
            page.editY = editor.clamp(page.editY, editor.ih)
        }
        onReadyChanged: editor.settle()

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 24

            ClippingRectangle {
                id: viewport
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260
                radius: 18
                color: Theme.background

                Image {
                    id: shown
                    // A new name each time, so a picture framed and saved
                    // before is read again rather than served from cache.
                    source: page.editing.length > 0 ? "file://" + page.editing + "?v=" + AppState.avatarVersion : ""
                    cache: false
                    asynchronous: true
                    sourceSize: Qt.size(1200, 1200)
                    visible: editor.ready
                    width: editor.iw * editor.k
                    height: editor.ih * editor.k
                    x: viewport.width / 2 - page.editX * editor.iw * editor.k
                    y: viewport.height / 2 - page.editY * editor.ih * editor.k
                    smooth: true
                    mipmap: true
                }

                // Outside the circle, dimmed: what will not be in the picture.
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d")
                        c.reset()
                        c.fillStyle = Qt.rgba(0, 0, 0, 0.55)
                        c.fillRect(0, 0, width, height)
                        c.globalCompositeOperation = "destination-out"
                        c.beginPath()
                        c.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 2)
                        c.fill()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.alpha("#ffffff", 0.8)
                }

                Text {
                    anchors.centerIn: parent
                    visible: !editor.ready
                    text: shown.status === Image.Error ? "Cannot open this image" : "Loading…"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: editor.ready
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    preventStealing: true
                    property real startX: 0
                    property real startY: 0
                    property real fromX: 0
                    property real fromY: 0

                    onPressed: mouse => {
                        startX = mouse.x; startY = mouse.y
                        fromX = page.editX; fromY = page.editY
                    }
                    // Dragging the picture moves it under the circle: the
                    // square's centre goes the other way.
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        page.editX = editor.clamp(fromX - (mouse.x - startX) / (editor.k * editor.iw), editor.iw)
                        page.editY = editor.clamp(fromY - (mouse.y - startY) / (editor.k * editor.ih), editor.ih)
                    }
                    onWheel: wheel => {
                        var z = page.editZoom * Math.pow(1.12, wheel.angleDelta.y / 120)
                        page.editZoom = Math.max(1, Math.min(6, z))
                        editor.settle()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 14

                Text {
                    text: "Frame your picture"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.bold: true
                    font.family: Theme.fontMono
                }

                Text {
                    Layout.fillWidth: true
                    text: "Drag to move · scroll to zoom"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    IconGlyph {
                        text: "\u{F0349}"
                        size: Theme.iconSmall
                        color: Theme.textMuted
                    }

                    SettingsSlider {
                        Layout.fillWidth: true
                        compact: true
                        live: true
                        from: 1; to: 6; step: 0.01
                        value: page.editZoom
                        onMoved: v => { page.editZoom = v; editor.settle() }
                    }

                    IconGlyph {
                        text: "\u{F0415}"
                        size: Theme.iconSmall
                        color: Theme.textMuted
                    }
                }

                Row {
                    spacing: 8

                    PillButton {
                        text: "Cancel"
                        onClicked: page.editing = ""
                    }

                    PillButton {
                        text: AppState.avatarBusy ? "…" : "Save"
                        emphasis: true
                        available: editor.ready && !AppState.avatarBusy
                        onClicked: page.save()
                    }

                    PillButton {
                        text: "Reset"
                        available: page.editZoom !== 1 || page.editX !== 0.5 || page.editY !== 0.5
                        onClicked: { page.editZoom = 1; page.editX = 0.5; page.editY = 0.5; editor.settle() }
                    }
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
                            else if (!AppState.avatarBusy) page.frame(entry.filePath, false, 1, 0.5, 0.5)
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
