import QtQuick
import qs.config

// The card every desktop widget is drawn on: the wallpaper's hue at a dark
// value (Theme.widgetSurface), opaque, the panels' largest radius. No shadow
// at rest -- the widgets lie on the desktop, they do not float over it; the
// picker gives one only to the widget being carried.
//
// Each widget sets `live` off while its monitor's desktop is covered, and the
// ones that redraw on their own (the spectrum, the meters, a song's progress)
// stop with it. `bar` is the monitor's bar, for the media player it follows.
Rectangle {
    // Off until the host says otherwise, so a widget does not subscribe to
    // anything for the moment between being created and being told it is
    // covered.
    property bool live: false
    property var bar: null

    color: Theme.widgetSurface
    radius: Theme.radiusXLarge
}
