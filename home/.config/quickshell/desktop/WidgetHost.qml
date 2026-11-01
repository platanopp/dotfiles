import QtQuick
import qs.services

// One desktop widget, laid out at its kind's size and scaled by `size` as a whole
// (distance-field text stays sharp). The desktop, the picker's copies, its previews
// and the dragged one are all this.
Item {
    id: host

    property string kind: ""
    property bool live: true
    property var bar: null
    property real size: 1
    property real glass: Widgets.defaultGlass

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
    Binding { target: loader.item; property: "glassAlpha"; value: host.glass; when: loader.item !== null }
}
