import QtQuick
import qs.services

// One desktop widget of a given kind, at the size its kind is laid out for
// times `size`. The desktop layer, the picker's editable copies, its previews
// and the one being dragged out are all this, so they are the same drawing.
//
// The widget is laid out at its kind's own size and scaled as a whole, never
// laid out bigger: the text is drawn from distance fields and the rest are
// rectangles, so it stays sharp at any size the picker allows.
Item {
    id: host

    property string kind: ""
    property bool live: true
    property var bar: null
    property real size: 1

    readonly property var spec: Widgets.spec(host.kind)

    implicitWidth: host.spec ? Math.round(host.spec.w * host.size) : 0
    implicitHeight: host.spec ? Math.round(host.spec.h * host.size) : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
        id: loader
        width: host.spec ? host.spec.w : 0
        height: host.spec ? host.spec.h : 0
        scale: host.size
        transformOrigin: Item.TopLeft
        source: host.spec ? "widgets/" + host.spec.file + ".qml" : ""
        asynchronous: false
    }

    Binding { target: loader.item; property: "live"; value: host.live; when: loader.item !== null }
    Binding { target: loader.item; property: "bar"; value: host.bar; when: loader.item !== null }
}
