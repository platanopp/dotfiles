pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Native notification daemon. Replaces the dunstctl calls the shell used to
// make, which silently did nothing because dunst is not installed.
//
// Every notification goes to the centre (the bell in the control pill) and
// stays there until it is cleared or the app withdraws it. A toast is only
// how it arrives: when the toast times out the notification leaves the
// screen, not the centre. Do not disturb keeps the toasts away (all but
// Critical) and still files everything in the centre, quietly.
Singleton {
    id: root

    // No toasts but Critical; the centre still gets everything.
    property bool dnd: false

    readonly property int maxVisible: 4
    // The centre's length; past it the oldest go.
    readonly property int maxQueued: 60

    // Every notification in the centre, newest first.
    property var list: []

    // The ones showing as toasts right now, newest first.
    property var visibleList: []
    readonly property int count: list.length
    // Arrived since the centre was last looked at.
    property int unread: 0

    function _refresh() {
        root.visibleList = root.list.filter(w => w.popup).slice(0, root.maxVisible)
    }

    // A toast that has had its time: off the screen, still in the centre.
    function expire(wrapper) {
        if (!wrapper || wrapper.gone || !wrapper.popup) return
        wrapper.popup = false
        root._refresh()
    }

    function markRead() { root.unread = 0 }

    // Set while the centre is open: toasts would only repeat what is on it,
    // on top of it -- the ones up go, and new ones arrive straight in.
    property bool centreOpen: false
    onCentreOpenChanged: {
        if (!root.centreOpen) return
        for (var i = 0; i < root.list.length; i++) root.list[i].popup = false
        root._refresh()
        root.unread = 0
    }

    // User-initiated close. Going through the daemon makes the sending app
    // aware; onClosed then removes the wrapper.
    function dismiss(wrapper) {
        if (!wrapper || wrapper.gone) return
        if (wrapper.notification) wrapper.notification.dismiss()
        else _drop(wrapper)
    }

    function dismissAll() {
        var copy = root.list.slice()
        for (var i = 0; i < copy.length; i++) root.dismiss(copy[i])
        root.unread = 0
    }

    // Removes a wrapper whose notification is already closed.
    function _drop(wrapper) {
        if (!wrapper || wrapper.gone) return
        wrapper.gone = true
        var copy = root.list.slice()
        var idx = copy.indexOf(wrapper)
        if (idx !== -1) {
            copy.splice(idx, 1)
            root.list = copy
        }
        root._refresh()
        wrapper.destroy()
    }

    // Snapshot of a notification. The daemon's object can be freed once the
    // app closes it, so the fields the UI binds to are copied up front.
    component Notif: QtObject {
        id: wrapper

        property var notification
        property bool gone: false
        // Showing as a toast (see expire); false from the start under DND.
        property bool popup: true
        // When it arrived, for the centre's "5m ago".
        property date time: new Date()

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
        }

        function invoke(identifier) {
            for (var i = 0; i < wrapper.actions.length; i++) {
                if (wrapper.actions[i].identifier === identifier) {
                    wrapper.actions[i].invoke()
                    return
                }
            }
        }

        Component.onCompleted: {
            if (!notification) return
            summary = notification.summary
            body = notification.body
            appName = notification.appName
            appIcon = notification.appIcon
            image = notification.image
            urgency = notification.urgency
            expireTimeout = notification.expireTimeout

            var out = []
            var src = notification.actions
            var len = src ? src.length : 0
            for (var i = 0; i < len; i++) {
                var a = src[i]
                if (!a) continue
                // Bind the action object into the closure so invoking it later
                // does not depend on the loop variable.
                out.push({
                    identifier: a.identifier,
                    text: a.text,
                    invoke: (function (action) { return function () { action.invoke() } })(a)
                })
            }
            actions = out
        }
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

            var quiet = root.centreOpen
                || (root.dnd && notif.urgency !== NotificationUrgency.Critical)
            var wrapper = notifComponent.createObject(root, { notification: notif, popup: !quiet })
            if (!wrapper) return

            var queued = [wrapper].concat(root.list)
            // Drop the oldest past the cap so a burst cannot grow unbounded.
            var overflow = queued.slice(root.maxQueued)
            root.list = queued.slice(0, root.maxQueued)
            if (!root.centreOpen) root.unread = Math.min(root.unread + 1, root.list.length)
            root._refresh()
            for (var i = 0; i < overflow.length; i++) root.dismiss(overflow[i])
        }
    }
}
