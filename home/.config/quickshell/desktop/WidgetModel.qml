import QtQuick
import qs.services

// One monitor's widgets as a ListModel, kept in step with Widgets.placed by
// id. A Repeater over the plain array rebuilt every widget whenever any one
// moved -- the covers reloaded, the spectrum dropped to nothing and came
// back -- where this only touches the rows that changed: moved widgets get
// new wx and wy (not x and y, which every delegate already has), gone ones
// are removed, new ones appended.
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
            delete byId[row.uid]
        }
        for (var j = 0; j < want.length; j++) {
            var n = want[j]
            if (byId[n.id]) model.append({ uid: n.id, kind: n.kind, wx: n.x, wy: n.y })
        }
    }

    onScreenNameChanged: model.sync()
    Component.onCompleted: model.sync()

    property Connections watch: Connections {
        target: Widgets
        function onPlacedChanged() { model.sync() }
    }
}
