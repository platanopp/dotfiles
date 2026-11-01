import QtQuick
import qs.config

// The shell's spring: a NumberAnimation that runs a little past its target
// and settles (see Theme's springs).
//
// Behavior on x { Elastic {} }              panels, cards, overlays
// Behavior on x { Elastic { small: true } } knobs, indicators, chips
//
// Spatial properties only: never opacity, nor a size shrinking towards zero,
// which would overshoot below it.
NumberAnimation {
    property bool small: false

    duration: small ? Theme.durSpringSmall : Theme.durSpring
    easing.type: Easing.OutBack
    easing.overshoot: small ? Theme.springOvershootSmall : Theme.springOvershoot
}
