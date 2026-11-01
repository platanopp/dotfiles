pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Native notification daemon. Everything goes to the centre (the control pill's bell) until
// cleared or withdrawn; a toast is only how it arrives. Do not disturb keeps toasts away (all
// but Critical). The views read two ListModels of keys (`model` for the centre, `popups` for
// toasts), changed a row at a time: a JS array rebuilt every view on each change and restarted
// every toast's countdown and entrance.
Singleton {
    id: root

    // No toasts but Critical; the centre still gets everything.
    property bool dnd: false
    function toggleDnd() { root.dnd = !root.dnd }

    // Toasts on screen at once; the rest wait, their countdown not started until they show.
    readonly property int maxVisible: 4
    // How long a toast stays, in ms, counted while it shows and not hovered.
    readonly property int lifetime: 5000
    // The centre's length; past it the oldest go.
    readonly property int maxQueued: 60

    // Keys, newest first.
    readonly property ListModel model: ListModel {}
    readonly property ListModel popups: ListModel {}

    readonly property int count: root.model.count
    // Arrived since the centre was last looked at.
    property int unread: 0

    // key -> Notif
    property var byKey: ({})
    property int nextKey: 1

    function get(key) { return root.byKey[key] || null }

    // Every notification in the centre, newest first, as objects.
    function all() {
        var out = []
        for (var i = 0; i < root.model.count; i++) {
            var w = root.get(root.model.get(i).key)
            if (w) out.push(w)
        }
        return out
    }

    function indexIn(listModel, key) {
        for (var i = 0; i < listModel.count; i++)
            if (listModel.get(i).key === key) return i
        return -1
    }

    // A toast that has had its time: off the screen, still in the centre. Marked `leaving` so
    // its card animates out and calls finishLeave; a waiting toast goes at once, and a timer
    // covers a card that never calls back.
    function expire(wrapper) {
        if (!wrapper) return
        wrapper.popup = false
        var i = root.indexIn(root.popups, wrapper.key)
        if (i === -1) return
        if (i >= root.maxVisible) {
            root.popups.remove(i)
            return
        }
        if (wrapper.leaving) return
        wrapper.leaving = true
        leaveLater.createObject(root, { key: wrapper.key })
    }

    function finishLeave(key) {
        var w = root.get(key)
        if (w && !w.leaving) return             // raised again meanwhile
        var i = root.indexIn(root.popups, key)
        if (i !== -1) root.popups.remove(i)
        if (w) w.leaving = false
    }

    Component {
        id: leaveLater
        Timer {
            property int key
            interval: 900
            running: true
            onTriggered: {
                root.finishLeave(key)
                destroy()
            }
        }
    }

    // Up as a toast again (new, or just updated by its app), its
    // countdown restarting when it shows.
    function raise(wrapper) {
        if (!wrapper || wrapper.gone) return
        var quiet = root.centreOpen
            || (root.dnd && wrapper.urgency !== NotificationUrgency.Critical)
        wrapper.expiresAt = 0
        wrapper.pausedAt = 0
        wrapper.leaving = false                 // updated on its way out: it stays
        if (quiet) {
            root.expire(wrapper)
            return
        }
        wrapper.popup = true
        var i = root.indexIn(root.popups, wrapper.key)
        if (i === 0) return
        if (i > 0) root.popups.move(i, 0, 1)
        else root.popups.insert(0, { key: wrapper.key })
    }

    function markRead() { root.unread = 0 }

    // Set while the centre is open: toasts would repeat what it shows, so the ones
    // up go and new ones go straight in.
    property bool centreOpen: false
    onCentreOpenChanged: {
        if (!root.centreOpen) return
        var up = root.all()
        for (var i = 0; i < up.length; i++) up[i].popup = false
        root.popups.clear()
        root.unread = 0
    }

    // User-initiated close, through the daemon so the app hears of it;
    // onClosed then removes the wrapper.
    function dismiss(wrapper) {
        if (!wrapper || wrapper.gone) return
        if (wrapper.notification) wrapper.notification.dismiss()
        else root._drop(wrapper)
    }

    function dismissAll() {
        var every = root.all()
        for (var i = 0; i < every.length; i++) root.dismiss(every[i])
        root.unread = 0
    }

    // Removes a wrapper whose notification is already closed.
    function _drop(wrapper) {
        if (!wrapper || wrapper.gone) return
        // A toast on screen leaves animated, like a timed-out one; the rest
        // of the removal doesn't wait.
        var p = root.indexIn(root.popups, wrapper.key)
        if (p !== -1 && p < root.maxVisible && !wrapper.leaving) {
            wrapper.leaving = true
            leaveLater.createObject(root, { key: wrapper.key })
        } else if (p !== -1) {
            root.popups.remove(p)
        }
        wrapper.gone = true
        var m = root.indexIn(root.model, wrapper.key)
        if (m !== -1) root.model.remove(m)
        var next = Object.assign({}, root.byKey)
        delete next[wrapper.key]
        root.byKey = next
        // Later, so a view still drawing its last frame is not left pointing at nothing.
        destroyLater.createObject(root, { target: wrapper })
    }

    Component {
        id: destroyLater
        Timer {
            property var target
            interval: 1000
            running: true
            onTriggered: {
                if (target) target.destroy()
                destroy()
            }
        }
    }

    // One notification. The daemon's object can be freed once the app closes it, so the shown
    // fields are copied, and copied again when the app replaces the text in place.
    component Notif: QtObject {
        id: wrapper

        property int key: 0
        property var notification
        property bool gone: false
        // Showing as a toast (see expire); false from the start under DND.
        property bool popup: true
        // When it arrived, for the centre's "5m ago".
        property date time: new Date()

        // On its way off the screen: its card is animating out (see expire).
        property bool leaving: false

        // Its toast's countdown, in Date.now() ms: when it runs out (0 until first
        // shown), and when a hover paused it.
        property real expiresAt: 0
        property real pausedAt: 0

        property string summary: ""
        property string body: ""
        property string appName: ""
        property string appIcon: ""
        property string image: ""
        property int urgency: NotificationUrgency.Normal
        property int expireTimeout: -1
        property var actions: []

        readonly property Connections conn: Connections {
            target: wrapper.notification
            function onClosed() { root._drop(wrapper) }
            // Replaced by its app (a download's progress, the next track): new
            // text, and the toast up again.
            function onSummaryChanged() { wrapper.copy(); root.raise(wrapper) }
            function onBodyChanged() { wrapper.copy(); root.raise(wrapper) }
            function onImageChanged() { wrapper.copy() }
            function onAppIconChanged() { wrapper.copy() }
            function onActionsChanged() { wrapper.copy() }
        }

        function invoke(identifier) {
            for (var i = 0; i < wrapper.actions.length; i++) {
                if (wrapper.actions[i].identifier === identifier) {
                    wrapper.actions[i].invoke()
                    return
                }
            }
        }

        function copy() {
            var n = wrapper.notification
            if (!n) return
            wrapper.summary = n.summary
            wrapper.body = n.body
            wrapper.appName = n.appName
            wrapper.appIcon = n.appIcon
            wrapper.image = n.image
            wrapper.urgency = n.urgency
            wrapper.expireTimeout = n.expireTimeout
            var out = []
            var src = n.actions
            var len = src ? src.length : 0
            for (var i = 0; i < len; i++) {
                var a = src[i]
                if (!a) continue
                // Bind the action object into the closure, so invoking it later does not
                // depend on the loop variable.
                out.push({
                    identifier: a.identifier,
                    text: a.text,
                    invoke: (function (action) { return function () { action.invoke() } })(a)
                })
            }
            wrapper.actions = out
        }

        Component.onCompleted: wrapper.copy()
    }

    Component {
        id: notifComponent
        Notif {}
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: function (notif) {
            notif.tracked = true

            var key = root.nextKey++
            var wrapper = notifComponent.createObject(root, { notification: notif, key: key, popup: false })
            if (!wrapper) return

            var next = Object.assign({}, root.byKey)
            next[key] = wrapper
            root.byKey = next
            root.model.insert(0, { key: key })
            root.raise(wrapper)
            if (!root.centreOpen) root.unread = Math.min(root.unread + 1, root.model.count)

            // Drop the oldest past the cap so a burst cannot grow unbounded.
            while (root.model.count > root.maxQueued) {
                var old = root.get(root.model.get(root.model.count - 1).key)
                if (!old) {
                    root.model.remove(root.model.count - 1)
                    continue
                }
                // Dropped now: the app's "closed" comes back later, and the
                // loop cannot wait for it.
                if (old.notification) old.notification.dismiss()
                root._drop(old)
            }
        }
    }
}
