import QtQuick
import qs.services

// One desktop widget of a given kind, at the size its kind is laid out for.
// The desktop layer, the picker's editable copies, its previews and the one
// being dragged out are all this, so they are the same drawing.
Item {
    id: host

    property string kind: ""
    property bool live: true
    property var bar: null

    readonly property var spec: Widgets.spec(host.kind)

    implicitWidth: host.spec ? host.spec.w : 0
    implicitHeight: host.spec ? host.spec.h : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
        id: loader
        anchors.fill: parent
        source: host.spec ? "widgets/" + host.spec.file + ".qml" : ""
        asynchronous: false
    }

    Binding { target: loader.item; property: "live"; value: host.live; when: loader.item !== null }
    Binding { target: loader.item; property: "bar"; value: host.bar; when: loader.item !== null }
}
