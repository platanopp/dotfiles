pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Native notification daemon. Replaces the dunstctl calls the shell used to
// make, which silently did nothing because dunst is not installed.
Singleton {
    id: root

    // Suppresses everything but Critical.
    property bool dnd: false

    readonly property int maxVisible: 4
    readonly property int maxQueued: 20

    // Live notifications, newest first.
    property var list: []

    readonly property var visibleList: list.slice(0, maxVisible)
    readonly property int count: list.length

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
        wrapper.destroy()
    }

    // Snapshot of a notification. The daemon's object can be freed once the
    // app closes it, so the fields the UI binds to are copied up front.
    component Notif: QtObject {
        id: wrapper

        property var notification
        property bool gone: false

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
            if (root.dnd && notif.urgency !== NotificationUrgency.Critical) {
                notif.dismiss()
                return
            }

            notif.tracked = true

            var wrapper = notifComponent.createObject(root, { notification: notif })
            if (!wrapper) return

            var queued = [wrapper].concat(root.list)
            // Drop the oldest past the cap so a burst cannot grow unbounded.
            var overflow = queued.slice(root.maxQueued)
            root.list = queued.slice(0, root.maxQueued)
            for (var i = 0; i < overflow.length; i++) root.dismiss(overflow[i])
        }
    }
}
