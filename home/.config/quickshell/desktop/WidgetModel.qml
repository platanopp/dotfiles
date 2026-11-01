import QtQuick
import qs.services

// One monitor's widgets as a ListModel kept in step with Widgets.placed by id,
// touching only rows that changed: a Repeater over the array rebuilt every widget on
// any move. Moves set wx/wy, resizes ws.
ListModel {
    id: model

    property string screenName: ""

    function sync() {
        var want = model.screenName.length > 0 ? Widgets.onScreen(model.screenName) : []
        var byId = {}
        for (var i = 0; i < want.length; i++) byId[want[i].id] = want[i]

        for (var r = model.count - 1; r >= 0; r--) {
            var row = model.get(r)
            var w = byId[row.uid]
            if (!w) {
                model.remove(r)
                continue
            }
            if (row.wx !== w.x) model.setProperty(r, "wx", w.x)
            if (row.wy !== w.y) model.setProperty(r, "wy", w.y)
            var size = Widgets.sizeOf(w)
            if (row.ws !== size) model.setProperty(r, "ws", size)
            delete byId[row.uid]
        }
        for (var j = 0; j < want.length; j++) {
            var n = want[j]
            if (byId[n.id]) model.append({ uid: n.id, kind: n.kind, wx: n.x, wy: n.y, ws: Widgets.sizeOf(n) })
        }
    }

    onScreenNameChanged: model.sync()
    Component.onCompleted: model.sync()

    property Connections watch: Connections {
        target: Widgets
        function onPlacedChanged() { model.sync() }
    }
}
